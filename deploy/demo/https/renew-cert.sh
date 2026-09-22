#!/bin/sh
# =============================================================================
#  Renew the Let's Encrypt certificate and reload nginx.
#  Installed as a weekly cron job by install-https.sh; safe to run by hand.
# =============================================================================
set -eu

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

echo "[$(date '+%F %T')] certbot renew"
docker run --rm \
    -v "$APP_DIR/nginx/letsencrypt:/etc/letsencrypt" \
    -v "$APP_DIR/nginx/www:/var/www/certbot" \
    certbot/certbot:latest renew \
    --webroot --webroot-path /var/www/certbot --quiet

docker compose exec -T nginx nginx -s reload
echo "[$(date '+%F %T')] nginx reloaded"
