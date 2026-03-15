# ROADMAP.md — hal-10k-platform Delivery Phases

This roadmap tracks the phased implementation of the HAL-10k platform infrastructure.
Stack generation will be progressively automated using **Spec-Kit** or **Open-Spec ADD**.

---

## Phase 0 — Bootstrap Documentation (Manual, Completed)

Document all steps already performed manually on HAL-10k as runbooks.
No automation required; these are point-in-time reference procedures.

- [x] `bootstrap/00-hardware-bios/` — BIOS tuning runbook (UMA, EXPO, power limits)
- [x] `bootstrap/01-os-install/` — Pop!_OS 24.x + XFCE + XRDP + Remmina + VSCode
- [x] `bootstrap/02-partitioning/` — GParted Live partitioning + /srv/platform layout + new partitioning to support /srv/experiments
- [x] `bootstrap/03-rocm/` — ROCm 7.2 installation and verification
- [x] `bootstrap/04-timeshift/` — Timeshift RSYNC config and retention policy
- [x] `bootstrap/05-docker/` — Docker CE + Portainer + Dockge + data-root relocation
- [x] `bootstrap/06-secrets-sops-age/` — SOPS + age installation and key setup (**manual runbook**)

---

## Phase 1 — Project Scaffold & Secrets Foundation

Seed the repository structure and establish the secrets management baseline.

- [x] Initialize git repository and push to GitHub (`hal-10k-platform`)
- [x] Add `.gitignore`, `.sops.yaml`, `secrets/.gitkeep`
- [x] Author `bootstrap/06-secrets-sops-age/runbook.md`
- [x] Create `scripts/secrets-decrypt.sh` and `scripts/secrets-encrypt.sh`
- [x] Add `docs/decisions/adr/ADR-0001-secrets-management-sops-age.md`
- [x] Add `docs/architecture/platform-overview.md`

---

## Phase 2 — Spec-Kit / Open-Spec ADD Automation

Automate Compose stack generation from declarative service specifications.

- [x] Evaluate Spec-Kit vs Open-Spec ADD for stack generation
- [x] Author `specs/` directory with ADD specs for each service
- [x] `docs/decisions/adr/ADR-0003-spec-driven-development-openspec.md`
- [x] Integrate spec generation into the WORKFLOW (generate → review → deploy)
- [x] Retrofit existing stacks with ADD specs (retroactive documentation)

---

## Phase 3 — Core Networking (Traefik)

Deploy the reverse proxy as the entry point for all services.

- [x] `compose/core/docker-compose.yml` — Traefik v3 + nginx socket proxy (ADR-0005)
- [x] `compose/core/.env.example`
- [x] `secrets/core.enc.yaml` — TLS / dashboard credentials (SOPS + age)
- [x] `docs/runbooks/core-traefik.md`
- [x] `docs/decisions/adr/ADR-0004-reverse-proxy-traefik.md`
- [x] `docs/decisions/adr/ADR-0005-docker-socket-proxy.md`
- [x] `docs/ports.md` — authoritative port registry
- [x] Verify: Traefik healthy, dashboard auth working, HTTP→HTTPS redirect confirmed

---

## Phase 4 — AI Inference Stack

Deploy LLM serving and the web UI.

- [x] `compose/ai/docker-compose.yml` — Ollama + LiteLLM + Open WebUI
- [x] GPU device reservation (`driver: amdgpu`, ROCm environment variables)
- [x] `secrets/ai.enc.yaml` — LiteLLM master key, API keys
- [x] `docs/runbooks/ai-stack.md`
- [x] `docs/runbooks/model-management.md` — pull, list, delete Ollama models
- [x] `docs/decisions/adr/ADR-0006-llm-serving-ollama-litellm.md`
- [x] Initial model roster: Qwen2.5-Coder-32B, DeepSeek-R1-32B, Llama-3.3-70B
- [x] `docs/runbooks/ai-client-setup.md` — configure Claude Code and Cline to use the initial model roster via LiteLLM proxy

---

## Phase 5 — Observability ✓

Monitoring and log aggregation for all platform services.
Deployed early so every subsequent phase can wire up metrics and dashboards incrementally.

- [x] `compose/observability/docker-compose.yml` — Prometheus + Grafana + Loki
- [x] Node Exporter + cAdvisor for host and container metrics
- [x] `secrets/observability.enc.yaml` — Grafana admin credentials
- [x] `docs/runbooks/observability.md`
- [x] `docs/decisions/adr/ADR-0007-observability-prometheus-loki-grafana.md`
- [x] Grafana dashboards — foundation set:
  - [x] Host: CPU, RAM, disk I/O, network (`/srv/platform` usage)
  - [x] GPU: ROCm utilization, VRAM, temperature (stub — awaiting ROCm exporter)
  - [x] Containers: per-stack resource usage via cAdvisor (limited — see Note)
  - [x] Traefik: request rate, error rate, latency (Prometheus metrics entrypoint)
