# GoToKart — Infrastructure

## Live Deployment

```
http://34.227.190.40          → GoToKart storefront (served by Nginx)
http://34.227.190.40/api/*    → Spring Boot backend (proxied by Nginx)

EC2 Instance  : Amazon Linux 2023  (ip-172-31-21-128)
Instance type : t2.micro (or your chosen type)
Region        : us-east-1
```

## Architecture

```
Browser → http://34.227.190.40
               │
         Nginx :80  (Docker)
          ├── /          → static frontend files
          └── /api/*     → http://backend:8080  (Docker internal)
               │
         Spring Boot :8080  (Docker)
               │
         MariaDB 10.11 :3306  (Docker)
```

## Repositories

| Repo | Purpose |
|------|---------|
| `frontend` | HTML/CSS/JS storefront |
| `backend` | Spring Boot REST API |
| `infra` | Dockerfile, Nginx config, Docker Compose files, CI/CD workflow |
| `docs` | Nextra documentation site |

---

## EC2 — One-time Server Setup

Run these once after creating a fresh Amazon Linux 2023 EC2 instance:

```bash
# 1. Install Docker
sudo yum install -y docker git
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
# 4. Add swap space (prevents OOM on t2.micro)
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

# 7. Build and start
cd infra
docker compose up -d --build
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
| `docker-compose.yaml` | Production compose — MariaDB + Backend + Nginx |
| `docker-compose.local.yml` | Local dev compose — same stack on your laptop |
| `nginx.conf` | Nginx: serves frontend static files + proxies `/api/` to backend |
| `.github/workflows/deploy.yml` | GitHub Actions — auto-deploy via SSM on push to main |

---

## Docker Services

| Container | Image | Port | Notes |
|-----------|-------|------|-------|
| `gotokart-mysql` | `mariadb:10.11` | 3306 (internal) | MySQL-compatible, no ioctl bug on AL2023 |
| `gotokart-backend` | `infra-backend` (built) | 8080 (internal) | Spring Boot, 350m mem limit |
| `gotokart-nginx` | `nginx:alpine` | 80 → public | Serves frontend + API proxy |

> **Why MariaDB instead of MySQL?** The official `mysql:8.x` Docker image crashes on Amazon Linux 2023's kernel with `Inappropriate ioctl for device`. MariaDB 10.11 is fully MySQL-compatible and works perfectly.

---

## Nginx Routing

| Path | Destination |
|------|-------------|
| `/` | Static files from `infra/frontend/` |
| `/api/*` | Proxied to `http://backend:8080/api/` |

---

## Useful Commands on EC2

```bash
# Check all containers are running
docker compose ps

# Watch backend logs live
docker logs -f gotokart-backend

# Watch MariaDB logs
docker logs -f gotokart-mysql

# Restart a single service
docker compose restart nginx

# Full restart
docker compose down && docker compose up -d

# Wipe DB and restart fresh (re-seeds 102 products + admin)
docker compose down -v && docker compose up -d --build
```

---

## EC2 Security Group Rules

| Type | Port | Source |
|------|------|--------|
| SSH | 22 | Your IP |
| HTTP | 80 | 0.0.0.0/0 |

---

## Local Development

```bash
cd infra
docker compose -f docker-compose.local.yml up --build
```

Opens `http://localhost` with the full stack (Nginx + Backend + MariaDB).

---

## Default Credentials

| Service | Value |
|---------|-------|
| DB name | `gotokart` |
| DB password (root) | `Root@1234` |
| Admin email | `admin@gotokart.com` |
| Admin password | `admin123` |

> Admin user is auto-created by `DataInitializer` on every backend startup if not found.
