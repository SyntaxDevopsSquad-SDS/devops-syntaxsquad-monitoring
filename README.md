# WhoKnows Monitoring (Prometheus + Grafana)

Production-minded monitoring repository for a separate monitoring VM.

This stack scrapes the WhoKnows backend metrics endpoint at:
- `http://syntax-reborndev.com:8080/metrics`

## Stack

- Nginx (single entrypoint/reverse proxy)
- Certbot + Let's Encrypt (TLS certificates and automatic renewal)
- Prometheus (metrics collection and storage)
- Grafana (visualization and dashboards)
- Optional: Node Exporter (VM host metrics)

## Repository Structure

- `docker-compose.yml`: Runs Nginx, Prometheus, Grafana and optional Node Exporter with named volumes and healthchecks.
- `docker-compose.dev.yml`: Local dev stack with direct Grafana/Prometheus ports and no TLS reverse proxy.
- `nginx/nginx.conf`: Reverse proxy config that redirects `80` to `443`, serves ACME challenge, and exposes `/grafana/` + `/prometheus/` over HTTPS.
- `scripts/init-letsencrypt.sh`: One-time bootstrap script that requests the first Let's Encrypt certificate.
- `prometheus/prometheus.yml`: Scrape jobs and intervals (includes `whoknows-go-backend` every `15s`).
- `grafana/provisioning/datasources/datasource.yml`: Auto-provisions Prometheus datasource.
- `grafana/provisioning/dashboards/dashboards.yml`: Auto-imports dashboards at startup.
- `grafana/dashboards/whoknows-overview.json`: Main WhoKnows overview dashboard.
- `.env.example`: Example environment variables for Grafana admin credentials and Certbot settings.
- `.github/workflows/validate-monitoring.yml`: PR-only validation of Compose and Prometheus config.
- `.gitignore`: Prevents committing secrets and local artifacts.

## Prerequisites

- Docker Engine + Docker Compose plugin on the monitoring VM.
- DNS/network access from monitoring VM to `syntax-reborndev.com:8080`.

## Setup

1. Create environment file:

```bash
cp .env.example .env
```

2. Edit `.env` with strong credentials.

Example `.env` values:

```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=ReplaceWithStrongPassword123!
MONITORING_DOMAIN=monitor.example.com
CERTBOT_EMAIL=ops@example.com
CERTBOT_CERT_NAME=monitoring
CERTBOT_STAGING=0
```

3. Bootstrap the first Let's Encrypt certificate:

```bash
chmod +x scripts/init-letsencrypt.sh
docker compose pull
docker compose --env-file .env run --rm certbot --version
set -a
. ./.env
set +a
./scripts/init-letsencrypt.sh
```

4. Start full stack:

```bash
docker compose up -d
docker compose ps
docker compose logs -f
```

5. Access:

- Grafana: `https://<MONITORING_DOMAIN>/`
- Prometheus: `https://<MONITORING_DOMAIN>/prometheus/`

6. Optional VM host metrics via Node Exporter:

```bash
docker compose --profile vm-metrics up -d
```

## Prometheus Details

- Scrape target: `syntax-reborndev.com:8080`
- Job name: `whoknows-go-backend`
- `scrape_interval: 15s`
- Retention: `30d` via `--storage.tsdb.retention.time=30d`

## Grafana Provisioning Details

- Datasource is auto-created from `grafana/provisioning/datasources/datasource.yml`.
- Datasource URL is environment-driven via `PROMETHEUS_URL`:
	- Dev (`docker-compose.dev.yml`): `http://prometheus:9090`
	- Prod (`docker-compose.yml`): `http://prometheus:9090/prometheus`
- Dashboard is auto-imported from `grafana/dashboards/whoknows-overview.json` through `dashboards.yml`.
- Admin credentials come from `.env` (`GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`), not hardcoded in files.

## Local Development

Start dev stack:

```bash
docker compose -f docker-compose.dev.yml up -d
```

Access locally:

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`

## Dashboard Coverage (`whoknows-overview`)

Includes panels for:
- HTTP requests total (rate + selected range total)
- HTTP requests by status code
- Request latency p95 from `whoknows_http_request_duration_seconds`
- Successful logins (`outcome="success"`)
- Failed logins (`outcome="failure"`)
- Successful registrations (`outcome="success"`)
- Registrations failing/validation outcomes
- Searches total
- Searches by query-term (TopK)
- Grafana variables for `query` and `language`

## Security and Network (Firewall/NSG)

Open only what is needed:

- Inbound to monitoring VM:
	- `80/tcp` (HTTP for ACME challenge + redirect)
	- `443/tcp` (HTTPS for Grafana and Prometheus)
- Outbound from monitoring VM:
	- `8080/tcp` to `syntax-reborndev.com` (backend metrics endpoint)

Recommended:
- Restrict source IPs for `443` to trusted admin/network ranges if possible.
- Keep `.env` out of Git (already covered by `.gitignore`).

## TLS / Certbot Notes

- Certificates are stored in `certbot/conf` (gitignored).
- ACME challenge files are served from `certbot/www`.
- Nginx uses certificate name `monitoring` by default (`CERTBOT_CERT_NAME`).
- Automatic renewals run in the `certbot` container every 12 hours.

Manual renewal test:

```bash
docker compose run --rm certbot renew --webroot -w /var/www/certbot --dry-run
```

## Healthchecks

Defined in `docker-compose.yml`:
- Prometheus: `http://localhost:9090/-/healthy`
- Grafana: `http://localhost:3000/api/health`

Verify status:

```bash
docker compose ps
```

## Backup and Restore

Named volumes used:
- `prometheus_data`
- `grafana_data`

Backup Prometheus data:

```bash
docker run --rm -v prometheus_data:/data -v "$PWD/backups:/backup" alpine \
	tar czf /backup/prometheus_data_$(date +%Y%m%d_%H%M%S).tgz -C /data .
```

Backup Grafana data (includes users, settings, dashboard state):

```bash
docker run --rm -v grafana_data:/data -v "$PWD/backups:/backup" alpine \
	tar czf /backup/grafana_data_$(date +%Y%m%d_%H%M%S).tgz -C /data .
```

Restore (example Prometheus):

```bash
docker compose down
docker run --rm -v prometheus_data:/data -v "$PWD/backups:/backup" alpine \
	sh -c "rm -rf /data/* && tar xzf /backup/<PROM_BACKUP_FILE>.tgz -C /data"
docker compose up -d
```

Dashboard JSON backup/restore:
- Source-controlled dashboard file: `grafana/dashboards/whoknows-overview.json`
- You can export/import dashboards in Grafana UI if needed for ad-hoc copies.

## CI Validation (GitHub Actions)

Workflow: `.github/workflows/validate-monitoring.yml`

On pull requests, it only validates:
- `docker compose config`
- `promtool check config prometheus/prometheus.yml`

No automatic deployment is performed.

## Troubleshooting

- `Target down` in Prometheus:
	- Check DNS from monitoring VM to `syntax-reborndev.com`.
	- Verify firewall/NSG allows egress `8080/tcp` from monitoring VM.
	- Confirm backend actually exposes `/metrics` on port `8080`.

- Grafana dashboard has no data:
	- Check Prometheus target status at `/targets`.
	- Verify metric names in backend match dashboard queries.
	- Validate selected time range and filters (`query`, `language`).

- Containers unhealthy:
	- `docker compose logs prometheus`
	- `docker compose logs grafana`
