# Experimentation Layer Architecture

## HAL-10k Self-Hosted AI Server

---

## Overview

The HAL-10k platform operates as two distinct layers: a stable **Platform Layer** running
production services under Docker Compose at `/srv/platform`, and a disposable
**Experimentation Layer** running Distrobox (rootless Podman) containers at `/srv/experiments`.
The Experimentation Layer provides isolated, GPU-accelerated environments for ML research,
model builds, and agent development — without risking contamination of the production stack.
When an experiment proves stable and valuable, it graduates to the Platform Layer.

---

## Two-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  HAL-10k Host (Pop!_OS 24.x)                                    │
│                                                                  │
│  ┌───────────────────────────────────┐                          │
│  │  PLATFORM LAYER                   │  /srv/platform           │
│  │  Docker Compose (root daemon)     │  Stable production svc   │
│  │                                   │                          │
│  │  Traefik · Ollama · LiteLLM       │                          │
│  │  Open WebUI · ChromaDB · n8n      │                          │
│  │  Gitea · Portainer · Dockge       │                          │
│  └───────────────────────────────────┘                          │
│                                                                  │
│  ┌───────────────────────────────────┐                          │
│  │  EXPERIMENTATION LAYER            │  /srv/experiments        │
│  │  Distrobox (rootless Podman)      │  Disposable ML envs      │
│  │                                   │                          │
│  │  ml-lab · llama-build             │                          │
│  │  agents-dev · ragna-ml            │                          │
│  │  torch-nightly                    │                          │
│  └───────────────────────────────────┘                          │
│                                                                  │
│  BOUNDARY RULE: experiment stable > 2 weeks → Platform Layer    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why a Separate Experimentation Layer

Running ML experiments directly on the host or inside the Docker stack risks contaminating
the stable production environment. The table below shows typical risks:

| Tool / Scenario | Host Contamination Risk |
|-----------------|------------------------|
| llama.cpp custom builds | Shared libs, compiler flags bleed into system |
| ROCm nightly / beta | Overrides stable ROCm install used by Ollama |
| PyTorch nightly | pip / conda conflicts with other Python workloads |
| Vulkan SDK dev builds | Conflicts with system Vulkan used by ROCm |
| LangChain / CrewAI experiments | Dependency hell across Python environments |
| C++ CMake experiments | Build artifacts and cached state pollute system |
| Model weight downloads | Untracked disk usage in unmanaged locations |

---

## Why Distrobox for Experiments

| Criterion | Docker (Platform Layer) | Distrobox (Experiment Layer) |
|-----------|------------------------|------------------------------|
| Intended lifetime | Weeks → permanent | Hours → days |
| Home directory | Isolated volume | Auto-mounted from host |
| GPU access | `deploy.resources.reservations` stanza | Auto-mounts `/dev/dri` |
| Root daemon required | Yes (Docker CE) | No (rootless Podman) |
| Feels like | Service container | Interactive dev shell |
| SSH / X11 forwarding | Manual config | Works by default |
| Disposal | `docker compose down -v` | `distrobox rm <name>` |

---

## Design Principles

1. **Disposability** — Every container is assumed throwaway; nothing in `/srv/experiments`
   is backed up or treated as persistent.
2. **Isolation** — Experiment dependencies (ROCm nightly, PyTorch nightly, custom builds)
   must not touch the host system or the Platform Layer.
3. **Reproducibility** — All container creation commands are version-controlled in
   `/srv/experiments/create.sh`; recreating an environment is a single command.
4. **Home transparency** — The user's home directory is auto-mounted inside every
   Distrobox container; dotfiles, SSH keys, and git config are available without duplication.
5. **GPU availability** — The RDNA 8060S iGPU (`/dev/dri`) is auto-mounted by Distrobox;
   ROCm / Vulkan toolchain installation is an inside-container step.
