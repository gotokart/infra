#!/usr/bin/env bash
# Manual rollback helper for the EC2 + Docker Compose stack.
# Run on the server over SSH after identifying a good commit in each repo.
set -euo pipefail

ROOT="${HOME}/gotokart"

cat <<'EOF'
GoToKart — rollback on EC2 (manual)

1. Inspect recent commits:
     cd ~/gotokart/backend  && git log --oneline -5
     cd ~/gotokart/frontend && git log --oneline -5
     cd ~/gotokart/infra    && git log --oneline -5

2. Checkout a known-good commit in each repo (example):
     git checkout <commit-sha>

3. Rebuild the stack (same as a normal redeploy):
     cd ~/gotokart && \
       cp backend/pom.xml infra/ && \
       cp -r backend/src infra/src && \
       cp -r frontend/. infra/frontend/ && \
       cd infra && docker compose up -d --build

EOF
