# Manual Test Cases: AI Inference Stack

**Specs**: `openspec/changes/phase-4-ai-inference-stack/specs/`
**Stack**: `compose/ai/`
**Prerequisites**: Stack is deployed per `docs/runbooks/ai-stack.md`

---

## TC-01 — Stack starts and all containers reach healthy

**Covers**: Requirements — Ollama GPU service, LiteLLM proxy, Open WebUI; all healthchecks

### Setup

```bash
./scripts/secrets-decrypt.sh ai
docker compose -f compose/ai/docker-compose.yml down 2>/dev/null || true
```

### Steps

1. Bring up the stack:
   ```bash
   docker compose -f compose/ai/docker-compose.yml up -d
   ```

2. Wait up to 90 seconds, then check status:
   ```bash
   docker compose -f compose/ai/docker-compose.yml ps
   ```

3. Check each container's health individually:
   ```bash
   docker inspect --format '{{.Name}} → {{.State.Health.Status}}' ollama litellm open-webui
   ```

### Expected Results

- All three containers: `STATUS` = `running (healthy)`
- No container in `restarting` or `exited` state

### Pass / Fail

| Check | Result |
|-------|--------|
| `ollama` healthy | ☐ Pass ☐ Fail |
| `litellm` healthy | ☐ Pass ☐ Fail |
| `open-webui` healthy | ☐ Pass ☐ Fail |

---

## TC-02 — Ollama has GPU access (ROCm)

**Covers**: Requirement — GPU-accelerated service; Scenario — Service starts with GPU access

### Steps

1. Check Ollama logs for ROCm device detection:
   ```bash
   docker logs ollama 2>&1 | grep -iE "rocm|gfx|amdgpu|gpu" | head -10
   ```

2. Verify GPU device nodes are accessible inside the container:
   ```bash
   docker exec ollama ls /dev/kfd /dev/dri/renderD128
   ```

3. Run a trivial inference to confirm GPU is used (small model — pulls ~4 GB if absent):
   ```bash
   docker exec ollama ollama run qwen2.5-coder:7b "Reply with one word: hello"
   ```

### Expected Results

- Logs contain ROCm/GFX version lines (e.g. `gfx1150` or `HSA override`)
- `/dev/kfd` and `/dev/dri/renderD128` are present in the container
- Inference returns a short response without error

### Pass / Fail

| Check | Result |
|-------|--------|
| ROCm device detected in Ollama logs | ☐ Pass ☐ Fail |
| `/dev/kfd` accessible in container | ☐ Pass ☐ Fail |
| Quick inference completes without error | ☐ Pass ☐ Fail |

---

## TC-03 — Ollama port not exposed to host

**Covers**: Requirement — Ollama exposes API only on internal network

### Steps

```bash
# Port 11434 must not appear in host port bindings
docker compose -f compose/ai/docker-compose.yml ps | grep ollama
ss -tlnp | grep 11434
```

### Expected Results

- `docker compose ps` shows no `0.0.0.0:11434` mapping for Ollama
- `ss` returns no output for port 11434

### Pass / Fail

| Check | Result |
|-------|--------|
| Port 11434 not host-bound (`docker compose ps`) | ☐ Pass ☐ Fail |
| Port 11434 not in `ss` output | ☐ Pass ☐ Fail |

---

## TC-04 — LiteLLM authenticates API requests

**Covers**: Requirement — Master-key authentication; Scenarios — Reject without token, accept with token

### Setup

```bash
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2)
```

### Steps

**4a — Request without auth is rejected:**

```bash
curl -sk -o /dev/null -w "%{http_code}\n" \
  -X POST https://litellm.hal.local/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder:32b","messages":[{"role":"user","content":"hi"}]}'
```

Expected: `401`

**4b — Request with correct key succeeds:**

```bash
curl -sk -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  https://litellm.hal.local/models
```

Expected: `200`

**4c — Request with wrong key is rejected:**

```bash
curl -sk -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer sk-wrongkey" \
  https://litellm.hal.local/models
```

Expected: `401`

### Pass / Fail

| Check | Result |
|-------|--------|
| No auth → 401 | ☐ Pass ☐ Fail |
| Correct key → 200 | ☐ Pass ☐ Fail |
| Wrong key → 401 | ☐ Pass ☐ Fail |

---

## TC-05 — LiteLLM routes model roster to Ollama

**Covers**: Requirement — Routes only to local Ollama; Scenario — Model routing targets Ollama

### Setup

```bash
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2)
```

### Steps

1. List registered models:
   ```bash
   curl -skf -H "Authorization: Bearer ${MASTER_KEY}" \
     https://litellm.hal.local/models | python3 -m json.tool | grep '"id"'
   ```

2. Verify at least the three roster models are present:
   - `qwen2.5-coder:32b`
   - `deepseek-r1:32b`
   - `llama3.3:70b`

3. Send a completion to one roster model:
   ```bash
   curl -skf -X POST https://litellm.hal.local/v1/chat/completions \
     -H "Authorization: Bearer ${MASTER_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"model":"qwen2.5-coder:32b","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' \
     | python3 -m json.tool | grep '"content"'
   ```

