# Manual Test Cases: Traefik Core Stack

**Spec**: `openspec/changes/add-traefik-internal-ingress/specs/traefik-core-proxy/spec.md`
**Stack**: `compose/core`
**Prerequisites**: Stack is deployed per `docs/runbooks/core-traefik.md`

---

## TC-01 — Core stack starts successfully

**Covers**: Requirement — Traefik v3 reverse proxy deployed as core stack

### Setup

```bash
# Ensure prerequisites are met
./scripts/create-traefik-network.sh
./scripts/secrets-decrypt.sh core
# Extract TLS files if not already present
python3 -c "
import yaml, base64, os
d = yaml.safe_load(open('/srv/platform/secrets/core.yaml'))
for f,k in [('hal-local.crt','TRAEFIK_TLS_CERT'),('hal-local.key','TRAEFIK_TLS_KEY')]:
    p = f'/srv/platform/secrets/{f}'
    open(p,'wb').write(base64.b64decode(d[k])); os.chmod(p,0o600)
"
docker compose -f compose/core/docker-compose.yml down 2>/dev/null || true
```

### Steps

1. Start the stack:
   ```bash
   docker compose -f compose/core/docker-compose.yml up -d
   ```

2. Wait up to 30 seconds, then check status:
   ```bash
   docker compose -f compose/core/docker-compose.yml ps
   ```

3. Verify port bindings:
   ```bash
   ss -tlnp | grep -E ':(80|443|8080)\b'
   ```

### Expected Results

- `docker compose ps` shows both `core-traefik-1` and `core-docker-socket-proxy-1` running
- `core-traefik-1` STATUS column shows `(healthy)`
- Port 80, 443, and 8080 appear in `ss` output bound to `0.0.0.0`

### Pass / Fail

| Check | Result |
|-------|--------|
| Both containers running | ☐ Pass ☐ Fail |
| `core-traefik-1` reports `healthy` | ☐ Pass ☐ Fail |
| Ports 80, 443, 8080 bound | ☐ Pass ☐ Fail |

---

## TC-02 — Traefik survives host reboot

**Covers**: Scenario — Traefik survives host reboot

### Steps

1. Confirm the stack is running:
   ```bash
   docker compose -f compose/core/docker-compose.yml ps
   ```

2. Reboot the host:
   ```bash
   sudo reboot
   ```

3. After the host comes back up (allow ~60 seconds), SSH in and check:
   ```bash
   docker compose -f compose/core/docker-compose.yml ps
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ping
   ```

### Expected Results

- Both containers are running without manual intervention
- Ping returns `200`

### Pass / Fail

| Check | Result |
|-------|--------|
| Containers auto-started after reboot | ☐ Pass ☐ Fail |
| Ping returns 200 | ☐ Pass ☐ Fail |

---

## TC-03 — Network creation is idempotent

**Covers**: Requirement — Shared `traefik` Docker network

### Steps

1. Run the network creation script twice in succession:
   ```bash
   ./scripts/create-traefik-network.sh
   ./scripts/create-traefik-network.sh
   echo "Exit code: $?"
   ```

2. Confirm exactly one network exists:
   ```bash
   docker network ls | grep traefik | wc -l
   ```

### Expected Results

- Both script invocations exit 0 with no error output
- Second run prints `Network 'traefik' already exists — nothing to do.`
- Network count is exactly `1`

### Pass / Fail

| Check | Result |
|-------|--------|
| Second run exits 0 without error | ☐ Pass ☐ Fail |
| Second run prints "already exists" message | ☐ Pass ☐ Fail |
| Exactly one `traefik` network exists | ☐ Pass ☐ Fail |

---

## TC-04 — Hostname-based routing via Docker labels

**Covers**: Requirement — Hostname-based routing; Scenario — Routing to a labeled service; Scenario — Unlabeled container is not routed

### Setup

Start a labeled test container:

```bash
docker run -d --name test-echo \
  --network traefik \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.test-echo.rule=Host(\`echo.hal.local\`)" \
  --label "traefik.http.routers.test-echo.entrypoints=websecure" \
  --label "traefik.http.routers.test-echo.tls=true" \
  --label "traefik.http.services.test-echo.loadbalancer.server.port=80" \
  nginx:alpine
```

Start an unlabeled container for the negative test:

```bash
docker run -d --name test-unlabeled --network traefik nginx:alpine
```

### Steps

**4a — Labeled service is routed:**

```bash
# Check Traefik dashboard API for the registered router
curl -s -u "admin:<password>" -H "Host: hal-10k.local" \
  http://localhost:8080/api/http/routers | grep test-echo
```

Expected: `test-echo@docker` router appears in the API response.

