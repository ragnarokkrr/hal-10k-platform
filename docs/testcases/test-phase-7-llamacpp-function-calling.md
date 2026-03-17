# Test Runbook: Phase 7 — llama.cpp Function-Calling Stack

**Phase**: Phase 7 — llama.cpp function-calling stack
**Status**: Verified
**Last verified**: 2026-03-17
**Performed by**: ragnarokkrr

---

## Purpose

Verify that the `compose/ai-tools/` llama.cpp stack is correctly deployed, that
function/tool calling works end-to-end via the LiteLLM `-tools` model aliases, and
that GPU access, network isolation, observability, and selective startup all function
as designed.

---

## Prerequisites

```bash
# Networks must exist
docker network ls | grep -E "ai_internal|observability_internal"

# LiteLLM must be running
docker compose -f compose/proxy/docker-compose.yml ps

# Set master key for API tests
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/proxy.yaml | awk '{print $2}')
```

---

## Test 1 — Container Startup and GPU Access

**Goal**: llama.cpp containers start, load models onto GPU, and reach `(healthy)`.

```bash
# Start primary model
docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b

# Wait for healthy (model load takes 60–120 s)
watch docker compose -f compose/ai-tools/docker-compose.yml ps

# Expected: llama-cpp-qwen32b  Status: Up ... (healthy)
```

**Verify GPU offload in logs:**

```bash
docker logs llama-cpp-qwen32b 2>&1 | grep "offloaded"
# Expected: load_tensors: offloaded 65/65 layers to GPU
```

**Verify ROCm device detection:**

```bash
docker logs llama-cpp-qwen32b 2>&1 | grep "ROCm"
# Expected: ggml_cuda_init: found 1 ROCm devices (Total VRAM: 56156 MiB)
```

---

## Test 2 — Function Calling End-to-End

**Goal**: POST to `/v1/chat/completions` with a `tools` array returns `tool_calls` in
the response.

```bash
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:32b-tools",
    "messages": [{"role": "user", "content": "Get the weather in Tokyo."}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather for a city",
        "parameters": {
          "type": "object",
          "properties": {"city": {"type": "string"}},
          "required": ["city"]
        }
      }
    }],
    "tool_choice": "required",
    "max_tokens": 100
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
c = d['choices'][0]
print('finish_reason:', c['finish_reason'])
print('tool_calls:', json.dumps(c['message'].get('tool_calls'), indent=2))
"
```

**Expected output:**

```
finish_reason: tool_calls
tool_calls: [
  {
    "function": {"arguments": "{\"city\": \"Tokyo\"}", "name": "get_weather"},
    "id": "...",
    "type": "function"
  }
]
```

---

## Test 3 — Multi-Model Routing

**Goal**: Each `-tools` alias routes to its dedicated llama.cpp container.

```bash
# Start second model
docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-deepseek32b

# Wait for healthy
sleep 90
docker compose -f compose/ai-tools/docker-compose.yml ps
# Expected: both llama-cpp-qwen32b and llama-cpp-deepseek32b show (healthy)

# Test deepseek route
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:32b-tools",
    "messages": [{"role": "user", "content": "List files in /tmp."}],
    "tools": [{"type": "function", "function": {"name": "list_files", "description": "List files", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}}],
    "tool_choice": "required",
    "max_tokens": 100
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('finish_reason:', d['choices'][0]['finish_reason'])"
# Expected: finish_reason: tool_calls
```

---

## Test 4 — Ollama Chat Still Works

**Goal**: The non-`-tools` aliases (via Ollama) continue to return chat completions.

> **Note:** Ensure Ollama has VRAM headroom. If 2× 32B llama.cpp containers are running,
> Ollama cannot load a second 32B model simultaneously (~46 GB llama.cpp + ~30 GB Ollama
> would exceed 56 GB usable VRAM). Stop one llama.cpp container, or unload the Ollama
> model after testing.

```bash
# Unload any cached Ollama model first if needed
# (Ollama image has no curl/wget — use the ollama CLI inside the container)
docker exec ollama ollama stop qwen2.5-coder:32b

# Stop one llama.cpp container if VRAM is tight
docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-deepseek32b

# Test Ollama route
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen2.5-coder:32b", "messages": [{"role": "user", "content": "Say hi"}], "max_tokens": 10}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('Ollama:', d['choices'][0]['message']['content'])"
# Expected: Ollama: Hi! (or similar)
```

---

## Test 5 — Network Isolation

**Goal**: llama.cpp containers are NOT directly reachable from the LAN (only via
LiteLLM on `ai_internal`). They are also reachable from Prometheus on
`observability_internal`.

