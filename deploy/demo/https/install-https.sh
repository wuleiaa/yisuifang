#!/usr/bin/env bash
# =============================================================================
#  Install HTTPS for the followup demo server (idempotent, safe to re-run).
#
#  Run it ON THE SERVER, as root:
#      cd /opt/followup && bash https/install-https.sh
#
#  Optional overrides:
#      DOMAIN=yisuifang.work EMAIL=you@example.com bash https/install-https.sh
#      SKIP_DRY_RUN=1 bash https/install-https.sh     # skip the staging dry-run
#
#  What it does:
#      1. checks that docker-compose.override.yml is being picked up (443 + mounts)
#      2. backs up nginx/followup.conf and the compose files
#      3. starts nginx with the http-only bootstrap, so the site keeps working
#      4. asks Let's Encrypt for a certificate (webroot challenge on port 80)
#      5. switches nginx/followup.conf back to the https version, tests and reloads
#      6. installs a weekly cron job that renews the certificate
#
#  If step 4 fails the site stays fully usable on plain http - nothing breaks.
# =============================================================================

set -eu

DOMAIN="${DOMAIN:-yisuifang.work}"
EMAIL="${EMAIL:-16673953299@163.com}"
SKIP_DRY_RUN="${SKIP_DRY_RUN:-0}"
CERTBOT_IMAGE="certbot/certbot:latest"

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NGINX_DIR="$APP_DIR/nginx"
CONF="$NGINX_DIR/followup.conf"
CONF_HTTPS="$NGINX_DIR/followup-https.conf"
CONF_HTTP="$NGINX_DIR/followup-http-only.conf"
LETSENCRYPT="$NGINX_DIR/letsencrypt"
WEBROOT="$NGINX_DIR/www"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$APP_DIR/backup/https-$STAMP"
CERT_FILE="$LETSENCRYPT/live/$DOMAIN/fullchain.pem"

