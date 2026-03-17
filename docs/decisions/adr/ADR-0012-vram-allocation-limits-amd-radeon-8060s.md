# ADR-0012: VRAM Allocation Limits on AMD Radeon 8060S (Hawk Point iGPU)

**Date**: 2026-03-17
**Status**: Accepted

Related: ADR-0011 (llama.cpp stack — assumes 96 GB VRAM; corrected here)

---

## Context

HAL-10k is a BOSGAME M5 AI Mini with an AMD RDNA 3.5 iGPU (AMD Radeon 8060S / 40 CU).
The system ships with 128 GB of unified memory configured as 32 GB system RAM + 96 GB
dedicated iGPU allocation in firmware.

ADR-0011 and the Phase 7 design assumed that the full 96 GB iGPU allocation was usable
as GPU VRAM for ROCm workloads. During Phase 7 deployment (2026-03-17), empirical testing
revealed that this assumption is incorrect in multiple ways that materially affect multi-model
scheduling.

This ADR records the full set of findings as a basis for future remediation work.

---

## Findings

### F1 — Actual ROCm-Accessible VRAM: ~56 GB, not 96 GB

ROCm/HIP reports and can allocate approximately **56,156 MiB (~54.8 GiB)** of device VRAM,
consistently observed across all llama.cpp container startups:

```
ggml_cuda_init: found 1 ROCm devices (Total VRAM: 56156 MiB):
  Device 0: AMD Radeon 8060S, gfx1100 (0x1100), VMM: no, Wave Size: 32, VRAM: 56156 MiB
```

The `rocm-smi` tool on the host reports a different value (16 GiB) when the GPU is idle /
in low-power state — this is not the usable allocation ceiling; it reflects the current
low-power framebuffer reservation.

**Root cause (hypothesis):** On Hawk Point iGPU systems, the full 96 GB iGPU allocation
in firmware is the theoretical ceiling, but the ROCm driver can only access a portion of
this as VRAM when the GPU is not in a unified memory mapping mode. The remaining ~40 GB
may require explicit XNACK (page fault) support or a future ROCm driver update to be
accessible as device memory. This has not been confirmed with AMD documentation.

### F2 — Ollama Reports Different VRAM Than llama.cpp

Ollama's internal model sizing uses a different accounting method. When loading
`qwen2.5-coder:32b`, Ollama reports a loaded model size of **30 GB** at **100% GPU**,
whereas llama.cpp loads the same Q4_K_M quantisation into **~18.5 GB** of ROCm VRAM
(with an additional ~4 GB for KV cache at 16K context).

This discrepancy has two implications:
1. Ollama's VRAM estimate is pessimistic relative to actual allocation — but the actual
   allocation is still large enough to cause contention when combined with llama.cpp.
2. VRAM budgeting cannot be done from Ollama's reported model sizes alone.

### F3 — VRAM Contention: Ollama Does Not Yield to Other Processes

Ollama holds loaded models in VRAM until an explicit unload (`keep_alive: 0`) or until
the keep-alive TTL expires (default: 5 minutes). It does not respond to ROCm memory
pressure from other processes. When a llama.cpp container starts and Ollama has a model
loaded:

- If combined allocation exceeds ~56 GB, the llama.cpp container fails with:
  `cudaMalloc failed: out of memory` / `unable to allocate ROCm0 buffer`
- Ollama continues holding its allocation unaware of the failure
- The llama.cpp container enters a crash-restart loop

**Empirical VRAM usage at the ~56 GB limit:**

| Configuration | VRAM estimate | Fits in 56 GB |
|---------------|---------------|---------------|
| 1× 32B llama.cpp (weights + KV@16K) | ~23 GB | Yes |
| 2× 32B llama.cpp | ~46 GB | Yes |
| 1× 70B llama.cpp (weights + KV@16K) | ~46 GB | Yes (solo only) |
| 2× 32B llama.cpp + Ollama 32B loaded | ~76 GB | **No** |
| 2× 32B llama.cpp + 1× 70B llama.cpp | ~89 GB | **No** |
| 1× 32B llama.cpp + Ollama 32B loaded | ~53 GB | Borderline (may fail) |

### F4 — HSA Override Differs Between Ollama and llama.cpp