```bash
# Request reaches the backend (expect nginx default page, TLS warning is expected)
curl -sk -H "Host: echo.hal.local" https://localhost/ | grep -i "Welcome to nginx"
```

**4b — Unlabeled container is not routed:**

```bash
curl -s -u "admin:<password>" -H "Host: hal-10k.local" \
  http://localhost:8080/api/http/routers | grep test-unlabeled
```

Expected: no output (unlabeled container not registered).

### Teardown

```bash
docker rm -f test-echo test-unlabeled
```

### Pass / Fail

| Check | Result |
|-------|--------|
| `test-echo@docker` appears in router API | ☐ Pass ☐ Fail |
| HTTPS request to `echo.hal.local` returns nginx page | ☐ Pass ☐ Fail |
| `test-unlabeled` does NOT appear in router API | ☐ Pass ☐ Fail |

---

## TC-05 — HTTPS with self-signed wildcard TLS certificate

**Covers**: Requirement — HTTPS with self-signed wildcard TLS; Scenario — HTTPS request is served

### Steps

1. Inspect the TLS certificate Traefik is serving:
   ```bash
   echo | openssl s_client -connect localhost:443 -servername test.hal.local 2>/dev/null \
     | openssl x509 -noout -subject -issuer -dates
   ```

2. Confirm the wildcard SAN covers `*.hal.local`:
   ```bash
   echo | openssl s_client -connect localhost:443 -servername test.hal.local 2>/dev/null \
     | openssl x509 -noout -ext subjectAltName
   ```

### Expected Results

- `subject` shows `CN = *.hal.local`
- `subjectAltName` includes `DNS:*.hal.local` and `DNS:hal.local`
- Certificate is not expired (`notAfter` is in the future)

### Pass / Fail

| Check | Result |
|-------|--------|
| Certificate CN is `*.hal.local` | ☐ Pass ☐ Fail |
| SAN covers `*.hal.local` and `hal.local` | ☐ Pass ☐ Fail |
| Certificate not expired | ☐ Pass ☐ Fail |

---

## TC-06 — HTTP redirects to HTTPS

**Covers**: Scenario — HTTP redirects to HTTPS

### Steps

```bash
curl -s -o /dev/null -w "%{http_code} → %{redirect_url}\n" \
  -H "Host: anyservice.hal.local" \
  http://localhost:80/some/path
```

### Expected Results

- HTTP status `301`
- `redirect_url` is `https://anyservice.hal.local/some/path`

### Pass / Fail

| Check | Result |
|-------|--------|
| Response is 301 | ☐ Pass ☐ Fail |
| Location header points to `https://` equivalent | ☐ Pass ☐ Fail |

---

## TC-07 — Dashboard authenticated access

**Covers**: Requirement — Dashboard secured with basic-auth; Scenario — Authenticated dashboard access

### Prerequisites

`hal-10k.local` must resolve on the machine running the browser. If not already set:

```bash
# On HAL-10k itself (browser on same host):
echo "127.0.0.1  hal-10k.local" | sudo tee -a /etc/hosts

# From another LAN machine (replace with HAL-10k's actual IP):
echo "192.168.x.x  hal-10k.local" | sudo tee -a /etc/hosts
```

> **Note**: `http://localhost:8080/dashboard/` returns 404 in the browser — Traefik's router
> requires `Host: hal-10k.local` and `localhost` does not match.

### Steps

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -u "admin:<password>" \
  -H "Host: hal-10k.local" \
  http://localhost:8080/dashboard/
```

Also verify in a browser: navigate to `http://hal-10k.local:8080/dashboard/`, enter credentials.

### Expected Results

- curl returns `200`
- Browser shows the Traefik dashboard with registered routers and services visible

### Pass / Fail

| Check | Result |
|-------|--------|
| curl returns 200 with valid credentials | ☐ Pass ☐ Fail |
| Dashboard renders in browser | ☐ Pass ☐ Fail |

---

## TC-08 — Dashboard unauthenticated access rejected

**Covers**: Scenario — Unauthenticated access is rejected

### Steps

```bash
# No credentials
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: hal-10k.local" \
  http://localhost:8080/dashboard/

# Wrong password
curl -s -o /dev/null -w "%{http_code}\n" \
  -u "admin:wrongpassword" \
  -H "Host: hal-10k.local" \
  http://localhost:8080/dashboard/
```

### Expected Results

- Both requests return `401`
- Dashboard HTML is not present in the response body

### Pass / Fail

| Check | Result |
|-------|--------|
| No credentials → 401 | ☐ Pass ☐ Fail |
| Wrong password → 401 | ☐ Pass ☐ Fail |

---

## TC-09 — Stack start with decrypted secrets

**Covers**: Scenario — Stack start with decrypted secrets

