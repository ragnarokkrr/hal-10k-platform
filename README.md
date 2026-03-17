# hal-10k-platform

<img src="docs/assets/HAL-10k.png" alt="HAL-10k Self-Hosted AI Server" width="600"/>

Infrastructure-as-code and runbooks for the **HAL-10k Self-Hosted AI Server** running on
a BOSGAME M5 AI Mini (AMD Ryzen AI Max+ 395, 128 GB unified RAM/VRAM).

> **HAL-10k! Self-Hosted AI Server**
>
> HAL-10k - HAL-9000 went Super Saiyan 4. Power level: 10,000!

> **What people say about HAL-10k!**
>
> *"That low-class clown... he is a genius!" — Vegeta*
>
> *"AI Singularity, in the palm of your hand!" — Doc Oc*
>
> *"A shadowy flight into the dangerous world of a man who does not exist!"* — K.I.T.T.

## What HAL-10k Does

A fully self-hosted AI coding and inference platform — no cloud, no subscriptions:

- **Runs 32B and 70B LLMs locally** — Qwen2.5-Coder 32B, DeepSeek-R1 32B, Llama 3.3 70B, GPU-accelerated via ROCm on AMD RDNA 3.5
- **Full agentic coding** — OpenCode and Claude Code connect to local models via LiteLLM and drive file edits, bash execution, and codebase navigation against real tools, not stubs
- **Function calling on local hardware** — llama.cpp (`compose/ai-tools/`) uses GGUF-embedded Jinja2 chat templates to implement OpenAI-compatible tool calling; works where Ollama cannot
- **OpenAI-compatible API gateway** — LiteLLM (`compose/proxy/`) routes chat and tool-calling requests to Ollama or llama.cpp backends; any OpenAI SDK client works out of the box
- **Full observability** — Prometheus + Loki + Grafana stack with per-container metrics, GPU VRAM monitoring, and aggregated logs for all services
- **Spec-driven infrastructure** — every change produces proposal → design → task artifacts before any file is modified; all committed alongside code

---

## Hardware

<img src="docs/assets/BOSGAME_M5_AI.png" alt="BOSGAME M5 AI Mini" width="600"/>

| Component | Spec |
|-----------|------|
| Platform | BOSGAME M5 AI Mini |
| CPU | AMD Ryzen AI Max+ 395 (16C/32T, Zen 5) |
| RAM/VRAM | 128 GB LPDDR5X unified (ROCm-accessible: ~56 GB) |
| iGPU | AMD RDNA 3.5, 40 Compute Units |
| Storage | 2 TB NVMe SSD (1.35 TB dedicated to `/srv/platform`) |
| OS | Pop!_OS 24.x LTS |

See [docs/hardware/bosgame-m5-ai-specs.md](docs/hardware/bosgame-m5-ai-specs.md) for full specs.

---

## Service Inventory

| Service | URL | Status |
|---------|-----|--------|
| Traefik | http://hal-10k:8080 | ✅ Running |
| Ollama | internal (ai_internal) | ✅ Running |
| Open WebUI | https://openwebui.hal.local | ✅ Running |
| LiteLLM | https://litellm.hal.local | ✅ Running |
| llama.cpp (ai-tools) | internal (ai_internal) | ⚡ On-demand |
| Prometheus + Loki + Grafana | https://grafana.hal.local | ✅ Running |
| Portainer | https://hal-10k:9443 | ✅ Running |
| ChromaDB | http://hal-10k:8000 | 🔜 Planned |
| n8n | http://hal-10k:5678 | 🔜 Planned |
| Gitea | http://hal-10k:3001 | 🔜 Planned |

---

## Agentic AI Coding — `compose/ai-tools/` + OpenCode