- [x] Grafana dashboards — AI stack (provisioned after Phase 4):
  - [x] Ollama: inference request rate, latency (stub — awaiting Ollama metrics endpoint)
  - [x] LiteLLM: token throughput, per-model routing, error rate (stub — awaiting LiteLLM metrics)
- [x] Docker Loki log driver configured as default; all container logs aggregated in Loki
- [x] `docs/testcases/observability-stack-test.md`

**Note**: cAdvisor per-container labelling not functional with Docker 29+ containerd snapshotter (`io.containerd.snapshotter.v1`). Host-level metrics fully operational. Fix requires switching Docker storage driver to `overlay2` and re-pulling images (~5 GB) — scheduled for a future maintenance window.

---

## Phase 6 — LiteLLM Gateway Extraction (Spec 1)

Extract LiteLLM from `compose/ai/` into a standalone `compose/proxy/` stack, making it
the platform-level API gateway independent of any inference backend. Enables clean
multi-backend routing and isolates gateway restarts from inference containers.

See: `docs/decisions/adr/ADR-0011-llama-cpp-function-calling-stack.md`

- [x] Create `compose/proxy/docker-compose.yml` — LiteLLM service with Traefik labels
- [x] Create `compose/proxy/litellm-config.yaml` — migrated from `compose/ai/`
- [x] Create `compose/proxy/.env.example` — LiteLLM image tag, key references
- [x] Create `compose/proxy/.env` — production env (gitignored)
- [x] Ensure `ai_internal` network is named explicitly (`name: ai_internal` in `compose/ai/`; `compose/proxy/` references as external)
- [x] Remove LiteLLM service from `compose/ai/docker-compose.yml`
- [x] Remove `depends_on: litellm` from Open WebUI in `compose/ai/docker-compose.yml`
- [x] Update `docs/runbooks/ai-stack.md` — reflect new stack topology and startup order
- [x] Update `docs/ports.md` — reassign LiteLLM to `compose/proxy/`
- [x] Verify: `curl -sf https://litellm.hal.local/models` — all existing models still listed
- [x] Verify: Open WebUI chat still functional end-to-end

---

## Phase 7 — llama.cpp Function-Calling Stack (Spec 2)

Add a parallel inference stack `compose/ai-tools/` running llama.cpp for tool/function
calling workloads. Enables agentic AI clients (Claude Code, OpenCode) to use local
models for file edits, bash execution, and codebase navigation.

See: `docs/decisions/adr/ADR-0011-llama-cpp-function-calling-stack.md`

- [ ] Create `/srv/platform/models/gguf/` directory on HAL-10k
- [ ] `docs/runbooks/gguf-model-setup.md` — GGUF download, verification, GPU layer tuning
- [ ] Download initial GGUF models (bartowski quantisations, Q4_K_M):
  - [ ] `qwen2.5-coder-32b-instruct-q4_k_m.gguf` (~19 GB)
  - [ ] `llama3.3-70b-instruct-q4_k_m.gguf` (~43 GB)
- [ ] Create `compose/ai-tools/docker-compose.yml` — llama.cpp server (ROCm image, `--jinja` flag)
- [ ] Create `compose/ai-tools/.env.example` — image tag, model path
- [ ] Add `-tools` model aliases to `compose/proxy/litellm-config.yaml`:
  - [ ] `qwen2.5-coder:32b-tools` → llama.cpp backend
  - [ ] `llama3.3:70b-tools` → llama.cpp backend
- [ ] Update `docs/runbooks/ai-client-setup.md`:
  - [ ] Document `-tools` model aliases for OpenCode and Claude Code
  - [ ] Remove tool-use limitation notes resolved by this phase
- [ ] Verify function calling end-to-end: POST `/v1/chat/completions` with `tools` array → `tool_calls` in response
- [ ] Verify OpenCode agentic session creates files and runs bash commands via `qwen2.5-coder:32b-tools`

---

## Phase 8 — Experimentation Layer (Distrobox)

Establish the Experimentation Layer as a formal, documented tier of the HAL-10k lab
for disposable, GPU-accelerated ML experiments. Runs on Distrobox (rootless Podman) at
`/srv/experiments/` — separate from the Docker Platform Layer.