```bash
# Verify container is on ai_internal
docker network inspect ai_internal | python3 -c "
import sys, json
data = json.load(sys.stdin)[0]
containers = list(data['Containers'].values())
names = [c['Name'] for c in containers]
print('Containers on ai_internal:', names)
"
# Expected: includes litellm, ollama, open-webui, and any llama.cpp containers currently running
# (llama-cpp-deepseek32b only appears if it is started)

# Verify container is on observability_internal
docker network inspect observability_internal | python3 -c "
import sys, json
data = json.load(sys.stdin)[0]
containers = list(data['Containers'].values())
names = [c['Name'] for c in containers]
print('Containers on observability_internal:', names)
"
# Expected: includes llama-cpp-qwen32b, prometheus, loki, grafana, etc.

# Verify NOT on traefik network (no direct external access)
docker inspect llama-cpp-qwen32b | python3 -c "
import sys, json
nets = list(json.load(sys.stdin)[0]['NetworkSettings']['Networks'].keys())
print('Networks:', nets)
assert 'traefik' not in nets, 'ERROR: llama.cpp on traefik!'
print('OK: not on traefik network')
"
```

---

## Test 6 — Selective Startup and Stop

**Goal**: Individual containers can be started and stopped without affecting others.

```bash
# Stop DeepSeek (to free VRAM)
docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-deepseek32b

# LiteLLM returns 502 for deepseek-r1:32b-tools (expected — container stopped)
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "deepseek-r1:32b-tools", "messages": [{"role":"user","content":"hi"}], "max_tokens": 5}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('message','OK')[:80])"
# Expected: error containing "502" or connection refused

# Qwen route still works
curl -sk https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen2.5-coder:32b-tools", "messages": [{"role":"user","content":"hi"}], "max_tokens": 5}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('qwen route:', d['choices'][0]['finish_reason'])"
# Expected: qwen route: stop or tool_calls

# Restart DeepSeek — LiteLLM auto-recovers
docker compose -f compose/ai-tools/docker-compose.yml start llama-cpp-deepseek32b
```

---

## Test 7 — Prometheus Scraping

**Goal**: Prometheus can scrape `/metrics` from each running llama.cpp container.

```bash
# Direct scrape test
docker exec prometheus wget -qO- http://llama-cpp-qwen32b:8080/metrics | head -10
# Expected: Prometheus metrics starting with "# HELP llamacpp:"

# Check Prometheus target status
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets' \
  | python3 -c "
import sys, json
targets = json.load(sys.stdin)['data']['activeTargets']
llama_targets = [t for t in targets if 'llama' in t.get('labels', {}).get('job', '')]
for t in llama_targets:
    print(t['labels']['job'], '->', t['health'])
"
# Expected:
# llama-cpp-qwen32b -> up
# llama-cpp-deepseek32b -> up (if running)
# llama-cpp-llama70b -> down (not running — expected)
```

---

## Test 8 — Loki Log Ingestion

**Goal**: Container stdout/stderr is shipped to Loki via the global Docker log driver.

```bash
docker exec loki wget -qO- \
  'http://localhost:3100/loki/api/v1/query_range?query={compose_service="llama-cpp-qwen32b"}&limit=5' \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
streams = d['data']['result']
print(f'Log streams found: {len(streams)}')
for stream in streams[:1]:
    for ts, line in stream['values'][:3]:
        print(line[:100])
"
# Expected: 1 or more streams, model loading log lines visible
```

---

## Test 9 — Open WebUI

**Goal**: Open WebUI still loads models and completes a chat message.

1. Open `https://openwebui.hal.local` in a browser
2. Confirm models list loads (qwen2.5-coder:32b, deepseek-r1:32b, llama3.3:70b)
3. Start a new chat, select `qwen2.5-coder:32b`, send a test message
4. Confirm a response is received

> Note: Open WebUI uses Ollama-backed models only. The `-tools` aliases are not shown
> in Open WebUI's model list.

---

## Known Constraints

### VRAM Budget

ROCm-accessible VRAM is ~56 GB (not 96 GB — the full 96 GB includes system RAM that
is not directly GPU-accessible via ROCm/HIP). Practical limits:

- 2× 32B llama.cpp containers: ~46 GB — fits comfortably
- 2× 32B llama.cpp + Ollama 32B model loaded: ~76 GB — exceeds 56 GB, Ollama load fails
- Operator must coordinate which models are loaded simultaneously

### HSA Override

AMD Radeon 8060S (gfx1102) requires `HSA_OVERRIDE_GFX_VERSION=11.0.0` (not 11.0.2).
Using 11.0.2 causes a segfault in `sched_reserve` during HIP kernel initialization.
Ollama uses 11.0.2 successfully because it uses different ROCm code paths.

### Warmup Disabled

The `--no-warmup` flag is intentionally NOT used in production compose — the containers
start cleanly without it with the correct `HSA_OVERRIDE_GFX_VERSION=11.0.0`.

---

## Sources

- Phase 7 design: `openspec/changes/phase-7-llamacpp-function-calling/design.md`
- GGUF setup: `docs/runbooks/gguf-model-setup.md`
- ADR-0011: `docs/decisions/adr/ADR-0011-llama-cpp-function-calling-stack.md`
