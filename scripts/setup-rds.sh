#!/usr/bin/env bash
# ── infra/scripts/setup-rds.sh ───────────────────────────────────────────────
# Bootstraps the GoToKart MySQL database on AWS RDS and brings the new stack up.
#
# Run this ON THE EC2 HOST (not on your laptop) the first time you switch from
# the in-container MariaDB to RDS. Idempotent — safe to re-run.
#
# Usage:
#   chmod +x infra/scripts/setup-rds.sh
#   ./infra/scripts/setup-rds.sh
#
# What it does:
#   1. Installs the mysql client (mariadb105 on AL2023) if missing.
#   2. Downloads the AWS RDS CA bundle for verified-TLS connections.
#   3. Prompts for the RDS master password and a new app-user password.
#   4. Creates the `gotokart` database and `gotokart_app` user on RDS.
#   5. Writes infra/.env with the connection details (asks before overwriting).
#   6. Stops the old MariaDB container (if any) and brings up the new stack.
#   7. Tails the backend logs until it sees "Started GotokartApplication".
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Defaults — override via environment if needed ────────────────────────────
RDS_HOST="${RDS_HOST:-gotokart-db.ccjocguqok5t.us-east-1.rds.amazonaws.com}"
RDS_PORT="${RDS_PORT:-3306}"
RDS_DB_NAME="${RDS_DB_NAME:-gotokart}"
RDS_USERNAME="${RDS_USERNAME:-gotokart_app}"
RDS_MASTER_USER="${RDS_MASTER_USER:-admin}"
JWT_SECRET="${JWT_SECRET:-GoToKartSuperSecretJwtKey2026!!VeryLongAndSecure@#\$%}"
JWT_EXPIRY_MS="${JWT_EXPIRY_MS:-86400000}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_S3_BUCKET="${AWS_S3_BUCKET:-gotokart-product-images-035379289330-us-east-1-an}"
AWS_S3_PRESIGN_TTL_SECONDS="${AWS_S3_PRESIGN_TTL_SECONDS:-300}"

