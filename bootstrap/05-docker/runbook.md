# Runbook: Docker CE + Portainer + Dockge Installation

**Phase**: bootstrap/05 — docker
**Status**: Verified
**Last verified**: 2026-03-08
**Performed by**: ragnarokkrr

---

## Purpose

Install Docker CE, relocate the Docker data-root to `/srv/platform/docker`, and deploy
Portainer (container management UI) and Dockge (Compose stack manager) as the foundation
for all future service deployments.

---

## Prerequisites

- [ ] Phase 02 (partitioning) complete — `/srv/platform` mounted
- [ ] Phase 03 (ROCm) complete
- [ ] Internet connectivity

---

## Procedure

### Step 1 — Install Docker CE

```bash
# Remove any old Docker packages
sudo apt remove -y docker docker.io docker-compose containerd runc 2>/dev/null || true

# Add Docker's official APT repository
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Step 2 — Add User to Docker Group

```bash
sudo usermod -aG docker $USER
# Log out and back in for group membership to take effect
```

### Step 3 — Relocate Docker Data-Root to /srv/platform/docker

```bash
# Stop Docker
sudo systemctl stop docker

# Create the new data-root
sudo mkdir -p /srv/platform/docker

# Configure Docker daemon
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/srv/platform/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

# Start Docker with new config
sudo systemctl start docker
sudo systemctl enable docker
```

**Verify**:
```bash
docker info | grep -i "docker root dir"
# Expected: Docker Root Dir: /srv/platform/docker
```

### Step 4 — Deploy Portainer

```bash
docker volume create portainer_data

docker run -d \
  --name portainer \
  --restart=always \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

**Access**: https://hal-10k:9443 (accept self-signed cert, create admin user on first visit)

### Step 5 — Deploy Dockge (Compose Stack Manager)

```bash
sudo mkdir -p /srv/platform/compose /srv/platform/dockge/data

docker run -d \
  --name dockge \
  --restart=always \
  -p 5001:5001 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /srv/platform/dockge/data:/app/data \
  -v /srv/platform/compose:/opt/stacks \
  -e DOCKGE_STACKS_DIR=/opt/stacks \
  louislam/dockge:latest
```

**Access**: http://hal-10k:5001

---

## Verify

```bash
# Docker
docker version
docker compose version
docker info | grep "Docker Root Dir"

# Containers
docker ps
# Expected: portainer, dockge both Up

# Disk (ensure data goes to /srv/platform)
df -h /srv/platform/docker
```

---

## Rollback

```bash
docker stop portainer dockge
docker rm portainer dockge
sudo systemctl stop docker
sudo rm /etc/docker/daemon.json
sudo systemctl start docker
```

To fully remove Docker: `sudo apt purge docker-ce docker-ce-cli containerd.io`

---

## Sources

- Obsidian vault note: `[[docker-portainer-dockge-how-to]]`
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`
