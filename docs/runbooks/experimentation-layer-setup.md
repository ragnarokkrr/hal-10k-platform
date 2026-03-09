# Runbook: Experimentation Layer Setup

**Phase**: bootstrap/07 — experimentation layer
**Status**: Draft
**Last verified**: not yet executed
**Performed by**: ragnarokkrr

---

## Purpose

Establish the Experimentation Layer on HAL-10k: install Distrobox and rootless Podman,
create the `/srv/experiments/` directory convention, and bootstrap the standard container
catalog. This runbook covers setup steps only — container creation commands are
version-controlled in `/srv/experiments/create.sh` and executed separately.

---

## Prerequisites

- [ ] Phase 0 bootstrap completed (Docker CE + Pop!_OS baseline running)
- [ ] ROCm 7.2 installed and verified on host (`bootstrap/03-rocm/`)
- [ ] Logged in as a non-root user with sudo access
- [ ] Internet access available for package downloads

---

## Procedure

### Step 1 — Install Distrobox + Podman

> **Note**: Steps listed here; commands not yet executed and not yet verified on HAL-10k.

Install rootless Podman and Distrobox from the Pop!_OS / Ubuntu package repositories.
Verify rootless Podman operation before proceeding to Distrobox container creation.

### Step 2 — Create `/srv/experiments/` Directory Structure

> **Note**: Steps listed here; commands not yet executed.

Create the top-level `/srv/experiments/` directory with appropriate ownership and
permissions. Establish subdirectory conventions for per-container state and shared
artifacts. The `create.sh` script will live at `/srv/experiments/create.sh`.

### Step 3 — Standard Container Catalog

> **Note**: Container creation deferred to Phase 9 implementation. The table below
> records the planned catalog; actual `distrobox create` commands are to be added to
> `create.sh`.

| Container | Base Image | Key Packages | Status |
|-----------|------------|--------------|--------|
| `ml-lab` | ubuntu:24.04 | Python 3.12, PyTorch stable, Transformers, HuggingFace Hub | planned |
| `llama-build` | ubuntu:24.04 | C++, CMake, ROCm dev headers, Vulkan SDK | planned |
| `agents-dev` | fedora:40 | Python 3.12, LangChain, CrewAI, AutoGen | planned |
| `ragna-ml` | ubuntu:24.04 | JupyterLab + ML baseline stack | planned |
| `torch-nightly` | ubuntu:22.04 | PyTorch nightly (isolated from stable) | planned |

### Step 4 — GPU Validation Steps

> **Note**: Commands listed here for reference; not yet executed. Run inside a Distrobox
> container after Step 3.

Validate iGPU passthrough inside a container using the following tools:

- `clinfo` — verify OpenCL device enumeration (RDNA 8060S visible)
- `vulkaninfo` — verify Vulkan ICD and device properties
- `rocminfo` — verify ROCm agent enumeration and GPU compute unit count

All three must show the RDNA 8060S before proceeding to GPU-accelerated workloads.

### Step 5 — JupyterLab Bootstrap (`ragna-ml`)

> **Note**: Steps listed here; not yet executed.

Inside the `ragna-ml` container:

- Install JupyterLab and the ML baseline stack (PyTorch stable, NumPy, Pandas, Matplotlib)
- Configure JupyterLab to bind on `localhost:8888`
- Verify the home directory is auto-mounted and notebooks persist on the host filesystem
- Start JupyterLab manually; confirm access at `http://localhost:8888`

JupyterLab is started per-session — it is not registered as a systemd service.

### Step 6 — `create.sh` Reference

> **Note**: The `create.sh` script is to be implemented in a future phase.

All container creation commands (`distrobox create ...`) will be version-controlled in
`/srv/experiments/create.sh`. This script is the single source of truth for recreating
any container from scratch. It is not present yet; it will be authored as part of
Phase 9 implementation.

Expected location: `/srv/experiments/create.sh`

---

## Verification

- [ ] `distrobox version` returns a valid version string
- [ ] `podman info` confirms rootless operation (no root daemon)
- [ ] `/srv/experiments/` directory exists with correct ownership
- [ ] At least one container from the catalog created and enters successfully
- [ ] GPU validation passes (`clinfo`, `vulkaninfo`, `rocminfo`) inside a container
- [ ] JupyterLab accessible at `http://localhost:8888` from `ragna-ml`

---

## Rollback

- Remove Distrobox containers: `distrobox rm <name>` for each container
- Remove `/srv/experiments/` directory if empty and no data to preserve
- Podman and Distrobox packages can be removed via `apt remove` without affecting Docker CE
- ROCm and host GPU drivers are unaffected by this rollback

---

## Sources

- Architecture document: `docs/architecture/experimentation-layer.md`
- Obsidian vault note: `Personal/Ideas/hal-10k-experimentation-layer.md`
- Distrobox documentation: https://distrobox.it/
- Podman rootless setup: https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