### Steps

1. Confirm `secrets/core.yaml` exists:
   ```bash
   ls -la /srv/platform/secrets/core.yaml
   ```

2. Start the stack and confirm no secret-related errors in logs:
   ```bash
   docker compose -f compose/core/docker-compose.yml up -d
   docker compose -f compose/core/docker-compose.yml logs traefik 2>&1 | grep -i "secret\|env_file\|error" | head -10
   ```

3. Confirm env vars are present inside the container:
   ```bash
   docker exec core-traefik-1 env | grep TRAEFIK_DASHBOARD_AUTH
   ```

### Expected Results

- `core.yaml` exists with mode `600`
- No secret or env_file errors in Traefik logs
- `TRAEFIK_DASHBOARD_AUTH` is set and contains `admin:$apr1$...`

### Pass / Fail

| Check | Result |
|-------|--------|
| `core.yaml` exists, mode 600 | ☐ Pass ☐ Fail |
| No env_file errors in logs | ☐ Pass ☐ Fail |
| `TRAEFIK_DASHBOARD_AUTH` set in container | ☐ Pass ☐ Fail |

---

## TC-10 — Missing secrets file causes startup failure

**Covers**: Scenario — Missing secrets file causes startup failure

### Setup

```bash
docker compose -f compose/core/docker-compose.yml down
sudo mv /srv/platform/secrets/core.yaml /srv/platform/secrets/core.yaml.bak
```

### Steps

```bash
docker compose -f compose/core/docker-compose.yml up -d
echo "Exit code: $?"
```

### Expected Results

- Docker Compose exits with a **non-zero** exit code
- Output mentions that the env_file `/srv/platform/secrets/core.yaml` is missing or not found

### Teardown

```bash
sudo mv /srv/platform/secrets/core.yaml.bak /srv/platform/secrets/core.yaml
docker compose -f compose/core/docker-compose.yml up -d
```

### Pass / Fail

| Check | Result |
|-------|--------|
| `docker compose up` exits non-zero | ☐ Pass ☐ Fail |
| Error message references missing env_file | ☐ Pass ☐ Fail |

---

## TC-11 — Operational documentation present and complete

**Covers**: Requirement — Operational runbook and ADR

### Steps

1. Confirm both documents exist:
   ```bash
   ls docs/runbooks/core-traefik.md
   ls docs/decisions/adr/ADR-0004-reverse-proxy-traefik.md
   ls docs/decisions/adr/ADR-0005-docker-socket-proxy.md
   ```

2. Verify runbook covers key sections (visual inspection):
   - [ ] Prerequisites listed
   - [ ] Step-numbered deployment procedure
   - [ ] TLS cert extraction commands
   - [ ] Label convention for downstream stacks
   - [ ] Rollback instructions
   - [ ] Troubleshooting table

3. Verify ADR-0004 covers:
   - [ ] Context explaining the problem
   - [ ] Decision stated clearly
   - [ ] Rationale with comparison table (Traefik vs Caddy vs nginx-proxy)
   - [ ] Alternatives rejected section

### Pass / Fail

| Check | Result |
|-------|--------|
| `core-traefik.md` exists | ☐ Pass ☐ Fail |
| `ADR-0004` exists | ☐ Pass ☐ Fail |
| `ADR-0005` exists | ☐ Pass ☐ Fail |
| Runbook covers full lifecycle | ☐ Pass ☐ Fail |
| ADR-0004 documents alternatives | ☐ Pass ☐ Fail |

---

## Test Run Summary

| TC | Description | Result | Notes |
|----|-------------|--------|-------|
| TC-01 | Stack starts, both containers healthy | ☐ Pass ☐ Fail | |
| TC-02 | Survives reboot | ☐ Pass ☐ Fail | |
| TC-03 | Network creation idempotent | ☐ Pass ☐ Fail | |
| TC-04 | Label-based routing; unlabeled excluded | ☐ Pass ☐ Fail | |
| TC-05 | Wildcard TLS cert served on port 443 | ☐ Pass ☐ Fail | |
| TC-06 | HTTP 301 → HTTPS | ☐ Pass ☐ Fail | |
| TC-07 | Dashboard: authenticated → 200 | ☐ Pass ☐ Fail | |
| TC-08 | Dashboard: unauthenticated → 401 | ☐ Pass ☐ Fail | |
| TC-09 | Stack loads secrets from env_file | ☐ Pass ☐ Fail | |
| TC-10 | Missing secrets → non-zero exit | ☐ Pass ☐ Fail | |
| TC-11 | Runbook and ADRs present | ☐ Pass ☐ Fail | |

**Tester**: _______________  **Date**: _______________  **Stack version**: `traefik:v3.3`