6. **No long-running daemons** — The Experimentation Layer runs interactive shells and
   short-lived servers (JupyterLab, llama.cpp); nothing is managed by systemd or auto-started.
7. **Named, not anonymous** — All containers have descriptive names (`ml-lab`, `ragna-ml`,
   etc.) matching entries in the Environment Catalog; no one-off unnamed containers.

---

## Experiment Lifecycle

```
        IDEA
          │
          ▼
        RAW  ─────────────────────────────────────────────┐
     (new Distrobox container)                            │
          │                                               │
          │  works? / reproducible?                       │ one-off?
          ▼                                               │
      VALIDATED                                           │
   (stable in container)                                  │
          │                                               │
          │  > 2 weeks daily use?                         │
          ▼                                               ▼
  GRADUATION CANDIDATE                                RETIRE
   (documented, config                             (distrobox rm)
    stabilized)
          │
          │  meets all 4 graduation criteria?
          ▼
   PLATFORM SERVICE
  (Docker Compose stack,
   Traefik-exposed,
   versioned in repo)
```

---

## Graduation Criteria

An experiment graduates to the Platform Layer when **all four** criteria are met:

1. **Daily use** — the experiment is used every day, not just occasionally.
2. **Config stabilized** — no more changes to core dependencies, ports, or data paths.
3. **Reboot persistence** — the service is expected to survive and restart after a host reboot.
4. **Documented in runbook** — a `docs/runbooks/` entry exists covering deployment and verification.

---

## Graduation Targets

| From (Distrobox) | To (Docker Compose) | Notes |
|------------------|---------------------|-------|
| LM Studio model server | Ollama (`compose/ai/`) | Ollama is the production model server |
| LM Studio model server | vLLM (`compose/ai/`) | If throughput demands vLLM |
| llama.cpp server | llama.cpp service (`compose/ai/`) | If Vulkan inference preferred over ROCm |
| JupyterLab (`ragna-ml`) | JupyterHub (`compose/notebooks/`) | Multi-user notebook server |
| Experiment endpoint | Traefik-exposed service | Any stable HTTP API |

---

## Environment Catalog

Standard containers maintained in the Experimentation Layer:

| Container | Base Image | Key Packages | Status |
|-----------|------------|--------------|--------|
| `ml-lab` | ubuntu:24.04 | Python 3.12, PyTorch stable, Transformers, HuggingFace Hub | planned |
| `llama-build` | ubuntu:24.04 | C++, CMake, ROCm dev headers, Vulkan SDK | planned |
| `agents-dev` | fedora:40 | Python 3.12, LangChain, CrewAI, AutoGen | planned |
| `ragna-ml` | ubuntu:24.04 | JupyterLab + ML baseline stack | planned |
| `torch-nightly` | ubuntu:22.04 | PyTorch nightly (isolated from stable) | planned |

All container creation commands are version-controlled in `/srv/experiments/create.sh`.

---

## JupyterLab

JupyterLab runs **inside the `ragna-ml` Distrobox container** and is accessible at
`http://localhost:8888`. The host home directory is auto-mounted, so notebooks saved
inside the container are immediately visible on the host filesystem. JupyterLab is
started manually per session — it is not a persistent daemon.

---

## LM Studio

LM Studio is a **host-level desktop application** — it does not run inside Distrobox.
It uses the shared model directory at `/srv/platform/models/` and exposes an
OpenAI-compatible API at `http://localhost:1234/v1`. LM Studio is the "Winamp of
local LLMs": excellent for manual, interactive model exploration and A/B testing before
committing a model to the Ollama roster.

---

## GPU Access

The RDNA 8060S iGPU auto-mounts `/dev/dri` devices into every Distrobox container —
no extra configuration required at container creation time. ROCm and Vulkan toolchain
installation is an **inside-container step** documented in the experimentation layer
setup runbook (`docs/runbooks/experimentation-layer-setup.md`), not on the host.
This keeps GPU driver installation fully scoped to the experiment environment.