log() { printf '\n=== %s\n' "$*"; }
die() { printf '\n!! ERROR: %s\n' "$*" >&2; exit 1; }
http_code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: $DOMAIN" "http://127.0.0.1$1" || echo "000"; }
https_code() { curl -s -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN$1" || echo "000"; }

# ---------------------------------------------------------------- safety first
# (root is required for the fallback copy below and for everything after it)
[ "$(id -u)" = "0" ] || die "please run as root (run 'sudo -i' first, then re-run)"

# nginx refuses to start when ssl_certificate points at a file that is not there
# yet (the whole server, not just that vhost). If the config on disk is already
# the https one but the certificate is missing, fall back to the http bootstrap
# BEFORE anything else - so a reboot or a container restart cannot take the site
# down while we are still in the middle of installing.
if [ -f "$CONF" ] && [ -f "$CONF_HTTP" ] && [ ! -f "$CERT_FILE" ] \
   && grep -q 'ssl_certificate' "$CONF"; then
    echo "!! https config found but no certificate yet - falling back to the http bootstrap"
    cp -f "$CONF_HTTP" "$CONF"
fi

# ---------------------------------------------------------------- preflight
[ -f "$APP_DIR/docker-compose.yml" ] || die "docker-compose.yml not found in $APP_DIR"
[ -f "$APP_DIR/docker-compose.override.yml" ] || die "docker-compose.override.yml not found - unzip the package into $APP_DIR first"
[ -f "$CONF_HTTPS" ] || die "$CONF_HTTPS not found - unzip the package into $APP_DIR first"
[ -f "$CONF_HTTP" ] || die "$CONF_HTTP not found - unzip the package into $APP_DIR first"
command -v docker >/dev/null 2>&1 || die "docker not found"
command -v curl >/dev/null 2>&1 || die "curl not found (try: apt-get install -y curl)"

cd "$APP_DIR"

log "0/6 preflight"
echo "app dir    : $APP_DIR"
echo "domain     : $DOMAIN, www.$DOMAIN"
echo "letsencrypt: $EMAIL"
echo "backup     : $BACKUP_DIR"

COMPOSE_CFG="$(docker compose config 2>&1)" || die "docker compose config failed:
$COMPOSE_CFG"
printf '%s\n' "$COMPOSE_CFG" | grep -Eq '(published: +"?443|443:443)' \
    || die "port 443 is not published - is docker-compose.override.yml in $APP_DIR ?"
printf '%s\n' "$COMPOSE_CFG" | grep -q '/etc/letsencrypt' \
    || die "the certificate folder is not mounted - is docker-compose.override.yml in $APP_DIR ?"
printf '%s\n' "$COMPOSE_CFG" | grep -q '/var/www/certbot' \
    || die "the acme webroot is not mounted - is docker-compose.override.yml in $APP_DIR ?"
printf '%s\n' "$COMPOSE_CFG" | grep -q 'nginx/followup.conf' \
    || die "this server mounts a different nginx config file - stop here and check docker-compose.yml before continuing"
echo "compose check: 443 + certificate mounts are in place"

# ---------------------------------------------------------------- 1. backup
log "1/6 backup current config"
mkdir -p "$BACKUP_DIR"
[ -f "$CONF" ] && cp -a "$CONF" "$BACKUP_DIR/followup.conf.before" || true
cp -a docker-compose.yml "$BACKUP_DIR/docker-compose.yml.before"
cp -a docker-compose.override.yml "$BACKUP_DIR/docker-compose.override.yml.before"
echo "saved to $BACKUP_DIR"

# ---------------------------------------------------------------- 2. dirs
log "2/6 prepare certificate folders"
mkdir -p "$LETSENCRYPT" "$WEBROOT"
chmod 755 "$WEBROOT"

# ---------------------------------------------------------------- 3. bootstrap
log "3/6 start nginx with the http-only bootstrap (site stays online)"
# NOTE: always copy into place, never 'mv' - a single-file compose mount follows
# the original inode, and replacing the file would leave nginx reading stale content.
cp -f "$CONF_HTTP" "$CONF"
docker compose up -d nginx || die "could not start nginx"
sleep 3
docker compose exec -T nginx nginx -t || die "nginx config test failed (bootstrap)"
echo "  http  /         -> $(http_code /)"
echo "  http  /patient/ -> $(http_code /patient/)"
echo "  http  /admin/   -> $(http_code /admin/)"

# ---------------------------------------------------------------- 4. certbot
log "4/6 request the certificate from Let's Encrypt"

run_certbot() {
    docker run --rm \
        -v "$LETSENCRYPT:/etc/letsencrypt" \
        -v "$WEBROOT:/var/www/certbot" \
        "$CERTBOT_IMAGE" certonly \
        --webroot --webroot-path /var/www/certbot \
        --domains "$DOMAIN,www.$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos --no-eff-email --non-interactive "$@"
}

if [ -f "$CERT_FILE" ]; then
    echo "certificate already exists - skipping issuance"
else
    if [ "$SKIP_DRY_RUN" != "1" ]; then
        echo "-- dry run first (checks DNS + port 80, costs no rate limit)"
        run_certbot --dry-run || die "dry run failed - fix the error above, then re-run this script"
    fi
    run_certbot --keep-until-expiring \
        || die "issuance failed - the site is still fine on http, fix the error and re-run"
fi

[ -f "$CERT_FILE" ] || die "certificate file not found: $CERT_FILE"

# ---------------------------------------------------------------- 5. enable 443
log "5/6 switch nginx to https"
cp -f "$CONF_HTTPS" "$CONF"
docker compose exec -T nginx nginx -t || die "nginx config test failed (https)"
docker compose exec -T nginx nginx -s reload

echo "  https /         -> $(https_code /)"
echo "  https /patient/ -> $(https_code /patient/)"
echo "  https /admin/   -> $(https_code /admin/)"
echo "  https /health   -> $(https_code /health)"
echo "  http  /         -> $(http_code /)   (expect 301)"

# ---------------------------------------------------------------- 6. renewal
log "6/6 install the weekly renewal cron job"
systemctl enable --now cron >/dev/null 2>&1 || true
chmod +x "$APP_DIR/https/renew-cert.sh"
cat > /etc/cron.d/followup-cert-renew <<CRON
# Let's Encrypt renewal for $DOMAIN (installed by install-https.sh)
17 3 * * 1 root $APP_DIR/https/renew-cert.sh >> /var/log/followup-cert-renew.log 2>&1
CRON
chmod 644 /etc/cron.d/followup-cert-renew
echo "cron file: /etc/cron.d/followup-cert-renew"

log "done"
cat <<EOF
Certificate : $LETSENCRYPT/live/$DOMAIN/
Config      : $CONF  (now a copy of $CONF_HTTPS)
Backup      : $BACKUP_DIR
Renewal     : every Monday 03:17, log at /var/log/followup-cert-renew.log

Next: open https://$DOMAIN/ in a browser and check the padlock.

Rollback to plain http:
    cd $APP_DIR
    rm -f docker-compose.override.yml
    cp -f $BACKUP_DIR/followup.conf.before $CONF
    docker compose up -d nginx
EOF
