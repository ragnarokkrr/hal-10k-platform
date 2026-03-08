# Runbook: Hardware BIOS Configuration

**Phase**: bootstrap/00 — hardware-bios
**Status**: Verified
**Last verified**: 2026-03-07
**Performed by**: ragnarokkrr

---

## Purpose

Configure the BOSGAME M5 AI Mini BIOS for optimal LLM inference performance:
maximize GPU memory allocation, enable XMP/EXPO memory profile, and set appropriate
power / thermal limits.

---

## Prerequisites

- [ ] Physical access to the machine (or IPMI/out-of-band)
- [ ] USB keyboard attached (BIOS navigation)

---

## Procedure

### Step 1 — Enter BIOS Setup

Power on the machine and repeatedly press **`Delete`** (or `F2`) during POST to enter the
BIOS/UEFI setup utility.

### Step 2 — Enable EXPO / XMP Memory Profile

Navigate to: `Advanced → Memory Configuration`

```
EXPO/XMP Profile: Profile 1  (enables 6400 MT/s LPDDR5X)
Memory Interleaving: Enabled
```

**Verify**: POST screen should show the correct memory speed on next boot.

### Step 3 — Configure UMA Frame Buffer Size (iGPU VRAM)

Navigate to: `Advanced → AMD CBS → NBIO → GFX Configuration`

```
UMA Frame Buffer Size: 8G
```

> Setting 8 GB reserves a fixed VRAM pool for the iGPU. The remaining ~120 GB of unified
> RAM is available to the OS and model weights.

### Step 4 — Power and Thermal Limits

Navigate to: `Advanced → AMD Overclocking → Package Power Limit`

```
TDP: 65 W  (or higher if cooling allows; default may be 45 W)
Sustained Power Limit (PPT): 65000 mW
```

> Increasing TDP allows the CPU/GPU to sustain higher clocks during extended inference
> workloads without thermal throttling.

### Step 5 — Save and Exit

Press **`F10`** → Save Changes and Reset.

---

## Verify (in OS after reboot)

```bash
# Check memory speed
sudo dmidecode -t memory | grep -i speed

# Check GPU VRAM visible to ROCm (after ROCm installed)
rocminfo | grep -A5 "GPU Agent"

# Check CPU/GPU TDP (requires amdgpu_top or lm-sensors)
amdgpu_top --dump-info 2>/dev/null | grep -i power
```

---

## Rollback

Load BIOS defaults: `F9` → Load Optimized Defaults → `F10` Save.
This reverts to safe but conservative settings (lower VRAM, stock TDP).

---

## Sources

- Obsidian vault note: `[[self-host-llm-on-bosgame-m5-ai-mini]]`
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`