### Expected Results

- Models endpoint lists all three roster models
- Completion returns a `choices[0].message.content` without error

### Pass / Fail

| Check | Result |
|-------|--------|
| `qwen2.5-coder:32b` listed | ☐ Pass ☐ Fail |
| `deepseek-r1:32b` listed | ☐ Pass ☐ Fail |
| `llama3.3:70b` listed | ☐ Pass ☐ Fail |
| Completion request returns valid response | ☐ Pass ☐ Fail |

---

## TC-06 — LiteLLM port not exposed to host

**Covers**: Requirement — LiteLLM port not host-mapped

### Steps

```bash
docker compose -f compose/ai/docker-compose.yml ps | grep litellm
ss -tlnp | grep 4000
```

### Expected Results

- No `0.0.0.0:4000` mapping shown
- `ss` returns no output for port 4000

### Pass / Fail

| Check | Result |
|-------|--------|
| Port 4000 not host-bound (`docker compose ps`) | ☐ Pass ☐ Fail |
| Port 4000 not in `ss` output | ☐ Pass ☐ Fail |

---

## TC-07 — Open WebUI is accessible via Traefik HTTPS

**Covers**: Requirement — HTTPS access via Traefik; Scenario — HTTPS access via Traefik

### Prerequisites

`openwebui.hal.local` resolves to HAL-10k. If not:
```bash
echo "127.0.0.1  openwebui.hal.local litellm.hal.local" | sudo tee -a /etc/hosts
```

### Steps

1. Check via curl:
   ```bash
   curl -sk -o /dev/null -w "%{http_code}\n" https://openwebui.hal.local/

   ```

2. Check TLS certificate:
   ```bash
   echo | openssl s_client -connect openwebui.hal.local:443 -servername openwebui.hal.local 2>/dev/null \
     | openssl x509 -noout -subject -ext subjectAltName
   ```

3. Open in a browser: `https://openwebui.hal.local` — verify the login page loads.

### Expected Results

- curl returns `200`
- Certificate subject is `*.hal.local`
- Login page renders in the browser

### Pass / Fail

| Check | Result |
|-------|--------|
| curl returns 200 | ☐ Pass ☐ Fail |
| Certificate CN is `*.hal.local` | ☐ Pass ☐ Fail |
| Login page loads in browser | ☐ Pass ☐ Fail |

---

## TC-08 — Open WebUI port not exposed to host

**Covers**: Requirement — Port not exposed to host

### Steps

```bash
docker compose -f compose/ai/docker-compose.yml ps | grep open-webui
ss -tlnp | grep 8080
```

### Expected Results

- No `0.0.0.0:8080` mapping for `open-webui`
- `ss` returns no output for port 8080

### Pass / Fail

| Check | Result |
|-------|--------|
| Port 8080 not host-bound (`docker compose ps`) | ☐ Pass ☐ Fail |
| Port 8080 not in `ss` output | ☐ Pass ☐ Fail |

---

## TC-09 — Open WebUI shows LiteLLM models in selector

**Covers**: Requirement — Open WebUI connected to LiteLLM; Scenario — Models visible in WebUI

### Steps

1. Open `https://openwebui.hal.local` in a browser
2. Create an account or log in
3. Open a new chat — click the model selector dropdown

### Expected Results

- At least `qwen2.5-coder:32b`, `deepseek-r1:32b`, and `llama3.3:70b` appear in the list
- Selecting a model and sending a message returns a valid response

### Pass / Fail

| Check | Result |
|-------|--------|
| Roster models appear in model selector | ☐ Pass ☐ Fail |
| Chat response received without error | ☐ Pass ☐ Fail |

---

## TC-10 — Open WebUI data persists across container restart

**Covers**: Requirement — Data persists; Scenario — Chat history survives recreation

### Steps

1. Open `https://openwebui.hal.local`, create an account, start a chat, send a message.

2. Recreate the container (does not remove the volume):
   ```bash
   docker compose -f compose/ai/docker-compose.yml up -d --force-recreate open-webui
   ```

3. Wait for healthy, then reload `https://openwebui.hal.local`.

### Expected Results

- Account and chat history are intact after recreation
- Named volume `open_webui_data` still exists:
  ```bash
  docker volume ls | grep open_webui_data
  ```

### Pass / Fail

| Check | Result |
|-------|--------|
| Chat history intact after recreation | ☐ Pass ☐ Fail |
| `open_webui_data` volume present | ☐ Pass ☐ Fail |

---

## TC-11 — Model weights survive Ollama container recreation

**Covers**: Requirement — Model weights stored at well-known host path; Scenario — Models survive recreation

### Steps

1. Note current model list:
   ```bash
   docker exec ollama ollama list
   ```

2. Recreate the Ollama container:
   ```bash
   docker compose -f compose/ai/docker-compose.yml up -d --force-recreate ollama
   ```

3. Wait for healthy, then check models:
   ```bash
   docker exec ollama ollama list
   ```

### Expected Results

