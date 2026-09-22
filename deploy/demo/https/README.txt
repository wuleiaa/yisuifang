HTTPS package for yisuifang.work
================================

Files in this package (all of them go to /opt/followup/):

    docker-compose.override.yml     adds port 443 + cert/acme mounts to nginx
    nginx/followup.conf             the config that is live right now
    nginx/followup-https.conf       final https config (what install copies in)
    nginx/followup-http-only.conf   bootstrap: plain http + acme challenge
    https/install-https.sh          one-shot installer (idempotent)
    https/renew-cert.sh             weekly renewal (installed into cron)

How to install (on the server, as root):

    cd /opt/followup
    unzip -o /home/ubuntu/followup-https1.zip
    bash https/install-https.sh

The installer never leaves the site broken: it keeps nginx on plain http while
the certificate is being issued, and only switches to https after the
certificate really exists.

Full explanation, verification steps and rollback: docs/HTTPS-配置与续期.md
