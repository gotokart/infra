# TLS Certs (git-ignored)

Nginx in `docker-compose.yaml` mounts this directory at `/etc/nginx/certs:ro`
to serve HTTPS on port 443 for **gotokart.xyz** / **www.gotokart.xyz**.
The actual key/cert files are not committed (see `infra/.gitignore`); they
must be generated on the host before the first `docker compose up`.

## Production — Let's Encrypt with webroot

We renew via webroot, **not** standalone. Standalone needs port 80 free, but
nginx is already bound there. Webroot lets certbot drop the HTTP-01 challenge
file into a directory nginx serves at `/.well-known/acme-challenge/`, so
nginx never has to stop.

### First-time issuance

DNS for `gotokart.xyz` and `www.gotokart.xyz` must already point at this
EC2 instance.

```bash
sudo dnf install -y certbot                        # Amazon Linux 2023

cd ~/gotokart/infra
mkdir -p certbot-webroot                           # mounted into nginx

# nginx must be running so it can serve the challenge file
docker compose up -d nginx

sudo certbot certonly --webroot \
  --webroot-path /home/ec2-user/gotokart/infra/certbot-webroot \
  -d gotokart.xyz \
  -d www.gotokart.xyz \
  --email admin@gotokart.xyz \
  --agree-tos \
  --non-interactive

# Copy into the directory nginx mounts as cert material. Filenames stay
# `selfsigned.{crt,key}` so nginx.conf doesn't branch between dev and prod.
sudo cp /etc/letsencrypt/live/gotokart.xyz/fullchain.pem ./certs/selfsigned.crt
sudo cp /etc/letsencrypt/live/gotokart.xyz/privkey.pem   ./certs/selfsigned.key
sudo chown ec2-user:ec2-user ./certs/selfsigned.*
chmod 600 ./certs/selfsigned.key

docker compose restart nginx
```

### Migrating an existing standalone cert to webroot

If the cert was first issued with `--standalone`, the renewal config still
says so. Patch it once:

```bash
sudo sed -i \
  -e 's|^authenticator = standalone$|authenticator = webroot|' \
  -e '/^\[renewalparams\]/a webroot_path = /home/ec2-user/gotokart/infra/certbot-webroot,\nwebroot_map = {"gotokart.xyz": "/home/ec2-user/gotokart/infra/certbot-webroot", "www.gotokart.xyz": "/home/ec2-user/gotokart/infra/certbot-webroot"}' \
  /etc/letsencrypt/renewal/gotokart.xyz.conf

# Verify with a dry-run — must say "Congratulations, all simulated renewals…"
sudo certbot renew --dry-run
```

### Auto-renewal (systemd timer)

Renewals happen via `gotokart-cert-renew.service`, fired by
`gotokart-cert-renew.timer` (twice daily, randomized). Both unit files live
under `/etc/systemd/system/` on the EC2 host. The renewal script:

```bash
#!/usr/bin/env bash
set -euo pipefail

LIVE=/etc/letsencrypt/live/gotokart.xyz
DEST=/home/ec2-user/gotokart/infra/certs

certbot renew --quiet                              # uses webroot per renewal conf

if find "$LIVE/fullchain.pem" -mmin -60 | grep -q .; then
  cp "$LIVE/fullchain.pem" "$DEST/selfsigned.crt"
  cp "$LIVE/privkey.pem"   "$DEST/selfsigned.key"
  chown ec2-user:ec2-user "$DEST"/selfsigned.{crt,key}
  chmod 600 "$DEST/selfsigned.key"
  /usr/bin/docker compose \
    -f /home/ec2-user/gotokart/infra/docker-compose.yaml restart nginx
fi
```

`certbot renew` is a no-op until the cert is within 30 days of expiry; the
script then copies the new files into `infra/certs/` and reloads nginx.

## Local dev — self-signed

For developer laptops or staging boxes without a public domain:

```bash
cd infra
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/selfsigned.key \
  -out certs/selfsigned.crt \
  -subj "/CN=localhost"
chmod 600 certs/selfsigned.key
```

Browsers will warn about an untrusted issuer; accept once per machine.

## Sanity check

```bash
openssl x509 -in certs/selfsigned.crt -noout -subject -enddate
docker compose exec nginx nginx -t
curl -I https://gotokart.xyz
sudo certbot renew --dry-run
```