- Model list is identical before and after recreation
- Weights directory still populated:
  ```bash
  ls /srv/platform/models/blobs/ | wc -l
  ```

### Pass / Fail

| Check | Result |
|-------|--------|
| Models present after recreation | ☐ Pass ☐ Fail |
| `/srv/platform/models/` bind-mount intact | ☐ Pass ☐ Fail |

---

## TC-12 — Stack survives host reboot

**Covers**: Requirements — `restart: unless-stopped` on all services

### Steps

1. Confirm stack is running:
   ```bash
   docker compose -f compose/ai/docker-compose.yml ps
   ```

2. Reboot:
   ```bash
   sudo reboot
   ```

3. After the host comes back up (~60 s), SSH in and check:
   ```bash
   docker compose -f compose/ai/docker-compose.yml ps
   docker inspect --format '{{.Name}} → {{.State.Health.Status}}' ollama litellm open-webui
   ```

### Expected Results

- All three containers are running (healthy) without manual intervention

### Pass / Fail

| Check | Result |
|-------|--------|
| `ollama` auto-restarted and healthy | ☐ Pass ☐ Fail |
| `litellm` auto-restarted and healthy | ☐ Pass ☐ Fail |
| `open-webui` auto-restarted and healthy | ☐ Pass ☐ Fail |

---

## TC-13 — Plaintext secrets not in repository

**Covers**: Requirement — Master key never stored in plaintext; Scenario — No plaintext in repo

### Steps

```bash
cd /srv/platform/repos/hal-10k-platform

# Must find no matches (excludes .example files and encrypted .enc.yaml)
git grep -iE "(LITELLM_MASTER_KEY|OPENAI_API_KEY|WEBUI_SECRET_KEY)\s*[:=]\s*[^<]" \
  -- ':!*.example' ':!*.enc.yaml' ':!*.md'
echo "Matches found: $?"
```

A non-zero exit code (no matches) is the expected outcome.

### Expected Results

- `git grep` returns exit code `1` (no matches)
- No line in the repository contains a raw key value outside of example/encrypted files

### Pass / Fail

| Check | Result |
|-------|--------|
| `git grep` finds no plaintext secrets | ☐ Pass ☐ Fail |
| `secrets/ai.enc.yaml` is SOPS-encrypted (not plaintext YAML) | ☐ Pass ☐ Fail |

---

## TC-14 — Documentation complete

**Covers**: Operational readiness

### Steps

```bash
ls docs/runbooks/ai-stack.md
ls docs/runbooks/model-management.md
ls docs/runbooks/ai-client-setup.md
ls docs/decisions/adr/ADR-0006-llm-serving-ollama-litellm.md
ls docs/services-catalog.md
```

Visual inspection checklist:
- [ ] `ai-stack.md` covers bring-up, tear-down, GPU verification, secret rotation
- [ ] `model-management.md` covers pull, list, remove, add to LiteLLM config
- [ ] `ai-client-setup.md` covers Claude Code and Cline configuration
- [ ] `ADR-0006` states decision, rationale, and alternatives considered
- [ ] `services-catalog.md` lists all three AI services with image, port, network, volume

### Pass / Fail

| Check | Result |
|-------|--------|
| `ai-stack.md` exists | ☐ Pass ☐ Fail |
| `model-management.md` exists | ☐ Pass ☐ Fail |
| `ai-client-setup.md` exists | ☐ Pass ☐ Fail |
| `ADR-0006` exists | ☐ Pass ☐ Fail |
| `services-catalog.md` exists and covers AI stack | ☐ Pass ☐ Fail |

---

## Test Run Summary

| TC | Description | Result | Notes |
|----|-------------|--------|-------|
| TC-01 | All containers start healthy | ☐ Pass ☐ Fail | |
| TC-02 | Ollama GPU access (ROCm) | ☐ Pass ☐ Fail | |
| TC-03 | Ollama port not host-exposed | ☐ Pass ☐ Fail | |
| TC-04 | LiteLLM rejects/accepts by master key | ☐ Pass ☐ Fail | |
| TC-05 | LiteLLM routes full model roster | ☐ Pass ☐ Fail | |
| TC-06 | LiteLLM port not host-exposed | ☐ Pass ☐ Fail | |
| TC-07 | Open WebUI HTTPS via Traefik | ☐ Pass ☐ Fail | |
| TC-08 | Open WebUI port not host-exposed | ☐ Pass ☐ Fail | |
| TC-09 | Open WebUI shows LiteLLM models | ☐ Pass ☐ Fail | |
| TC-10 | Open WebUI data persists on restart | ☐ Pass ☐ Fail | |
| TC-11 | Ollama models survive recreation | ☐ Pass ☐ Fail | |
| TC-12 | Stack survives host reboot | ☐ Pass ☐ Fail | |
| TC-13 | No plaintext secrets in repo | ☐ Pass ☐ Fail | |
| TC-14 | Documentation complete | ☐ Pass ☐ Fail | |

**Tester**: _______________  **Date**: _______________  **Stack versions**: see `compose/ai/.env`
