# TLS Certs (git-ignored)

Nginx in `docker-compose.yaml` mounts this directory at `/etc/nginx/certs:ro`
to serve HTTPS on port 443 for **gotokart.xyz** / **www.gotokart.xyz**.
The actual key/cert files are not committed (see `infra/.gitignore`); they
must be generated on the host before the first `docker compose up`.

## Production — Let's Encrypt (current setup)

DNS for `gotokart.xyz` and `www.gotokart.xyz` must already point at this
EC2 instance. Then on the host:

```bash
sudo dnf install -y certbot                        # Amazon Linux 2023
# (use `sudo yum install -y certbot` on AL2)

sudo certbot certonly --standalone \
  -d gotokart.xyz \
  -d www.gotokart.xyz \
  --email admin@gotokart.xyz \
  --agree-tos \
  --non-interactive

# Copy into the directory nginx mounts. Filenames stay `selfsigned.*` so
# nginx.conf doesn't need to change between dev and prod.
cd ~/gotokart/infra
sudo cp /etc/letsencrypt/live/gotokart.xyz/fullchain.pem ./certs/selfsigned.crt
sudo cp /etc/letsencrypt/live/gotokart.xyz/privkey.pem   ./certs/selfsigned.key
sudo chown ec2-user:ec2-user ./certs/selfsigned.*
chmod 600 ./certs/selfsigned.key

docker compose restart nginx
```

Certbot needs port 80 free for the HTTP-01 challenge, so stop nginx first
on renewals (or use the `--webroot` plugin instead of `--standalone`).

### Auto-renewal

Let's Encrypt certs expire every 90 days. Drop a script that re-copies
into `infra/certs/` and reloads nginx, then schedule it:

```bash
sudo systemctl enable --now certbot-renew.timer
```

…or a simple cron entry:

```cron
0 3 * * 0 certbot renew --quiet \
  --post-hook "cp /etc/letsencrypt/live/gotokart.xyz/fullchain.pem /home/ec2-user/gotokart/infra/certs/selfsigned.crt && cp /etc/letsencrypt/live/gotokart.xyz/privkey.pem /home/ec2-user/gotokart/infra/certs/selfsigned.key && docker compose -f /home/ec2-user/gotokart/infra/docker-compose.yaml restart nginx"
```

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
```
