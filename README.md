# GoToKart — Infrastructure

## Live Deployment

```
http://34.229.50.171          → GoToKart storefront (served by Nginx)
http://34.229.50.171/api/*    → Spring Boot backend (proxied by Nginx)
```

### EC2 instance

| Field | Value |
|-------|-------|
| Status | Active |
| Name | `gotokart-ecommerce` |
| Instance ID | `i-0dcb2819d4c3539f5` |
| Type | `t3.small` (2 vCPU, 2GB RAM) |
| Region | `us-east-1` (N. Virginia) |
| Public IP | `34.229.50.171` |

### Docker (**2** containers running)

| Role | Service | Port |
|------|---------|------|
| Frontend | Nginx | 80 |
| Backend | Spring Boot | 8080 |

**Network:** `infra_gotokart-net`

### Database (AWS managed, outside Docker)

| Field | Value |
|-------|-------|
| Service | **Amazon RDS for MySQL 8.0** |
| Endpoint | `gotokart-db.xxxxxxxx.us-east-1.rds.amazonaws.com` |
| Port | `3306` |
| DB name | `gotokart` |
| Auth | Username/password (stored in `infra/.env` — see below) |
| Network | Private to the VPC; security group allows port 3306 only from the EC2 SG |

## Architecture

```
┌─ Client ────────────────────────────────────────────────┐
│  User (browser)          Dev (local machine)            │
└──────────┬───────────────────────┬──────────────────────┘
           │ HTTP :80              │ git push
           │                       ▼
           │         ┌─ GitHub · gotokart org ──────────────┐
           │         │  frontend  backend  infra  docs       │
           │         └──────┬─────────┬──────────────────────┘
           │                │ push    │ push
           │                ▼         ▼
           │         ┌─ GitHub Actions CI/CD ────────────────┐
           │         │  build & test  →  deploy job           │
           │         └───────────────────┬───────────────────┘
           │                             │ docker compose up --build
           ▼                             ▼
┌─ AWS EC2 · t3.small · 34.229.50.171 ────────────────────┐
│  ┌─ Docker containers (infra_gotokart-net) ──────────┐    │
│  │  Nginx :80  ──/api/*──▶  Spring Boot :8080       │    │
│  │      │                       │                   │    │
│  │  static files                │ JDBC :3306        │    │
│  └──────────────────────────────┼──────────────────┘    │
│                                  ▼                       │
│                         ┌─ AWS RDS (MySQL 8) ──────┐     │
│                         │  gotokart-db (private)   │     │
│                         └──────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

## Repositories

| Repo | Purpose |
|------|---------|
| `frontend` | HTML/CSS/JS storefront |
| `backend` | Spring Boot REST API |
| `infra` | Dockerfile, Nginx config, Docker Compose files, CI/CD workflow |
| `docs` | Nextra documentation site |

---

## AWS RDS — one-time setup

This stack expects a MySQL 8.0 RDS instance to exist before the backend container starts.

### 1. Create the RDS instance (Console)

1. **RDS → Create database** → **Standard create**.
2. **Engine:** MySQL 8.0 (latest minor).
3. **Templates:** *Production* (or *Dev/Test* for non-prod).
4. **Settings:**
   - DB instance identifier: `gotokart-db`
   - Master username: `admin` (you'll create a less-privileged app user below)
   - Master password: store in a password manager
5. **Instance class:** `db.t4g.micro` is fine for low traffic.
6. **Storage:** 20 GB gp3, **autoscaling on**.
7. **Connectivity:**
   - VPC: same VPC as the EC2 instance
   - Public access: **No**
   - VPC security group: create new `gotokart-rds-sg` (rules added in step 2)
   - AZ: same AZ as EC2 (lower latency, lower cross-AZ cost)
8. **Database authentication:** Password authentication.
9. **Additional configuration:**
   - Initial database name: `gotokart`
   - Backups: 7-day retention
   - Encryption: **enabled** (KMS default key is fine)
10. Click **Create database** — provisioning takes ~5 minutes.

### 2. Lock down the security group

On `gotokart-rds-sg`, **inbound** rules:

| Type | Port | Source |
|------|------|--------|
| MySQL/Aurora | 3306 | `sg-xxxxxxxx` (the EC2 security group) |

No public IPs, no `0.0.0.0/0`. Outbound can stay default.

### 3. Run the bootstrap script on EC2 (recommended)

SSH onto EC2, then:

```bash
cd /home/ec2-user/gotokart/infra
git pull origin main      # picks up the new compose file + setup script
./scripts/setup-rds.sh
```

The script is idempotent. It:

- Installs the `mysql` CLI (via `mariadb105`) if missing.
- Downloads the AWS RDS CA bundle and connects with `--ssl-mode=VERIFY_IDENTITY`.
- Prompts for the master password and a new app-user password.
- Creates the `gotokart` database and the `gotokart_app` user (least-privilege; never reuses the master `admin` user).
- Writes `infra/.env` with mode `0600`.
- Brings down the old stack (including the MariaDB container) and runs `docker compose up -d --build`.
- Tails the backend logs until it sees `Started GotokartApplication`.

### Manual alternative — if you'd rather do each step by hand

```bash
mysql -h gotokart-db.ccjocguqok5t.us-east-1.rds.amazonaws.com -u admin -p
```

```sql
CREATE DATABASE gotokart CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'gotokart_app'@'%' IDENTIFIED BY 'a-strong-password';
GRANT ALL PRIVILEGES ON gotokart.* TO 'gotokart_app'@'%';
FLUSH PRIVILEGES;
EXIT;
```

```bash
cd /home/ec2-user/gotokart/infra
cp .env.example .env
nano .env       # fill in RDS_HOST, RDS_USERNAME, RDS_PASSWORD, JWT_SECRET
docker compose down && docker compose up -d --build
```

`.env` is git-ignored (`.gitignore` already excludes `.env` and `*.env`). Docker Compose loads it automatically — no `--env-file` flag needed.

### 5. (Optional) migrate existing data from the old MariaDB container

If you're switching from the previous in-container MariaDB and want to keep existing rows:

```bash
# On EC2, before tearing down the old stack
docker exec gotokart-mysql mariadb-dump -uroot -pRoot@1234 gotokart > gotokart-dump.sql

