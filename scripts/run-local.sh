#!/usr/bin/env bash
# Run GoToKart locally (MySQL 8 + Spring Boot + static frontend).
# Expects backend/ and frontend/ as siblings of this infra/ folder.
# Usage: ./scripts/run-local.sh

set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$INFRA/.." && pwd)"
MYSQL_DIR="$INFRA/.local/mysql-data"
MYSQL_PID="$INFRA/.local/mysql.pid"
MYSQL_SOCKET="/tmp/mysql-gotokart.sock"
MYSQL_PORT=3307

# macOS: use system Keychain for HTTPS (fixes Unsplash SSL on local Java)
if [[ "$(uname -s)" == "Darwin" ]]; then
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djavax.net.ssl.trustStoreType=KeychainStore -Djavax.net.ssl.trustStore=NONE"
fi

export SPRING_DATASOURCE_URL="jdbc:mysql://127.0.0.1:${MYSQL_PORT}/gotokart?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&authenticationPlugin=caching_sha2_password"
export SPRING_DATASOURCE_USERNAME=root
export SPRING_DATASOURCE_PASSWORD='Root@1234'

# Optional AWS S3 vars from infra/.env (for product image uploads)
if [[ -f "$INFRA/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$INFRA/.env"
  set +a
fi

start_mysql() {
  mkdir -p "$INFRA/.local"
  if [[ ! -f "$MYSQL_DIR/ibdata1" ]]; then
    echo "→ Initializing MySQL data directory..."
    /opt/homebrew/opt/mysql@8.0/bin/mysqld --initialize-insecure \
      --datadir="$MYSQL_DIR" --user="$(whoami)"
  fi

  if [[ -f "$MYSQL_PID" ]] && kill -0 "$(cat "$MYSQL_PID")" 2>/dev/null; then
    echo "→ MySQL already running on port $MYSQL_PORT"
    return
  fi

  echo "→ Starting MySQL on port $MYSQL_PORT..."
  /opt/homebrew/opt/mysql@8.0/bin/mysqld \
    --datadir="$MYSQL_DIR" \
    --port="$MYSQL_PORT" \
    --socket="$MYSQL_SOCKET" \
    --pid-file="$MYSQL_PID" \
    --bind-address=127.0.0.1 \
    --user="$(whoami)" &

  for _ in $(seq 1 30); do
    if mysql -S "$MYSQL_SOCKET" -u root -e "SELECT 1" &>/dev/null; then
      break
    fi
    sleep 1
  done

  mysql -S "$MYSQL_SOCKET" -u root <<'SQL'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'Root@1234';
CREATE DATABASE IF NOT EXISTS gotokart;
FLUSH PRIVILEGES;
SQL
  echo "→ MySQL ready (database: gotokart)"
}

start_mysql

echo "→ Starting backend on http://localhost:8080 ..."
cd "$ROOT/backend"
bash mvnw spring-boot:run &
BACKEND_PID=$!

echo "→ Serving frontend on http://localhost:5500 ..."
cd "$ROOT/frontend"
python3 -m http.server 5500 &
FRONTEND_PID=$!

cleanup() {
  echo
  echo "→ Shutting down..."
  kill "$FRONTEND_PID" "$BACKEND_PID" 2>/dev/null || true
}
trap cleanup INT TERM

echo
echo "============================================"
echo "  GoToKart local dev is running"
echo "  Frontend:  http://localhost:5500"
echo "  Backend:   http://localhost:8080/api"
echo "  Admin:     admin@gotokart.com / admin123"
echo "============================================"
echo "Press Ctrl+C to stop backend and frontend."
echo "(MySQL on port $MYSQL_PORT keeps running in the background.)"
echo

wait "$BACKEND_PID"
