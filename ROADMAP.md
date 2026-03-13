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

- [ ] `compose/ai/docker-compose.yml` — Ollama + LiteLLM + Open WebUI
- [ ] GPU device reservation (`driver: amdgpu`, ROCm environment variables)
- [ ] `secrets/ai.enc.yaml` — LiteLLM master key, API keys
- [ ] `docs/runbooks/ai-stack.md`
- [ ] `docs/runbooks/model-management.md` — pull, list, delete Ollama models
- [ ] `docs/decisions/adr/ADR-0003-llm-serving-ollama-litellm.md`
- [ ] Initial model roster: Qwen2.5-Coder-32B, DeepSeek-Coder-33B, Llama-3.3-70B
- [ ] `docs/runbooks/ai-client-setup.md` — configure Claude Code and Cline to use the initial model roster via LiteLLM proxy

---

## Phase 5 — Observability

Monitoring and log aggregation for all platform services.
Deployed early so every subsequent phase can wire up metrics and dashboards incrementally.

- [ ] `compose/observability/docker-compose.yml` — Prometheus + Grafana + Loki
- [ ] Node Exporter + cAdvisor for host and container metrics
- [ ] `secrets/observability.enc.yaml` — Grafana admin credentials
- [ ] `docs/runbooks/observability.md`
- [ ] `docs/decisions/adr/ADR-observability-stack.md`
- [ ] Grafana dashboards — foundation set:
  - [ ] Host: CPU, RAM, disk I/O, network (`/srv/platform` usage alert)
  - [ ] GPU: ROCm utilization, VRAM, temperature (alert on thermal limit)
  - [ ] Containers: per-stack resource usage via cAdvisor
  - [ ] Traefik: request rate, error rate, latency (via Traefik access log → Loki)
- [ ] Grafana dashboards — AI stack (provisioned after Phase 4):
  - [ ] Ollama: active model, inference request rate, latency
  - [ ] LiteLLM: token throughput, per-model routing, error rate
  - [ ] Open WebUI: active sessions

---

## Phase 6 — Data & Vector Store

Persistent storage layer for embeddings and RAG pipelines.

- [ ] `compose/data/docker-compose.yml` — ChromaDB
- [ ] `secrets/data.enc.yaml`
- [ ] `docs/runbooks/data-chromadb.md`
- [ ] `docs/decisions/adr/ADR-vector-store-chromadb.md`
- [ ] Verify: Open WebUI RAG pipeline connected to ChromaDB
- [ ] Grafana: add ChromaDB collection count and query latency dashboard

---

## Phase 7 — Workflow Automation (n8n)

Orchestration layer for AI pipelines and integrations.

- [ ] `compose/workflows/docker-compose.yml` — n8n
- [ ] `secrets/workflows.enc.yaml`
- [ ] `docs/runbooks/workflows-n8n.md`
- [ ] Initial workflow: HAL-10k PA → Ollama → ChromaDB
- [ ] Grafana: add n8n workflow execution count and error rate dashboard

---

## Phase 8 — Implementing Gitea (Self-Hosted Git)

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

## Phase 9 — Experimentation Layer (Distrobox)

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

## Backlog / Future

- Automated backup rotation scripts (`scripts/backup-*.sh`)
- Secret rotation runbook
- HAL-10k PA integration — Claude Code pointing to local Ollama via LiteLLM proxy
- Multi-model routing strategy implementation (Qwen2.5 / DeepSeek / Llama routing)
- Disaster recovery runbook (full restore from Timeshift + Compose re-deploy)