# Push the dump into RDS
mysql -h gotokart-db.xxxxxxxx.us-east-1.rds.amazonaws.com -u gotokart_app -p gotokart \
  < gotokart-dump.sql
```

Otherwise, JPA's `ddl-auto=update` will create all tables on first boot and `DataInitializer` will reseed the 102 products + admin user.

---

## EC2 — One-time Server Setup

Run these once after creating a fresh Amazon Linux 2023 EC2 instance:

```bash
# 1. Install Docker
sudo yum install -y docker git mariadb105   # `mariadb105` gives us the `mysql` CLI for RDS access
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# 2. Install latest buildx + compose plugins
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL "https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-amd64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
sudo curl -SL "https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 3. Log out and back in (docker group takes effect)
exit
```

```bash
# 4. Add swap space (prevents OOM on small instances)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab

# 5. Clone all repos
mkdir -p /home/ec2-user/gotokart && cd /home/ec2-user/gotokart
git clone https://github.com/gotokart/backend.git
git clone https://github.com/gotokart/frontend.git
git clone https://github.com/gotokart/infra.git

# 6. Copy backend source into infra (Docker build context)
cp backend/pom.xml infra/
cp -r backend/src infra/src
cp -r frontend/. infra/frontend/

# 7. Configure DB and bring stack up — one-shot script
cd infra
./scripts/setup-rds.sh
```

---

## EC2 — Re-deploy After Code Changes

```bash
cd /home/ec2-user/gotokart && \
  git -C backend pull origin main && \
  git -C frontend pull origin main && \
  git -C infra pull origin main && \
  cp backend/pom.xml infra/ && \
  cp -r backend/src infra/src && \
  cp -r frontend/. infra/frontend/ && \
  cd infra && docker compose up -d --build
