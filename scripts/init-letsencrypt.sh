#!/usr/bin/env sh
set -eu

DOMAIN="${MONITORING_DOMAIN:-}"
EMAIL="${CERTBOT_EMAIL:-}"
CERT_NAME="${CERTBOT_CERT_NAME:-monitoring}"
STAGING="${CERTBOT_STAGING:-0}"

if [ -z "$DOMAIN" ]; then
  echo "ERROR: MONITORING_DOMAIN is not set in .env"
  exit 1
fi

if [ -z "$EMAIL" ]; then
  echo "ERROR: CERTBOT_EMAIL is not set in .env"
  exit 1
fi

mkdir -p ./certbot/conf ./certbot/www

if [ ! -f "./certbot/conf/live/$CERT_NAME/fullchain.pem" ]; then
  echo "Creating temporary self-signed certificate for initial Nginx startup..."
  docker compose run --rm --entrypoint "sh -c 'mkdir -p /etc/letsencrypt/live/$CERT_NAME && openssl req -x509 -nodes -newkey rsa:2048 -days 1 -keyout /etc/letsencrypt/live/$CERT_NAME/privkey.pem -out /etc/letsencrypt/live/$CERT_NAME/fullchain.pem -subj \"/CN=localhost\"'" certbot
fi

echo "Starting Nginx to serve ACME challenge endpoint..."
docker compose up -d nginx

STAGING_ARG=""
if [ "$STAGING" = "1" ]; then
  STAGING_ARG="--staging"
fi

echo "Requesting Let's Encrypt certificate for domain: $DOMAIN"
# shellcheck disable=SC2086
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  --email "$EMAIL" \
  -d "$DOMAIN" \
  --rsa-key-size 4096 \
  --agree-tos \
  --no-eff-email \
  --cert-name "$CERT_NAME" \
  --force-renewal \
  $STAGING_ARG

echo "Reloading Nginx with the newly issued certificate..."
docker compose exec nginx nginx -s reload

echo "Done. HTTPS is now configured for $DOMAIN"