Both Ollama and llama.cpp require `HSA_OVERRIDE_GFX_VERSION` to operate on this GPU
(the Radeon 8060S is not natively listed in ROCm's supported device table). However,
the two stacks require *different* override values:

| Stack | HSA_OVERRIDE_GFX_VERSION | Result |
|-------|--------------------------|--------|
| Ollama | `11.0.2` | Works correctly |
| llama.cpp | `11.0.2` | **Segfault (exit 139) in `sched_reserve`** |
| llama.cpp | `11.0.0` | Works correctly |

The crash with `11.0.2` in llama.cpp occurs after model weights are loaded but before
the server begins listening, specifically during `sched_reserve` — the phase where HIP
compute graphs are compiled and GPU memory is reserved for inference buffers. The
`11.0.0` override selects the gfx1100 (RX 7900-series) kernel set, which is
compute-compatible with gfx1102 and does not trigger the crash.

The exact mechanism is unknown. Both overrides map to RDNA 3 architectures (11.0.0 →
gfx1100, 11.0.2 → gfx1102). The difference may be in the specific HIP kernel variants
compiled into the llama.cpp ROCm image for these two targets. The llama.cpp image used
(`ghcr.io/ggml-org/llama.cpp:server-rocm`, build b8390,
`sha256:d52a425c5001fb619d9ef96701aa02f10c88cc2b2f6b8f6d397ebd169654581b`) may not
include compiled gfx1102 kernels for all operations.

**Observed consequence of the override difference:** The GPU is reported as `gfx1100`
inside llama.cpp containers (override effective) vs. `gfx1102` inside Ollama containers.
Both work, but represent different kernel selection paths.

### F5 — `--metrics` Flag Required for Prometheus Endpoint

llama.cpp does not expose `/metrics` by default. Without the `--metrics` flag, the
endpoint returns `HTTP 501 Not Implemented`:

```json
{"error": {"code": 501, "message": "This server does not support metrics endpoint. Start it with `--metrics`"}}
```

This is a configuration detail, not a hardware limitation, but it was an undocumented
gap in the Phase 7 design (ADR-0011 assumed `/metrics` was always available).

### F6 — LiteLLM `openai/` Prefix Requires Dummy `api_key`

LiteLLM v1.81.12 with `model: "openai/<model>"` and a custom `api_base` requires an
`api_key` to be set in `litellm_params`, even when the backend (Ollama, llama.cpp)
has no authentication. Without it, every request fails:

```
AuthenticationError: OpenAIException - The api_key client option must be set
```

Resolved by setting `api_key: "ollama"` / `api_key: "llama"` (dummy values) in
`compose/proxy/litellm-config.yaml`. This was not documented in LiteLLM's migration
notes between versions.

---

## Current Mitigations

All mitigations are in place as of Phase 7 completion (2026-03-17):

1. **`HSA_OVERRIDE_GFX_VERSION=11.0.0`** in `compose/ai-tools/docker-compose.yml`
2. **Operator-controlled startup** — `compose/ai-tools/` is not auto-started; operator
   selects which models to run based on workload and manually unloads Ollama models
   when starting llama.cpp containers
3. **`--metrics` flag** added to all three llama.cpp service commands
4. **Dummy `api_key`** added to all `openai/` prefix entries in `litellm-config.yaml`
5. **VRAM budget documentation** in `docs/runbooks/ai-stack.md` and
   `docs/runbooks/gguf-model-setup.md` with the corrected 56 GB limit

---

## Potential Future Fixes

### Fix A — Resolve Actual ROCm VRAM Ceiling

**Investigation needed:** Determine whether the ~56 GB VRAM ceiling is a firmware
configuration limit, a ROCm driver limitation, or requires XNACK/unified memory
addressing. Possible approaches:

- Check firmware BIOS settings for iGPU memory allocation options (some boards allow
  tuning beyond the default split)
- Test with newer ROCm versions that may better support Hawk Point unified memory
- Investigate `AMDGPU_FORCE_VRAM_ALLOC_ONLY` and related environment variables
- Review AMD's Strix Point / Hawk Point ROCm support notes when published

### Fix B — Coordinated VRAM Management

The current manual coordination (stop containers, unload Ollama, start other containers)
is error-prone. Potential solutions:

- **Ollama keep-alive tuning**: Set `OLLAMA_KEEP_ALIVE=0` in `compose/ai/` to make
  Ollama release VRAM immediately after each request, rather than holding for 5 minutes.
  This would allow llama.cpp containers to start without manual Ollama unloads.
- **Model groups / profiles**: Define mutually exclusive Docker Compose profiles for
  "chat mode" (Ollama only) vs. "agentic mode" (llama.cpp only) to prevent accidental
  simultaneous allocation.
- **VRAM health check**: Pre-flight script that reads `rocm-smi` VRAM usage before
  starting any llama.cpp container and fails fast with a clear error if headroom is
  insufficient.

### Fix C — Unified Serving Backend

If a future inference server supports both chat and tool calling without the
Ollama/llama.cpp split, VRAM contention between the two would be eliminated. Candidates
to evaluate when hardware upgrades:

- **vLLM** (deferred per ADR-0011 pending discrete GPU)
- **llama.cpp as sole backend** (replacing Ollama entirely — evaluated in ADR-0011,
  rejected due to Ollama's model management UX; worth revisiting if VRAM constraints
  become unworkable)
- **Ollama with tool calling** — if Ollama adds native function calling support for
  these models, the llama.cpp stack becomes redundant

### Fix D — HSA Override Root Cause

File an upstream issue with the llama.cpp project documenting the `11.0.2` segfault on
AMD Radeon 8060S (gfx1102) with build b8390. The fix may already be present in a newer
build, or the issue may need a targeted HIP kernel compilation fix for gfx1102.

Reference data for the upstream report:
- GPU: AMD Radeon 8060S, `gfx1102 (0x1102)`, Wave Size 32, 56156 MiB VRAM
- Image: `ghcr.io/ggml-org/llama.cpp:server-rocm` build b8390 (`sha256:d52a425c...`)
- Crash point: `sched_reserve` phase, after `load_tensors: offloaded N/N layers to GPU`
- Exit code: 139 (SIGSEGV)
- Workaround: `HSA_OVERRIDE_GFX_VERSION=11.0.0`

---

## Decision

Accept the current mitigations as production state for Phase 7. Track Fix A and Fix B
as backlog items. Re-evaluate Fix C when hardware upgrades to a discrete GPU.

No changes to running configuration are required beyond what was applied during
Phase 7 deployment.

---

## References

- Phase 7 design: `openspec/changes/phase-7-llamacpp-function-calling/design.md`
- GGUF model setup runbook: `docs/runbooks/gguf-model-setup.md`
- AI stack runbook: `docs/runbooks/ai-stack.md`
- ADR-0011: `docs/decisions/adr/ADR-0011-llama-cpp-function-calling-stack.md`
- llama.cpp server docs: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