INFRA_DIR="${INFRA_DIR:-$HOME/gotokart/infra}"
CA_BUNDLE="${CA_BUNDLE:-$HOME/global-bundle.pem}"

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { printf '\033[1;32m[setup-rds]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup-rds]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[setup-rds]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

# ── 0. Sanity checks ─────────────────────────────────────────────────────────
require_cmd curl
require_cmd docker
[ -d "$INFRA_DIR" ] || fail "INFRA_DIR not found: $INFRA_DIR (clone the infra repo first)"
[ -f "$INFRA_DIR/docker-compose.yaml" ] || fail "docker-compose.yaml not found in $INFRA_DIR"

# ── 1. Install mysql client ──────────────────────────────────────────────────
if ! command -v mysql >/dev/null 2>&1; then
  log "Installing mariadb105 (provides the mysql CLI on Amazon Linux 2023)…"
  sudo yum install -y mariadb105
else
  log "mysql client already installed: $(mysql --version)"
fi

# ── 2. Fetch the AWS RDS CA bundle (for VERIFY_IDENTITY connections) ─────────
if [ ! -s "$CA_BUNDLE" ]; then
  log "Downloading AWS RDS global CA bundle to $CA_BUNDLE…"
  curl -fsSL -o "$CA_BUNDLE" https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
else
  log "AWS RDS CA bundle already present at $CA_BUNDLE"
fi

# ── 3. Prompt for credentials ────────────────────────────────────────────────
echo
log "RDS host: $RDS_HOST"
log "RDS master user: $RDS_MASTER_USER"
log "App user to create: $RDS_USERNAME on database '$RDS_DB_NAME'"
echo

read -r -s -p "Enter RDS master password (for user $RDS_MASTER_USER): " RDS_MASTER_PASSWORD
echo
[ -n "$RDS_MASTER_PASSWORD" ] || fail "Master password cannot be empty"

read -r -s -p "Pick a strong password for the new app user $RDS_USERNAME: " RDS_PASSWORD
echo
read -r -s -p "Confirm app user password: " RDS_PASSWORD_CONFIRM
echo
[ "$RDS_PASSWORD" = "$RDS_PASSWORD_CONFIRM" ] || fail "App user passwords do not match"
[ ${#RDS_PASSWORD} -ge 8 ] || fail "App user password must be at least 8 characters"

# ── 4. Verify reachability + create DB and app user ──────────────────────────
log "Verifying connectivity to RDS over TLS…"
if ! MYSQL_PWD="$RDS_MASTER_PASSWORD" mysql \
      -h "$RDS_HOST" -P "$RDS_PORT" -u "$RDS_MASTER_USER" \
      --ssl-mode=VERIFY_IDENTITY --ssl-ca="$CA_BUNDLE" \
      -e "SELECT 1;" >/dev/null; then
  fail "Could not connect to RDS as $RDS_MASTER_USER. Check the password, the SG (rds-ec2-1), and the endpoint."
fi
log "Connection successful."

log "Creating database '$RDS_DB_NAME' and app user '$RDS_USERNAME' (idempotent)…"
MYSQL_PWD="$RDS_MASTER_PASSWORD" mysql \
  -h "$RDS_HOST" -P "$RDS_PORT" -u "$RDS_MASTER_USER" \
  --ssl-mode=VERIFY_IDENTITY --ssl-ca="$CA_BUNDLE" <<SQL
CREATE DATABASE IF NOT EXISTS \`$RDS_DB_NAME\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '$RDS_USERNAME'@'%' IDENTIFIED BY '$RDS_PASSWORD';
ALTER USER '$RDS_USERNAME'@'%' IDENTIFIED BY '$RDS_PASSWORD';
GRANT ALL PRIVILEGES ON \`$RDS_DB_NAME\`.* TO '$RDS_USERNAME'@'%';
FLUSH PRIVILEGES;
SQL
log "Database and app user are ready."

log "Verifying the new app user can log in…"
if ! MYSQL_PWD="$RDS_PASSWORD" mysql \
      -h "$RDS_HOST" -P "$RDS_PORT" -u "$RDS_USERNAME" \
      --ssl-mode=VERIFY_IDENTITY --ssl-ca="$CA_BUNDLE" \
      -D "$RDS_DB_NAME" -e "SELECT CURRENT_USER();" >/dev/null; then
  fail "App user $RDS_USERNAME failed to log in — credentials or grants are off."
fi
log "App user can connect. ✔"

# ── 5. Write infra/.env (asks before overwriting) ────────────────────────────
ENV_FILE="$INFRA_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  read -r -p ".env already exists at $ENV_FILE — overwrite? [y/N] " ANSWER
  case "$ANSWER" in [yY]|[yY][eE][sS]) ;; *) log "Keeping existing .env." ; SKIP_ENV=1 ;; esac
fi

if [ "${SKIP_ENV:-0}" != "1" ]; then
  log "Writing $ENV_FILE…"
  umask 077
  cat > "$ENV_FILE" <<ENV
# Auto-generated by infra/scripts/setup-rds.sh on $(date -u +'%Y-%m-%dT%H:%M:%SZ')
RDS_HOST=$RDS_HOST
RDS_PORT=$RDS_PORT
RDS_DB_NAME=$RDS_DB_NAME
RDS_USERNAME=$RDS_USERNAME
RDS_PASSWORD=$RDS_PASSWORD

JWT_SECRET=$JWT_SECRET
JWT_EXPIRY_MS=$JWT_EXPIRY_MS

AWS_REGION=$AWS_REGION
AWS_S3_BUCKET=$AWS_S3_BUCKET
AWS_S3_PUBLIC_BASE_URL=
AWS_S3_PRESIGN_TTL_SECONDS=$AWS_S3_PRESIGN_TTL_SECONDS
ENV
  chmod 600 "$ENV_FILE"
  log ".env written with mode 0600 (only your user can read it)."
fi

# ── 6. Bring the new stack up ────────────────────────────────────────────────
log "Stopping the old stack (this also tears down the obsolete MariaDB container)…"
( cd "$INFRA_DIR" && docker compose down ) || warn "compose down had non-fatal output; continuing."

log "Building and starting the new stack (backend + nginx, no DB container)…"
( cd "$INFRA_DIR" && docker compose up -d --build )

# ── 7. Wait for the backend to be ready ──────────────────────────────────────
log "Waiting for the backend to finish startup (looking for 'Started GotokartApplication')…"
DEADLINE=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if docker logs gotokart-backend 2>&1 | grep -q "Started GotokartApplication"; then
    log "Backend is up. ✔"
    break
  fi
  if docker logs gotokart-backend 2>&1 | grep -Eqi "Access denied|Communications link failure|Public Key Retrieval"; then
    docker logs gotokart-backend 2>&1 | tail -50
    fail "Backend hit a database error during startup. See the log lines above."
  fi
  sleep 3
done

if ! docker logs gotokart-backend 2>&1 | grep -q "Started GotokartApplication"; then
  warn "Backend did not report ready within 3 minutes. Last 50 log lines:"
  docker logs gotokart-backend 2>&1 | tail -50
  fail "Bring-up did not finish cleanly. Investigate before declaring done."
fi

# ── 8. Smoke tests ───────────────────────────────────────────────────────────
log "Smoke testing the public endpoints…"
docker compose -f "$INFRA_DIR/docker-compose.yaml" ps
echo
log "GET https://gotokart.xyz (HEAD):"
curl -sSI https://gotokart.xyz | head -1 || warn "Public HEAD failed — check nginx + DNS."
echo
log "GET https://gotokart.xyz/api/products (first 200 chars):"
curl -sS https://gotokart.xyz/api/products | head -c 200
echo

cat <<DONE

──────────────────────────────────────────────────────────────────────────────
 GoToKart is now running against AWS RDS.

 Host:       $RDS_HOST
 Database:   $RDS_DB_NAME
 App user:   $RDS_USERNAME
 .env file:  $ENV_FILE  (mode 0600)

 Useful follow-ups:
   docker compose -f $INFRA_DIR/docker-compose.yaml ps
   docker logs -f gotokart-backend
   mysql -h $RDS_HOST -u $RDS_USERNAME -p $RDS_DB_NAME \\
         --ssl-mode=VERIFY_IDENTITY --ssl-ca=$CA_BUNDLE

 Once you have confirmed everything works, reclaim the old MariaDB volume:
   docker volume ls | grep mysql
   docker volume rm infra_mysql-data
──────────────────────────────────────────────────────────────────────────────
DONE
