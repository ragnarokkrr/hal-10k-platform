# ROADMAP.md — hal-10k-platform Delivery Phases

This roadmap tracks the phased implementation of the HAL-10k platform infrastructure.
Stack generation will be progressively automated using **Spec-Kit** or **Open-Spec ADD**.

---

## Phase 0 — Bootstrap Documentation (Manual, Completed)

Document all steps already performed manually on HAL-10k as runbooks.
No automation required; these are point-in-time reference procedures.

- [x] `bootstrap/00-hardware-bios/` — BIOS tuning runbook (UMA, EXPO, power limits)
- [x] `bootstrap/01-os-install/` — Pop!_OS 24.x + XFCE + XRDP + Remmina + VSCode
- [x] `bootstrap/02-partitioning/` — GParted Live partitioning + /srv/platform layout
- [x] `bootstrap/03-rocm/` — ROCm 7.2 installation and verification
- [x] `bootstrap/04-timeshift/` — Timeshift RSYNC config and retention policy
- [x] `bootstrap/05-docker/` — Docker CE + Portainer + Dockge + data-root relocation
- [ ] `bootstrap/06-secrets-sops-age/` — SOPS + age installation and key setup (**manual runbook**)

---

## Phase 1 — Project Scaffold & Secrets Foundation

Seed the repository structure and establish the secrets management baseline.

- [ ] Initialize git repository and push to GitHub (`hal-10k-platform`)
- [ ] Add `.gitignore`, `.sops.yaml`, `secrets/.gitkeep`
- [ ] Author `bootstrap/06-secrets-sops-age/runbook.md`
- [ ] Create `scripts/secrets-decrypt.sh` and `scripts/secrets-encrypt.sh`
- [ ] Add `docs/decisions/adr/ADR-0001-secrets-management-sops-age.md`
- [ ] Add `docs/architecture/platform-overview.md`

---

## Phase 2 — Core Networking (Traefik)

Deploy the reverse proxy as the entry point for all services.

- [ ] `compose/core/docker-compose.yml` — Traefik v3
- [ ] `compose/core/.env.example`
- [ ] `secrets/core.enc.yaml` — TLS / dashboard credentials
- [ ] `docs/runbooks/core-traefik.md`
- [ ] `docs/decisions/adr/ADR-0002-reverse-proxy-traefik.md`
- [ ] Verify: all services accessible via Traefik labels

---

## Phase 3 — AI Inference Stack

Deploy LLM serving and the web UI.

- [ ] `compose/ai/docker-compose.yml` — Ollama + LiteLLM + Open WebUI
- [ ] GPU device reservation (`driver: amdgpu`, ROCm environment variables)
- [ ] `secrets/ai.enc.yaml` — LiteLLM master key, API keys
- [ ] `docs/runbooks/ai-stack.md`
- [ ] `docs/runbooks/model-management.md` — pull, list, delete Ollama models
- [ ] `docs/decisions/adr/ADR-0003-llm-serving-ollama-litellm.md`
- [ ] Initial model roster: Qwen2.5-Coder-32B, DeepSeek-Coder-33B, Llama-3.3-70B

---

## Phase 4 — Data & Vector Store

Persistent storage layer for embeddings and RAG pipelines.

- [ ] `compose/data/docker-compose.yml` — ChromaDB
- [ ] `secrets/data.enc.yaml`
- [ ] `docs/runbooks/data-chromadb.md`
- [ ] `docs/decisions/adr/ADR-0004-vector-store-chromadb.md`
- [ ] Verify: Open WebUI RAG pipeline connected to ChromaDB

---

## Phase 5 — Workflow Automation (n8n)

Orchestration layer for AI pipelines and integrations.

- [ ] `compose/workflows/docker-compose.yml` — n8n
- [ ] `secrets/workflows.enc.yaml`
- [ ] `docs/runbooks/workflows-n8n.md`
- [ ] Initial workflow: HAL-10k PA → Ollama → ChromaDB

---

## Phase 6 — Implementing Gitea (Self-Hosted Git)

Replace GitHub dependency with an on-prem git server for full self-sufficiency.

- [ ] `compose/gitea/docker-compose.yml` — Gitea + PostgreSQL
- [ ] `secrets/gitea.enc.yaml`
- [ ] `docs/runbooks/gitea-setup.md`
- [ ] `docs/runbooks/migrate-repos-to-gitea.md` — mirror `hal-10k-platform` from GitHub
- [ ] `docs/decisions/adr/ADR-0005-self-hosted-git-gitea.md`
- [ ] Configure Gitea Actions runner (CI for this repo)
- [ ] Update `WORKFLOW.md` to reflect Gitea as primary remote

---

## Phase 7 — Observability

Monitoring and log aggregation for all services.

- [ ] `compose/observability/docker-compose.yml` — Prometheus + Grafana + Loki
- [ ] Node Exporter + cAdvisor for host and container metrics
- [ ] `docs/runbooks/observability.md`
- [ ] Grafana dashboards: GPU utilization (ROCm), container resources, model latency
- [ ] Alerting: disk space on `/srv/platform`, GPU temperature

---

## Phase 8 — Spec-Kit / Open-Spec ADD Automation

Automate Compose stack generation from declarative service specifications.

- [ ] Evaluate Spec-Kit vs Open-Spec ADD for stack generation
- [ ] Author `specs/` directory with ADD specs for each service
- [ ] `docs/decisions/adr/ADR-0006-compose-generation-spec-kit.md`
- [ ] Integrate spec generation into the WORKFLOW (generate → review → deploy)
- [ ] Retrofit existing stacks with ADD specs (retroactive documentation)

---

## Backlog / Future

- Automated backup rotation scripts (`scripts/backup-*.sh`)
- Secret rotation runbook
- HAL-10k PA integration — Claude Code pointing to local Ollama via LiteLLM proxy
- Multi-model routing strategy implementation (Qwen2.5 / DeepSeek / Llama routing)
- Disaster recovery runbook (full restore from Timeshift + Compose re-deploy)
