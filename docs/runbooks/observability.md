# Runbook: Observability Stack

**Stack**: `compose/observability/`
**Services**: Prometheus · Loki · Grafana · Node Exporter · cAdvisor
**Related ADR**: [ADR-0007](../decisions/adr/ADR-0007-observability-prometheus-loki-grafana.md)

---

## Prerequisites

- Traefik core stack running: `docker compose -f compose/core/docker-compose.yml ps`
- `traefik` external Docker network exists
- Loki Docker log driver installed: `docker plugin ls | grep loki`
- SOPS age key available: `echo $SOPS_AGE_KEY_FILE`
- `/etc/hosts` contains `grafana.hal.local`:
  ```
  127.0.0.1  grafana.hal.local
  ```
  Add if missing: `echo "127.0.0.1  grafana.hal.local" | sudo tee -a /etc/hosts`

---

## 1. First-Time Setup

### 1.1 Install the Loki Docker log driver

```bash
docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
docker plugin ls | grep loki
# Expected: loki   grafana/loki-docker-driver:latest  true
```

### 1.2 Configure Docker daemon to use Loki as default log driver

Edit `/etc/docker/daemon.json` to add:

```json
{
  "data-root": "/srv/platform/docker",
  "log-driver": "loki",
  "log-opts": {
    "loki-url": "http://localhost:3100/loki/api/v1/push",
    "loki-batch-size": "400",
    "loki-retries": "3",
    "loki-timeout": "10s",
    "keep-file": "true",
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Restart Docker and verify stacks recover:

```bash
sudo systemctl restart docker
sleep 10
docker compose -f compose/core/docker-compose.yml ps
docker compose -f compose/ai/docker-compose.yml ps
```

### 1.3 Prepare secrets

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
./scripts/secrets-decrypt.sh observability
# Verify:
ls /srv/platform/secrets/observability.yaml
```

### 1.4 Copy and configure the environment file

```bash
cp compose/observability/.env.example compose/observability/.env
# No changes needed for defaults; image tags are pre-set
```

### 1.5 Bring up the stack

```bash
docker compose -f compose/observability/docker-compose.yml up -d
```

**Verify all containers healthy** (may take up to 60 s):

```bash
docker compose -f compose/observability/docker-compose.yml ps
# Expected: all 5 services status=healthy
```

### 1.6 Verify Prometheus targets

```bash
curl -sk http://prometheus:9090/api/v1/targets 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(t['labels']['job'], t['health'])
"
# Expected: prometheus up, node-exporter up, cadvisor up, traefik up
```

Or open Prometheus in the browser: `http://localhost:9090/targets` (direct, no TLS).

### 1.7 Open Grafana

Navigate to `https://grafana.hal.local` and log in with the admin credentials from `secrets/observability.yaml`.

---

## 2. Daily Operations

### Bring up

```bash
docker compose -f compose/observability/docker-compose.yml up -d
```

### Tear down (preserves data volumes)

```bash
docker compose -f compose/observability/docker-compose.yml down
```

### Tail all logs

```bash
docker compose -f compose/observability/docker-compose.yml logs -f
```

### Check health

```bash
docker compose -f compose/observability/docker-compose.yml ps
```

---

## 3. Adding a New Prometheus Scrape Target

Edit `compose/observability/prometheus.yml` and add a job under `scrape_configs`:

```yaml
- job_name: my-service
  static_configs:
    - targets: ["my-service:9090"]
```

Reload Prometheus without restart:

```bash
curl -X POST http://localhost:9090/-/reload
```

**Verify**:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json,sys; d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if t['labels']['job'] == 'my-service':
        print(t['health'])
"
# Expected: up
```

---

## 4. Loki Log Driver

### Reinstall after Docker upgrade

```bash
docker plugin disable loki --force
docker plugin rm loki
docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
```

### Verify logs reach Loki

```bash
# Query last 5 minutes of Loki for a container
curl -sG "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={container_name="traefik"}' \
  --data-urlencode "start=$(date -d '5 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['data']['result']), 'streams')"
# Expected: 1 streams (or more)
```

---

## 5. Known Limitations

### cAdvisor — no per-container labels with Docker 29+ containerd snapshotter

Docker 29+ defaults to `io.containerd.snapshotter.v1` which stores layer metadata differently from the classic `overlay2`. cAdvisor v0.52 attempts to look up layer info at `image/overlayfs/layerdb/mounts/<id>/mount-id`, which doesn't exist with the containerd snapshotter, so container discovery silently fails.

**Impact**: Container Resources dashboard shows no per-container CPU/RAM data.
**Workaround**: Host-level metrics (node-exporter) fully operational.
**Fix**: Add `"features": {"containerd-snapshotter": false}` to `/etc/docker/daemon.json` and re-pull all images (~5 GB, ~30-60 min downtime). Schedule during a maintenance window.

---

## 6. Rollback

```bash
docker compose -f compose/observability/docker-compose.yml down
# Data volumes are preserved; re-run bring-up to restore
```

To destroy data volumes completely:

```bash
docker compose -f compose/observability/docker-compose.yml down -v
```

---

## Sources

- ADR-0007: `docs/decisions/adr/ADR-0007-observability-prometheus-loki-grafana.md`
- Prometheus docs: https://prometheus.io/docs/
- Loki Docker driver: https://grafana.com/docs/loki/latest/clients/docker-driver/