- [ ] Install Podman + Distrobox on HAL-10k (**future**)
- [ ] Create `/srv/experiments/` directory convention (**future**)
- [ ] Author `/srv/experiments/create.sh` — version-controlled container creation commands (**future**)
- [ ] Create standard containers: `ml-lab`, `llama-build`, `agents-dev`, `ragna-ml` (**future**)
- [ ] Bootstrap `ragna-ml` JupyterLab container (**future**)
- [ ] Validate iGPU passthrough inside a container (`clinfo`, `vulkaninfo`) (**future**)
- [ ] Test llama.cpp Vulkan build inside `llama-build` (**future**)
- [ ] Evaluate LM Studio API vs Ollama for experiment-layer model serving (**future**)
- [ ] `docs/runbooks/experimentation-layer-setup.md` — full implementation steps (**future**)
- [ ] Grafana: GPU utilization dashboard scoped to experiment workloads (**future**)

---

## Phase 8.5 — Experiment Lifecycle Tracking (Backlog.md)

Track Distrobox experiment lifecycle inside the provisioning repo using Backlog.md.

- [ ] Install Backlog.md CLI: `npm install -g @mrleskbacklog/backlog.md` (verify current package name) (**future**)
- [ ] Bootstrap the Backlog.md project non-interactively (preserves pre-seeded tasks and IDs):
      `cd experiments && backlog init "HAL-10k Experiments" --defaults --task-prefix exp --integration-mode none` (**future**)
- [ ] Create `experiments/` directory in the repo root (**done** — seeded below)
- [ ] Seed `experiments/backlog/tasks/` — initial task files for all 5 standard containers in `To Do` / `idea` state:
      `ml-lab`, `llama-build`, `agents-dev`, `ragna-ml`, `torch-nightly` (**done**)
- [ ] Define label taxonomy: `idea` | `raw` | `validated` | `graduation-candidate` | `graduating` | `promoted` (**done**)
- [ ] Add graduation checklist template to `experiments/README.md` (**done**)
- [ ] Update `WORKFLOW.md` — add "Experiment Tracking" section documenting the
      Backlog.md → OpenSpec graduation trigger (**done**)
- [ ] Add `docs/decisions/adr/ADR-0010-experiment-lifecycle-tracking-backlog-md.md` (**done**)

---

## Phase 9 — Data & Vector Store

Persistent storage layer for embeddings and RAG pipelines.

- [ ] `compose/data/docker-compose.yml` — ChromaDB
- [ ] `secrets/data.enc.yaml`
- [ ] `docs/runbooks/data-chromadb.md`
- [ ] `docs/decisions/adr/ADR-vector-store-chromadb.md`
- [ ] Verify: Open WebUI RAG pipeline connected to ChromaDB
- [ ] Grafana: add ChromaDB collection count and query latency dashboard

---

## Phase 10 — Workflow Automation (n8n)

Orchestration layer for AI pipelines and integrations.

- [ ] `compose/workflows/docker-compose.yml` — n8n
- [ ] `secrets/workflows.enc.yaml`
- [ ] `docs/runbooks/workflows-n8n.md`
- [ ] Initial workflow: HAL-10k PA → local models via LiteLLM → ChromaDB
- [ ] Grafana: add n8n workflow execution count and error rate dashboard

---

## Phase 11 — Implementing Gitea (Self-Hosted Git)

Replace GitHub dependency with an on-prem git server for full self-sufficiency.

- [ ] `compose/gitea/docker-compose.yml` — Gitea + PostgreSQL
- [ ] `secrets/gitea.enc.yaml`
- [ ] `docs/runbooks/gitea-setup.md`
- [ ] `docs/runbooks/migrate-repos-to-gitea.md` — mirror `hal-10k-platform` from GitHub
- [ ] `docs/decisions/adr/ADR-self-hosted-git-gitea.md`
- [ ] Configure Gitea Actions runner (CI for this repo)
- [ ] Update `WORKFLOW.md` to reflect Gitea as primary remote
- [ ] Grafana: add Gitea repository activity and PostgreSQL metrics dashboard
- [ ] Loki: wire Gitea + Actions runner logs into log aggregation

---

## Backlog / Future

- Automated backup rotation scripts (`scripts/backup-*.sh`)
- Secret rotation runbook
- GGUF deduplication: script to symlink blobs from Ollama's content-addressed store into `/srv/platform/models/gguf/` (eliminates duplicate disk usage between Phase 7 and Ollama)
- vLLM evaluation ADR — revisit when hardware upgrades to discrete AMD GPU (RX 7900 XTX or MI-series)
- Disaster recovery runbook (full restore from Timeshift + Compose re-deploy)
