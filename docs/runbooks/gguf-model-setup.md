# Runbook: GGUF Model Provisioning

**Phase**: Phase 7 — llama.cpp function-calling stack
**Status**: Verified
**Last verified**: 2026-03-17
**Performed by**: ragnarokkrr

---

## Purpose

Download and manage GGUF model weights for the `compose/ai-tools/` llama.cpp stack. GGUF files live at `/srv/platform/models/gguf/` and are bind-mounted read-only into each llama.cpp container. This is separate from Ollama's managed storage (`/srv/platform/models/blobs/`).

---

## Prerequisites

- [ ] `/srv/platform/models/gguf/` directory exists (created in Phase 7 task 1.1)
- [ ] `pipx` installed: `sudo apt install pipx && pipx ensurepath`
- [ ] Sufficient disk space: ~19 GB per 32B model, ~40 GB for 70B model
- [ ] Hugging Face CLI installed: `pipx install 'huggingface_hub[cli]'` — installs as `hf`

---

## VRAM Budget

ROCm-accessible VRAM on this hardware is ~56 GB (carved from 128 GB unified system
memory). The full 96 GB iGPU allocation is not fully addressable by ROCm/HIP.
System RAM (32 GB) handles OS and Docker overhead only.

| Combination | Weights | + 16K ctx/ea | Feasibility |
|-------------|---------|-------------|-------------|
| 1× 32B model | ~19 GB | ~23 GB | Trivial |
| 2× 32B models | ~38 GB | ~46 GB | Comfortable |
| 1× 32B + Ollama 32B loaded | ~19 + ~30 GB | ~53 GB | Tight — unload Ollama first |
| 1× 32B + 1× 70B | ~62 GB | ~71 GB | **Over limit** — stop 32B first |
| 2× 32B + 1× 70B | ~81 GB | ~94 GB | **Over limit** |

For agentic coding (sequential tool calls), 16K context is sufficient.
When running the 70B model, stop all other llama.cpp containers and unload Ollama models first.

---

## Model Roster

| Filename | Repo | Size | Purpose |
|----------|------|------|---------|
| `Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf` | `bartowski/Qwen2.5-Coder-32B-Instruct-GGUF` | ~19 GB | Primary coding + tool-calling model |
| `DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf` | `bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF` | ~19 GB | Reasoning + tool-calling model |
| `Llama-3.3-70B-Instruct-Q4_K_M.gguf` | `bartowski/Llama-3.3-70B-Instruct-GGUF` | ~43 GB | General instruction + tool-calling (optional) |

---

## Procedure

### Step 1 — Install Hugging Face CLI

```bash
sudo apt install pipx
pipx ensurepath
pipx install 'huggingface_hub[cli]'
```

> **Note:** On Pop!_OS / Ubuntu 24.x the Python environment is externally managed. Use `pipx` — not `pip install --user`. The CLI installs as `hf` (not `huggingface-cli`).

**Verify:**
```bash
hf --version
# Expected: huggingface_hub version 1.x.x
```

---

### Step 2 — Create model directory

```bash
mkdir -p /srv/platform/models/gguf
```

**Verify:**
```bash
ls -la /srv/platform/models/
# Expected: gguf/ directory alongside blobs/ and manifests/
```

---

### Step 3 — Download Qwen2.5-Coder 32B

```bash
hf download bartowski/Qwen2.5-Coder-32B-Instruct-GGUF \
  --include "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf" \
  --local-dir /srv/platform/models/gguf/
```

**Verify:**
```bash
ls -lh /srv/platform/models/gguf/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf
# Expected: ~19 GB file
```

---

### Step 4 — Download DeepSeek-R1 32B

```bash
hf download bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF \
  --include "DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf" \
  --local-dir /srv/platform/models/gguf/
```

**Verify:**
```bash
ls -lh /srv/platform/models/gguf/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf
# Expected: ~19 GB file
```

---

### Step 5 — (Optional) Download Llama 3.3 70B

Only needed if the `llama-cpp-llama70b` container will be started. Requires ~43 GB free disk space.

```bash
hf download bartowski/Llama-3.3-70B-Instruct-GGUF \
  --include "Llama-3.3-70B-Instruct-Q4_K_M.gguf" \
  --local-dir /srv/platform/models/gguf/
```

**Verify:**
```bash
ls -lh /srv/platform/models/gguf/Llama-3.3-70B-Instruct-Q4_K_M.gguf
# Expected: ~43 GB file
```

---

### Step 6 — Verify all models

```bash
ls -lh /srv/platform/models/gguf/
# Expected output (with all three):
# 19G  DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf
# 19G  Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf
# 43G  Llama-3.3-70B-Instruct-Q4_K_M.gguf
```

---

## GPU Layer Tuning

Each llama.cpp service offloads all model layers to VRAM by default (`--n-gpu-layers 99`). With 96 GB dedicated VRAM, full offload is feasible for all combinations.

If you need to reduce VRAM usage (e.g., running all three models at large context), adjust `N_GPU_LAYERS_*` in `compose/ai-tools/.env`:

```bash
# Partial offload — some layers run on CPU
N_GPU_LAYERS_QWEN32B=40
N_GPU_LAYERS_DEEPSEEK32B=40
```

Lower values reduce VRAM at the cost of inference speed. Monitor with:

```bash
# Check VRAM usage
rocm-smi --showmeminfo vram
```

---

## Context Size Tuning

Default context size is 16384 tokens (`CTX_SIZE=16384` in `.env`), suitable for agentic tool-call sessions. Override globally in `.env` or per-service if needed.

KV cache memory per model (FP16):
- 32B model at 16K ctx: ~4 GB
- 32B model at 32K ctx: ~8 GB
- 70B model at 16K ctx: ~5 GB

To halve KV cache VRAM, add to the service command in `docker-compose.yml`:
```
--cache-type-k q8_0 --cache-type-v q8_0
```

---

## Removing Models

```bash
# Remove a specific model to free disk space
rm /srv/platform/models/gguf/Llama-3.3-70B-Instruct-Q4_K_M.gguf

# Verify disk freed
df -h /srv
```

Stop the corresponding container before removing its model file:
```bash
docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-llama70b
```

---

## Rollback

GGUF files are standalone — removing them has no effect on Ollama or other stacks. To fully remove:

```bash
docker compose -f compose/ai-tools/docker-compose.yml down
rm -rf /srv/platform/models/gguf/
```

---

## Sources

- bartowski GGUF releases: https://huggingface.co/bartowski
- llama.cpp server docs: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- ADR-0011: `docs/decisions/adr/ADR-0011-llamacpp-function-calling-backend.md`
