# BOSGAME M5 AI Mini — Hardware Specifications

**Source**: [BOSGAME M5 AI Mini product page](https://www.bosgame.com/products/bosgame-m5-ai-mini-desktop-ryzen-ai-max-395-96gb-128gb-2tb)
**HAL-10k configuration**: 128 GB / 2 TB

---

## Processor

| Property | Value |
|----------|-------|
| Model | AMD Ryzen AI Max+ 395 |
| Architecture | Zen 5 (dual CCDs + dedicated IOD chip) |
| Cores / Threads | 16C / 32T |

## Graphics / iGPU

| Property | Value |
|----------|-------|
| GPU | AMD RDNA 3.5 integrated |
| Compute Units | 40 CU (20 WGP) |
| Comparable to | NVIDIA RTX 4070 (vendor claim) |
| GPU stack | ROCm 7.2 |

## Memory

| Property | Value |
|----------|-------|
| Capacity (HAL-10k) | 128 GB |
| Type | LPDDR5X |
| Speed | 8000 MHz |
| Architecture | Unified (CPU + GPU share same pool) |
| Available config | 96 GB or 128 GB |

## AI / NPU

| Property | Value |
|----------|-------|
| NPU | AMD XDNA 2 |
| NPU TOPS | 50 TOPS |
| Total system TOPS | 126 TOPS |
| LLM benchmark | 2.2× faster than RTX 4090 for local Llama 3 via LM Studio (vendor claim) |

## Storage

| Property | Value |
|----------|-------|
| Capacity (HAL-10k) | 2 TB |
| Interface | Dual M.2 PCIe Gen 4 |
| Expandability | Yes (dual slot) |

## Connectivity

| Interface | Spec |
|-----------|------|
| USB4 Type-C | 2× |
| USB 3.2 Gen 2 | 3× |
| USB 2.0 | 2× |
| Ethernet | 2.5 Gbps LAN |
| SD Card | SD 4.0 reader |

## Display Output

- Multi-display configurations supported via USB4 ports

## Operating System

| Property | Value |
|----------|-------|
| OS (HAL-10k) | Pop!_OS 24.x LTS (x86_64) |
| Vendor OS support | Windows 11 |

## Pricing (at time of purchase)

| Config | Price (USD) |
|--------|------------|
| 128 GB / 2 TB | $2,099 |

## Warranty

- 1-year limited — design and workmanship defects

---

## HAL-10k Disk Layout

| Partition | Mount | Size | Filesystem | Purpose |
|-----------|-------|------|------------|---------|
| nvme0n1p1 | /boot/efi | 512 MB | FAT32 | UEFI boot |
| nvme0n1p2 | /boot | 2 GB | ext4 | Kernel / initrd |
| nvme0n1p3 | / | 350 GB | ext4 | OS root |
| nvme0n1p4 | /srv | 1.35 TB | ext4 | Platform + Experiments data |
| nvme0n1p5 | (dedicated) | 250 GB | ext4 | Timeshift snapshots |

See `bootstrap/02-partitioning/` for the full partitioning runbook.
