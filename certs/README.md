# TLS Certs (git-ignored)

Nginx in `docker-compose.yaml` mounts this directory at `/etc/nginx/certs:ro`
to serve HTTPS on port 443. The actual key/cert files are **not** committed
(see `infra/.gitignore`). Generate them on the host before the first
`docker compose up`.

## Self-signed cert (dev / staging)

Browsers will show an untrusted-cert warning that you have to accept once.
This is acceptable while the site runs on a bare EC2 IP. Required because
S3 presigned PUTs are HTTPS — a plain HTTP page triggers mixed-content /
CORS failures in modern browsers.

```bash
cd ~/gotokart/infra
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/selfsigned.key \
  -out certs/selfsigned.crt \
  -subj "/CN=52.90.87.237"
chmod 600 certs/selfsigned.key
docker compose restart nginx
```

Replace the `CN` value when you bind a real domain.

## Production (Let's Encrypt)

When you have a domain pointed at this EC2 instance:

```bash
sudo dnf install -y certbot
sudo certbot certonly --standalone -d gotokart.example.com
# certs land in /etc/letsencrypt/live/<domain>/{fullchain.pem,privkey.pem}
```

Either:
1. Symlink them into `infra/certs/` and rename to `selfsigned.{crt,key}`, or
2. Update `nginx.conf` and the volume mount to point directly at
   `/etc/letsencrypt/live/<domain>/`.

Set up `certbot renew` via a systemd timer or cron (Let's Encrypt certs
expire every 90 days).

## Sanity check

```bash
openssl x509 -in certs/selfsigned.crt -noout -subject -enddate
docker compose exec nginx nginx -t
curl -kI https://52.90.87.237
```
