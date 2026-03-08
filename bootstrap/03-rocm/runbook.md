# Runbook: ROCm 7.2 Installation (AMD GPU Compute Stack)

**Phase**: bootstrap/03 — rocm
**Status**: Verified
**Last verified**: 2026-03-08
**Performed by**: ragnarokkrr

---

## Purpose

Install AMD ROCm 7.2 on Pop!_OS 24.x to enable GPU-accelerated inference workloads on
the RDNA 3.5 iGPU (40 Compute Units) integrated in the Ryzen AI Max+ 395.

---

## Prerequisites

- [ ] Phase 01 (OS install) complete
- [ ] Phase 02 (partitioning) complete
- [ ] Internet connectivity
- [ ] BIOS UMA Frame Buffer Size set to 8 GB (Phase 00)

---

## Procedure

### Step 1 — Download amdgpu-install Package

```bash
# ROCm 7.2 for Ubuntu 24.04 (Pop!_OS 24.x is Ubuntu-based)
wget https://repo.radeon.com/amdgpu-install/6.2/ubuntu/noble/amdgpu-install_6.2.60200-1_all.deb
sudo apt install -y ./amdgpu-install_6.2.60200-1_all.deb
```

> Verify the exact package URL at https://rocm.docs.amd.com/en/latest/deploy/linux/index.html

### Step 2 — Install ROCm

```bash
sudo amdgpu-install --usecase=rocm --no-dkms
```

> `--no-dkms` skips the open-source display driver (not needed for compute-only use).
> Remove this flag if you also want the amdgpu display driver.

### Step 3 — Add User to Required Groups

```bash
sudo usermod -aG render,video $USER
```

**Log out and back in** for group membership to take effect.

### Step 4 — Verify ROCm Installation

```bash
rocminfo
# Expected: lists one GPU agent with "gfx1151" or similar RDNA 3.5 target

clinfo
# Expected: lists OpenCL platforms including AMD

rocm-smi
# Expected: shows GPU utilization, temperature, power draw
```

```bash
# Confirm render group membership
groups | grep render
```

---

## Verify (Docker GPU Access)

After Docker is installed (Phase 05), verify containers can access the GPU:

```bash
docker run --device=/dev/kfd --device=/dev/dri \
  -e HSA_OVERRIDE_GFX_VERSION=11.0.0 \
  rocm/pytorch:latest \
  python3 -c "import torch; print(torch.cuda.is_available())"
```

> Expected: `True` (ROCm exposes as CUDA-compatible via HIP)

---

## Environment Variables for Inference

Add to `/etc/environment` or per-service Docker env:

```
HSA_OVERRIDE_GFX_VERSION=11.0.0
ROCR_VISIBLE_DEVICES=0
HIP_VISIBLE_DEVICES=0
```

> `HSA_OVERRIDE_GFX_VERSION` is required for some tools that don't natively recognize
> the RDNA 3.5 target ID.

---

## Rollback

```bash
sudo amdgpu-install --uninstall
sudo apt remove amdgpu-install
```

---

## Sources

- Obsidian vault note: `[[install-rocm-on-popos]]`
- Obsidian vault note: `[[self-host-llm-on-bosgame-m5-ai-mini]]`
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`
