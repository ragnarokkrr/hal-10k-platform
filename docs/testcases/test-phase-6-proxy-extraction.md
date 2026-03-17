# Test Runbook: Phase 6 — LiteLLM Proxy Extraction

Validates that LiteLLM has been successfully extracted from `compose/ai/` into the
standalone `compose/proxy/` gateway stack.

**Prerequisites**: both `compose/ai/` and `compose/proxy/` stacks are running.

```bash
# Verify compose/ai/ — expect ollama (healthy) and open-webui (healthy)
docker compose -f compose/ai/docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}'

# Verify compose/proxy/ — expect litellm (healthy)
docker compose -f compose/proxy/docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}'

# Verify proxy secrets are decrypted
ls -l /srv/platform/secrets/proxy.yaml
```

If any container is not healthy, bring up the missing stack before proceeding:

```bash
# Start inference stack first (creates ai_internal network)
docker compose -f compose/ai/docker-compose.yml up -d

# Then start proxy stack
docker compose -f compose/proxy/docker-compose.yml up -d
```

---

## (a) Verify `ai_internal` network and container membership

```bash
# Network exists with the correct name (not project-prefixed ai_ai_internal)
docker network ls --filter name=ai_internal --format 'Name={{.Name}}'
# Expected: ai_internal

# Both ollama and litellm are attached; open-webui is also attached
docker network inspect ai_internal --format '{{range .Containers}}{{.Name}} {{end}}'
# Expected output contains: ollama  litellm  open-webui (order may vary)
```

---

## (b) Verify `compose/ai/` has no litellm container

```bash
docker compose -f compose/ai/docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}'
# Expected: only ollama and open-webui listed — NO litellm row
```

---

## (c) Verify LiteLLM models endpoint lists all three models

```bash
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/proxy.yaml | cut -d' ' -f2)

curl -sk -H "Authorization: Bearer ${MASTER_KEY}" \
  https://litellm.hal.local/models | jq '.data[].id'
# Expected:
# "qwen2.5-coder:32b"
# "deepseek-r1:32b"
# "llama3.3:70b"
```

---

## (d) Verify Open WebUI chat completes a round-trip via the proxy

1. Open `https://openwebui.hal.local` in a browser
2. Log in (or create an account on first visit)
3. Select any model from the roster (e.g. `qwen2.5-coder:32b`)
4. Send a short message: `Say hello in one sentence`
5. Confirm a response is received

> A response confirms the full path: Open WebUI → LiteLLM (proxy) → Ollama → response.

---

## (e) Verify Traefik routes both hostnames independently

```bash
# LiteLLM health via Traefik
curl -sk -o /dev/null -w "%{http_code}" https://litellm.hal.local/health/liveliness
# Expected: 200

# Open WebUI health via Traefik
curl -sk -o /dev/null -w "%{http_code}" https://openwebui.hal.local/health
# Expected: 200
```

---

## (f) Verify proxy stack restarts independently of `compose/ai/`

```bash
# Restart proxy stack
docker compose -f compose/proxy/docker-compose.yml restart litellm

# Confirm ai stack containers are unaffected
docker compose -f compose/ai/docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}'
# Expected: ollama and open-webui remain running (healthy) — no restarts triggered

# Wait for LiteLLM to recover
docker inspect --format '{{.State.Health.Status}}' litellm
# Expected: healthy (within ~60s)

# Re-check models endpoint
curl -sk -H "Authorization: Bearer ${MASTER_KEY}" \
  https://litellm.hal.local/models | jq '.data[].id'
# Expected: all three models listed again
```
