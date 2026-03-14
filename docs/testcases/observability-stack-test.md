# Manual Test Cases: Observability Stack

**Stack**: `compose/observability/`
**Prerequisites**: Stack deployed per `docs/runbooks/observability.md`

---

## TC-01 — Stack starts and all containers reach healthy

**Covers**: All five services start with healthchecks passing

### Setup

```bash
./scripts/secrets-decrypt.sh observability
docker compose -f compose/observability/docker-compose.yml down 2>/dev/null || true
```

### Steps

1. Bring up the stack:
   ```bash
   docker compose -f compose/observability/docker-compose.yml up -d
   ```

2. Wait up to 90 seconds, then check status:
   ```bash
   docker compose -f compose/observability/docker-compose.yml ps
   ```

3. Check each container's health:
   ```bash
   docker inspect --format '{{.Name}} → {{.State.Health.Status}}' \
     prometheus loki grafana node-exporter cadvisor
   ```

### Expected Results

- All five containers: `STATUS` = `running (healthy)`
- No container in `restarting` or `exited` state

---

## TC-02 — Prometheus scrapes all four targets

**Covers**: Prometheus, Node Exporter, cAdvisor, Traefik scrape jobs active

### Steps

```bash
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(t['labels']['job'], '->', t['health'])
"
```

### Expected Results

```
prometheus -> up
node-exporter -> up
cadvisor -> up
traefik -> up
```

---

## TC-03 — Node Exporter exposes host metrics

**Covers**: CPU, RAM, disk, and network metrics visible in Prometheus

### Steps

```bash
# CPU metric
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('CPU series:', len(d['data']['result']))"

# RAM metric
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); v=d['data']['result'][0]['value'][1]; print('RAM bytes:', v)"

# Disk metric
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=node_filesystem_size_bytes%7Bmountpoint%3D%22%2Fsrv%22%7D' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('Disk series:', len(d['data']['result']))"
```

### Expected Results

- `CPU series` > 0
- `RAM bytes` is a large positive integer (e.g. ~117 GB = 117767901184)
- `Disk series` = 1

---

## TC-04 — Traefik metrics scraped

**Covers**: Traefik v3 entrypoint request metrics available

### Steps

```bash
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=traefik_entrypoint_requests_total' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('Traefik series:', len(d['data']['result']))"
```

### Expected Results

- `Traefik series` > 0 (some traffic will have occurred on `websecure` entrypoint)

---

## TC-05 — Grafana accessible via Traefik

**Covers**: Grafana UI reachable at `https://grafana.hal.local`, Traefik routing working

### Prerequisites

- `/etc/hosts` contains `127.0.0.1 grafana.hal.local`

### Steps

```bash
curl -sk -o /dev/null -w "%{http_code}" https://grafana.hal.local/login
```

### Expected Results

- HTTP status `200`

---

## TC-06 — Grafana datasources provisioned

**Covers**: Prometheus and Loki datasources auto-provisioned with correct UIDs

### Steps

```bash
# Get the admin password from secrets
GF_PASS=$(grep GF_SECURITY_ADMIN_PASSWORD /srv/platform/secrets/observability.yaml | awk '{print $2}')

curl -sk -u "admin:${GF_PASS}" \
  https://grafana.hal.local/api/datasources \
  | python3 -c "
import json,sys
ds=json.load(sys.stdin)
for d in ds:
    print(d['name'], 'uid:', d['uid'], 'type:', d['type'])
"
```

### Expected Results

```
Prometheus uid: prometheus type: prometheus
Loki uid: loki type: loki
```

---

## TC-07 — Grafana dashboards provisioned

**Covers**: All six dashboards present in Grafana

### Steps

```bash
GF_PASS=$(grep GF_SECURITY_ADMIN_PASSWORD /srv/platform/secrets/observability.yaml | awk '{print $2}')

curl -sk -u "admin:${GF_PASS}" \
  "https://grafana.hal.local/api/search?type=dash-db" \
  | python3 -c "
import json,sys
dbs=json.load(sys.stdin)
for d in dbs:
    print(d['uid'], d['title'])
"
```

### Expected Results

```
hal-host-overview  Host Overview
hal-traefik        Traefik
hal-ollama         Ollama Inference
hal-litellm        LiteLLM Proxy
hal-container      Container Resources
hal-gpu-rocm       GPU ROCm
```

---

## TC-08 — Host Overview dashboard shows data

**Covers**: Grafana Host Overview dashboard renders live data

### Steps

1. Open `https://grafana.hal.local` in a browser
2. Navigate to Dashboards → Host Overview
3. Verify panels show current values (not "No data")

### Expected Results

- CPU Usage stat panel: shows percentage (e.g. 5-30%)
- RAM Used stat panel: shows percentage
- Disk Used (/srv/platform) stat panel: shows percentage
- System Uptime stat panel: shows duration (e.g. "2h 30m")
- Time-series panels (CPU over time, Memory, Network I/O, Disk I/O): display data lines

---

## TC-09 — Loki receives container logs

**Covers**: Docker Loki log driver pushing logs to Loki; logs queryable

### Steps

```bash
# Generate some log output
docker logs traefik 2>&1 | tail -1

# Query Loki for traefik logs
curl -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bcompose_service%3D%22traefik%22%7D&start=$(python3 -c "import time; print(int((time.time()-300)*1e9))")&end=$(python3 -c "import time; print(int(time.time()*1e9))")" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
streams = d['data']['result']
if streams:
    entries = streams[0]['values']
    print(f'Found {len(entries)} log entries from traefik in last 5 min')
    print('Sample:', entries[0][1][:80])
else:
    print('No log streams found')
"
```

### Expected Results

- `Found N log entries from traefik in last 5 min` where N > 0
- Sample log line is a valid Traefik access log entry

---

## TC-10 — Prometheus data retention (smoke test)

**Covers**: Prometheus TSDB writing and retaining data

### Steps

```bash
# Check TSDB status
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/tsdb/status' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
s=d['data']
print('Head series:', s.get('headStats',{}).get('numSeries',0))
print('Retention (config):', '30d')
"
```

### Expected Results

- `Head series` > 0 (metrics are being actively collected)

---

## TC-11 — Stack survives docker daemon restart

**Covers**: `restart: unless-stopped` policy; all services recover after host reboot

### Steps

1. Note current uptimes:
   ```bash
   docker compose -f compose/observability/docker-compose.yml ps
   ```

2. Restart Docker daemon:
   ```bash
   sudo systemctl restart docker
   sleep 30
   ```

3. Check all containers recovered:
   ```bash
   docker compose -f compose/observability/docker-compose.yml ps
   ```

### Expected Results

- All five containers return to `running (healthy)` status within 60 seconds of daemon restart
