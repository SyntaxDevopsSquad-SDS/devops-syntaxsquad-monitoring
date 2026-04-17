# WhoKnows Monitoring (Prometheus + Grafana)

Production-minded monitoring repository for a separate monitoring VM.

This stack scrapes the WhoKnows backend metrics endpoint at:
- `http://syntax-reborndev.com:8080/metrics`

## Stack

- Prometheus (metrics collection and storage)
- Grafana (visualization and dashboards)
- Optional: Node Exporter (VM host metrics)

## Repository Structure

- `docker-compose.yml`: Runs Prometheus, Grafana and optional Node Exporter with named volumes and healthchecks.
- `prometheus/prometheus.yml`: Scrape jobs and intervals (includes `whoknows-go-backend` every `15s`).
- `grafana/provisioning/datasources/datasource.yml`: Auto-provisions Prometheus datasource.
- `grafana/provisioning/dashboards/dashboards.yml`: Auto-imports dashboards at startup.
- `grafana/dashboards/whoknows-overview.json`: Main WhoKnows overview dashboard.
- `.env.example`: Example environment variables for Grafana admin credentials.
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
```

3. Start services:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f
```

4. Access:

- Grafana: `http://<MONITORING_VM_IP>:3000`
- Prometheus: `http://<MONITORING_VM_IP>:9090`

5. Optional VM host metrics via Node Exporter:

```bash
docker compose --profile vm-metrics up -d
```

## Prometheus Details

- Scrape target: `syntax-reborndev.com:8080`
- Job name: `whoknows-go-backend`
- `scrape_interval: 15s`
- Retention: `7d` via `--storage.tsdb.retention.time=7d`

## Grafana Provisioning Details

- Datasource is auto-created from `grafana/provisioning/datasources/datasource.yml`.
- Dashboard is auto-imported from `grafana/dashboards/whoknows-overview.json` through `dashboards.yml`.
- Admin credentials come from `.env` (`GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`), not hardcoded in files.

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
	- `3000/tcp` (Grafana)
	- `9090/tcp` (Prometheus)
- Outbound from monitoring VM:
	- `8080/tcp` to `syntax-reborndev.com` (backend metrics endpoint)

Recommended:
- Restrict source IPs for ports `3000` and `9090` to trusted admin/network ranges.
- Keep `.env` out of Git (already covered by `.gitignore`).

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
