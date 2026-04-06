# GoToKart — Infrastructure

## Architecture

```
Frontend  → GitHub Pages  → gotokart.github.io/frontend
Backend   → Local / EC2   → http://localhost:8080
Database  → MySQL 8       → localhost:3306/gotokart
Docs      → GitHub Pages  → gotokart.github.io/docs
Pipelines → GitHub Actions
```

## Repositories

| Repo | Purpose |
|------|---------|
| `frontend` | HTML/CSS/JS storefront |
| `backend` | Spring Boot REST API |
| `infra` | Docker files, Nginx config, CI/CD workflows |
| `docs` | Nextra documentation site |

---

## Local Development

### Run everything locally with Docker

```bash
# From this directory
docker compose -f docker-compose.local.yml up --build
```

This starts:
- **MySQL 8** on port `3306` (db: `gotokart`, user: `root`, pass: `Root@1234`)
- **Spring Boot backend** on port `8080`
- **Nginx** on port `80` — serves frontend and proxies `/api/` to backend

Open `http://localhost` in your browser.

### Run backend directly (without Docker)

```bash
# Prerequisites: MySQL running at localhost:3306/gotokart
cd ../backend
mvn clean spring-boot:run
```

Then open `frontend/index.html` directly in your browser.

---

## Docker Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build — Maven compile → JRE runtime image |
| `docker-compose.yaml` | Production/EC2 compose (external DB via env vars) |
| `docker-compose.local.yml` | Local dev compose (includes MySQL container) |
| `nginx.conf` | Nginx config — serves frontend, proxies `/api/` to backend service |
| `.env.example` | Template for production environment variables |

---

## Nginx Routing

| Path | Destination |
|------|-------------|
| `/` | Serves static files from `frontend/` |
| `/api/*` | Proxied to `http://backend:8080/api/` |

---

## Production / EC2 Deployment

For EC2 deployment, copy the environment variable template:

```bash
cp .env.example .env
# Edit .env with your external MySQL connection details
docker compose up --build -d
```

Required environment variables (see `.env.example`):

```
SPRING_DATASOURCE_URL=jdbc:mysql://<host>:3306/<db>?useSSL=true&serverTimezone=UTC
SPRING_DATASOURCE_USERNAME=<username>
SPRING_DATASOURCE_PASSWORD=<password>
```

---

## CI/CD Flow

1. Push to `frontend/main` → GitHub Actions builds and publishes to GitHub Pages
2. Push to `backend/main` → Deploy workflow runs via `aws ssm send-command` on EC2
3. Push to `docs/main` → GitHub Actions builds Nextra docs and publishes to GitHub Pages

---

## Default Credentials (Local Dev)

| Service | Detail |
|---------|--------|
| MySQL database | `gotokart` |
| MySQL user | `root` |
| MySQL password | `Root@1234` |
| Admin email | `admin@gotokart.com` |
| Admin password | `admin123` |

> The admin user is auto-created by `DataInitializer` on backend startup.
