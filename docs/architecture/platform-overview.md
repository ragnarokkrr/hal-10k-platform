# Platform Architecture Overview

## HAL-10k Self-Hosted AI Server

**Host**: BOSGAME M5 AI Mini
**Purpose**: Local LLM inference, RAG pipelines, workflow automation, and knowledge management for the HAL-10k Personal Assistant system.

---

## Hardware

```
┌─────────────────────────────────────────────┐
│  BOSGAME M5 AI Mini                         │
│                                             │
│  CPU: AMD Ryzen AI Max+ 395                 │
│       16C / 32T, Zen 5, NPU                 │
│  RAM: 128 GB LPDDR5X (unified)              │
│  iGPU: RDNA 3.5, 40 CU (shared VRAM pool)  │
│  NVMe: 2 TB                                 │
│  OS:   Pop!_OS 24.x LTS (x86_64)           │
│  GPU:  ROCm 7.2                             │
└─────────────────────────────────────────────┘
```

---

## Storage Layout

```
/dev/nvme0n1
├── p1  /boot/efi     512 MB   FAT32
├── p2  /boot           2 GB   ext4
├── p3  /            350 GB   ext4    ← OS root
├── p4  /srv/platform  1.35 TB  ext4  ← ALL service data
└── p5  /mnt/timeshift  250 GB  ext4  ← Timeshift snapshots
```

### /srv/platform layout

```
/srv/platform/
├── compose/          # Live Compose stack working dirs (managed by Dockge)
├── docker/           # Docker data-root (images, volumes, overlay)
├── models/           # LLM model weights
│   └── ollama/       # Ollama model cache
├── datasets/         # Training + evaluation datasets
├── vectordb/         # ChromaDB persistent data
├── backups/          # Application-level backups
├── secrets/          # Decrypted runtime secrets (gitignored, ephemeral)
├── repos/            # Checked-out git repos
│   └── hal-10k-platform/   ← this repo
└── logs/             # Aggregated service logs
```

---

## Service Architecture

```
                         ┌──────────────────────┐
  External / LAN  ──────▶│  Traefik (core)      │ :80 / :443
                         └──────────┬───────────┘
                                    │  (route by host/path)
            ┌───────────────────────┼────────────────────┐
            │                       │                    │
     ┌──────▼──────┐      ┌────────▼──────┐    ┌────────▼──────┐
     │  Open WebUI  │      │   n8n         │    │  Gitea        │
     │  :3000       │      │   :5678       │    │  :3001        │
     └──────┬───────┘      └──────┬────────┘    └───────────────┘
            │                     │
     ┌──────▼───────────────────▼─────┐
     │         LiteLLM Proxy           │  :4000
     │  (model routing + rate limit)   │
     └──────────────┬─────────────────┘
                    │
           ┌────────▼──────────┐
           │  Ollama           │  :11434
           │  (GPU inference)  │
           │  ROCm / RDNA 3.5  │
           └───────────────────┘

     ┌─────────────────────┐
     │  ChromaDB           │  :8000
     │  (vector store)     │
     └─────────────────────┘

     ┌─────────────────────┐    ┌────────────────┐
     │  Portainer  :9443   │    │  Dockge  :5001 │
     │  (container mgmt)   │    │  (stack mgmt)  │
     └─────────────────────┘    └────────────────┘
```

---

## Model Roster (Planned)

| Model | Size | Role | RAM footprint |
|-------|------|------|---------------|
| Qwen2.5-Coder-32B | 32B | Code generation | ~22 GB |
| DeepSeek-Coder-33B | 33B | Reasoning / analysis | ~23 GB |
| Llama-3.3-70B | 70B | General / architecture | ~48 GB |

Total concurrent footprint: ~93 GB (within 128 GB unified RAM).

---

## Secrets Flow

```
age keypair (developer machine)
    │
    ▼
sops encrypt → secrets/*.enc.yaml  (committed to git)
                        │
                        │  git pull + sops --decrypt
                        ▼
              /srv/platform/secrets/*.yaml  (runtime only, gitignored)
                        │
                        │  env_file / volume mount
                        ▼
              Docker containers
```

---

## Network

| Service | Port | Access |
|---------|------|--------|
| Traefik HTTP | 80 | LAN |
| Traefik HTTPS | 443 | LAN |
| Traefik Dashboard | 8080 | LAN |
| Portainer | 9443 | LAN |
| Dockge | 5001 | LAN |
| Ollama | 11434 | Internal / Traefik |
| LiteLLM | 4000 | Internal / Traefik |
| Open WebUI | 3000 | Traefik |
| ChromaDB | 8000 | Internal |
| n8n | 5678 | Traefik |
| Gitea | 3001 | Traefik |
| XRDP | 3389 | LAN |