`compose/ai-tools/` runs [llama.cpp](https://github.com/ggml-org/llama.cpp) as a
dedicated function-calling backend. Unlike Ollama, llama.cpp implements tool calling at
the tokenisation layer via the GGUF-embedded Jinja2 chat template (`--jinja`), enabling
agentic clients to use local models for file edits, bash execution, and codebase
navigation.

**This stack is operator-started on demand** — not auto-started at boot.
GGUF models must be downloaded first: [gguf-model-setup.md](docs/runbooks/gguf-model-setup.md).

### Start a tool-calling session

```bash
# 1. Start the llama.cpp backend (on HAL-10k)
docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b

# 2. Launch OpenCode (local or remote laptop)
export LITELLM_API_KEY=<key from /srv/platform/secrets/ai.yaml>
export NODE_EXTRA_CA_CERTS=~/hal-local.crt   # remote laptop only
opencode --model hal/qwen2.5-coder:32b-tools

# 3. Stop backend when done (frees ~23 GB VRAM)
docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-qwen32b
```

### Model aliases

| Alias | Backend | Tool calling | VRAM |
|-------|---------|-------------|------|
| `qwen2.5-coder:32b` | Ollama | No | ~30 GB |
| `qwen2.5-coder:32b-tools` | llama.cpp | **Yes** | ~23 GB |
| `deepseek-r1:32b` | Ollama | No | ~30 GB |
| `deepseek-r1:32b-tools` | llama.cpp | **Yes** | ~23 GB |
| `llama3.3:70b` | Ollama | No | ~48 GB |
| `llama3.3:70b-tools` | llama.cpp | **Yes** | ~48 GB |

> ROCm-accessible VRAM is ~56 GB. Two 32B llama.cpp containers (~46 GB) is the practical
> multi-model limit. The 70B model requires all others stopped first.

Full client setup (OpenCode, Claude Code, Cline): [docs/runbooks/ai-client-setup.md](docs/runbooks/ai-client-setup.md)

---

## Two-Layer Architecture

HAL-10k runs two isolated layers:

- **Platform Layer** (`/srv/platform/`) — stable production services under Docker Compose
- **Experimentation Layer** (`/srv/experiments/`) — disposable GPU-accelerated ML environments under Distrobox (rootless Podman)

Experiments graduate to the Platform Layer when they reach daily use, stable config, reboot persistence, and a runbook.

See [docs/architecture/platform-overview.md](docs/architecture/platform-overview.md) for the full platform architecture and [docs/architecture/experimentation-layer.md](docs/architecture/experimentation-layer.md) for the lifecycle diagram and graduation criteria.

---

## Quick Start

```bash
# 1. Clone this repo on HAL-10k
git clone https://github.com/ragnarokkrr/hal-10k-platform.git /srv/platform/repos/hal-10k-platform
cd /srv/platform/repos/hal-10k-platform

# 2. Decrypt secrets
./scripts/secrets-decrypt.sh

# 3. Deploy a stack
cd compose/core && docker compose up -d
```

See [WORKFLOW.md](WORKFLOW.md) for the full development and deployment workflow.
See [ROADMAP.md](ROADMAP.md) for planned phases.

---

## Spec-Driven Development

Infrastructure changes follow a spec-driven workflow powered by
**[OpenSpec](https://github.com/Fission-AI/OpenSpec)** (by Fission AI).
Every change produces reviewable, diffable, committable artifacts before any repo file is modified:

```
/opsx:propose   → define the change (proposal, design, tasks)
review spec     → sanity-check before Claude touches anything
/opsx:apply     → implement repo changes
manual validate → run bootstrap / compose checks
/opsx:archive   → close the change
```

Change artifacts live under `openspec/changes/` and are committed alongside code.
See [ADR-0003](docs/decisions/adr/ADR-0003-spec-driven-development-openspec.md) for rationale.

---

## Reference Notes (HAL-10k Personal Assistant)

```
     . · · · · .
    · ░░░░░░░░░ ·
    · ░░( ◉ )░░ ·
    · ░░░░░░░░░ ·
     ' · · · · '
     I'm sorry, Dave.
     Actually I can do that.
```

This section is an infrastructure-facing distillation of knowledge from the **HAL-10k Personal Assistant** — an AI-powered personal knowledge base built on [Obsidian](https://obsidian.md) and [Claude Code](https://claude.ai/claude-code), combining a structured vault with Claude Code commands, skills, and multi-agent pipelines.

The notes below are the original sources from which the runbooks, ADRs, and compose stacks in this repo were derived.

Tags: `homelab/hal-10k` · `homelab/bosgame-m5-ai`

| Note | Topic |
|------|-------|
| HAL-10k - Self Hosted AI Server | Project overview |
| hal-10k-software-inventory-installed-stack | Installed software inventory |
| create-srv-platform-partition-gparted-live | /srv/platform partitioning procedure |
| service-platform-partition-strategy | Platform partition directory strategy |
| install-rocm-on-popos | ROCm 7.2 installation |
| timeshift-configurations | Timeshift backup config |
| docker-portainer-dockge-how-to | Docker + Portainer + Dockge setup |
| bosgame-m5-initial-software-popos-xfdp-xfce-remmina | OS baseline setup |
| self-host-llm-on-bosgame-m5-ai-mini | LLM hosting guide and BIOS tuning |
| multi-model-specialization-bosgame-m5 | Multi-model concurrency strategy |
| hal-10k-pa-embedded-mode | PA embedded mode strategy |
