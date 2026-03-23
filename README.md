# GoToKart Infrastructure

## Architecture
```
Frontend  ? GitHub Pages  ? gotokart.in
Backend   ? Railway       ? api.gotokart.in
Database  ? Railway MySQL
Pipelines ? .github repo
```

## Repositories
| Repo | Purpose |
|------|---------|
| frontend | HTML/CSS/JS source code |
| backend | Spring Boot source code |
| .github | CI/CD pipelines |
| infra | Infrastructure docs & config |

## Domain Setup
- Frontend: gotokart.in (GitHub Pages)
- Backend API: api.gotokart.in (Railway custom domain)

## CI/CD Flow
1. Push to frontend/main ? .github pipeline ? GitHub Pages
2. Push to backend/main ? Railway auto-deploy