```

---

## Docker Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build — Maven (JDK 21) compile → JRE 21 runtime |
| `docker-compose.yaml` | Production compose — Backend + Nginx (DB is RDS, external) |
| `docker-compose.local.yml` | Local dev compose — same stack + dockerized MySQL on your laptop |
| `nginx.conf` | Nginx: serves frontend static files + proxies `/api/` to backend |
| `.github/workflows/deploy.yml` | GitHub Actions — auto-deploy via SSM on push to main |

Secrets for the workflow: `AWS_IAM_ROLE_ARN`, `AWS_REGION`, `EC2_INSTANCE_ID`. Set `EC2_INSTANCE_ID` to the live instance (`i-0dcb2819d4c3539f5` for `gotokart-ecommerce`).

---

## Docker Services

| Container | Image | Port | Notes |
|-----------|-------|------|-------|
| `gotokart-backend` | `infra-backend` (built) | 8080 (internal) | Spring Boot, 350m mem limit, connects to RDS over JDBC |
| `gotokart-nginx` | `nginx:alpine` | 80 → public | Serves frontend + API proxy |

> **No DB container in production.** The MySQL database now lives in AWS RDS (managed). Local development still uses a throwaway MySQL container — see `docker-compose.local.yml`.

---

## Nginx Routing

| Path | Destination |
|------|-------------|
| `/` | Static files from `infra/frontend/` |
| `/api/*` | Proxied to `http://backend:8080/api/` |

---

## Useful Commands on EC2

```bash
# Check containers are running
docker compose ps

# Watch backend logs live
docker logs -f gotokart-backend

# Restart a single service
docker compose restart nginx

# Full restart (no data loss — data is in RDS, not in volumes)
docker compose down && docker compose up -d

# Connect to RDS from the EC2 box
source infra/.env
mysql -h "$RDS_HOST" -u "$RDS_USERNAME" -p"$RDS_PASSWORD" "$RDS_DB_NAME"
```

---

## EC2 Security Group Rules

| Type | Port | Source |
|------|------|--------|
| SSH | 22 | Your IP |
| HTTP | 80 | 0.0.0.0/0 |
| HTTPS | 443 | 0.0.0.0/0 |

The EC2 SG must also be referenced by `gotokart-rds-sg` as the source for port 3306 (set in step 2 of the RDS setup above).

---

## Local Development

```bash
cd infra
docker compose -f docker-compose.local.yml up --build
```

Opens `http://localhost` with the full stack (Nginx + Backend + a dockerized MySQL — RDS is **not** required for local dev).

---

## Default Credentials

| Service | Value |
|---------|-------|
| DB name | `gotokart` |
| DB user (production, RDS) | `gotokart_app` (set in `infra/.env`) |
| DB password (local docker) | `Gotokart#2026Ec2` |
| Admin email | `admin@gotokart.com` |
| Admin password | `admin123` |

> Admin user is auto-created by `DataInitializer` on every backend startup if not found.

---

## Admin Dashboard

Log in as `admin@gotokart.com` to see an **Admin** link in the top nav. The
dashboard ships with eight tabs:

| Tab | What it does |
|-----|--------------|
| Overview | KPI cards (revenue, orders, users, products), low-stock list, recent-orders feed |
| Products | Searchable table; add / edit / delete; in-place stock + price changes; CSV export |
| Orders | All orders across all customers; inline status dropdown (`PLACED → SHIPPED → DELIVERED / CANCELLED`); details modal; CSV export |
| Users | Role select (USER ↔ ADMIN); soft deactivate / reactivate; CSV export. The currently logged-in admin can't change their own role or deactivate themselves. |
| Categories | Add, rename, delete categories; deletion soft-orphans the linked products. |
| Coupons | Create discount codes (1–100%), set expiry + usage limit, toggle active. Storefront integration is wired in `/api/coupons/validate?code=…` for the cart flow to call when ready. |
| Reviews | Moderate user-submitted reviews (PENDING → APPROVED / REJECTED). |
| Revenue | Chart.js bar + line charts (daily / weekly / monthly). |

### New backend endpoints

All gated by `@PreAuthorize("hasRole('ADMIN')")` unless noted.

```
GET    /api/admin/stats                          Dashboard overview KPIs
GET    /api/admin/revenue?period=daily|weekly|monthly   Time-bucketed revenue
PATCH  /api/admin/users/{id}/role                Promote / demote (ADMIN ↔ USER)
PATCH  /api/admin/users/{id}/active              Deactivate / reactivate

GET    /api/orders                               Admin-only: list every order
PATCH  /api/orders/{id}/status                   Move through PLACED/SHIPPED/DELIVERED/CANCELLED

PUT    /api/categories/{id}                      Rename category
DELETE /api/categories/{id}                      Delete category

GET    /api/coupons                              List coupons
POST   /api/coupons                              Create
PUT    /api/coupons/{id}                         Update (code is immutable)
DELETE /api/coupons/{id}                         Delete
GET    /api/coupons/validate?code=ABC123         Public — used by the cart

GET    /api/reviews                              All reviews (filter ?status=)
GET    /api/reviews/product/{productId}          Public — approved reviews for a product
POST   /api/reviews                              Public — submit a new review (PENDING)
PATCH  /api/reviews/{id}/status                  Approve / Reject
DELETE /api/reviews/{id}                         Delete
```

### Schema changes auto-applied on first boot

Hibernate `ddl-auto=update` adds three tables / one column on next backend
restart — no manual migration required:

- `users` → adds column `active BIT(1) NOT NULL DEFAULT 1` (existing rows backfill to active).
- new table `coupons` (code, discount_percent, valid_until, usage_limit, used_count, active, created_at).
- new table `reviews` (user_id, product_id, rating, comment, status, created_at).

### Security tightening shipped alongside the dashboard

- `GET /api/users` and `GET /api/users/{id}` are now `hasRole('ADMIN')` only (previously open — emails leaked).
- `User.password` is now `@JsonProperty(WRITE_ONLY)` so it never leaves the backend in a JSON response.
- `POST /api/categories` is now admin-only (previously open).
- `PUT /api/products/{id}` is now admin-only (matches the existing `POST`/`DELETE`).

### Deploy

The dashboard is just an addition to the existing `frontend/` and `backend/`
images, so the normal redeploy applies — no infra changes. On EC2 each repo
is cloned separately under `~`:

```bash
ssh ec2-user@34.229.50.171

# 1. Pull the three repos
cd ~/backend  && git pull
cd ~/frontend && git pull
cd ~/infra    && git pull

# 2. Rebuild the backend image with the new code, recreate the container.
#    --no-deps so we don't touch nginx; -d so we don't tail the log.
cd ~/infra
docker compose up -d --no-deps --build backend

# 3. Restart nginx so it picks up the new frontend bind-mount.
docker compose restart nginx

# 4. Verify
docker compose ps
curl -s http://localhost/api/products | head -c 120
```
