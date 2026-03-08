# Runbook: OS Installation — Pop!_OS 24.x + Desktop Environment

**Phase**: bootstrap/01 — os-install
**Status**: Verified
**Last verified**: 2026-03-07
**Performed by**: ragnarokkrr

---

## Purpose

Install Pop!_OS 24.x LTS, configure a lightweight XFCE desktop, enable remote desktop
access via XRDP, and install baseline developer tools (Remmina, VSCode).

---

## Prerequisites

- [ ] Phase 00 (BIOS) complete
- [ ] USB drive with Pop!_OS 24.x ISO (>= 8 GB)
- [ ] Ethernet / Wi-Fi available during install for package downloads

---

## Procedure

### Step 1 — Create Bootable USB

On a separate machine:

```bash
# Linux
sudo dd if=pop-os_24.04_amd64_nvidia_*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Or use Balena Etcher (GUI)
```

### Step 2 — Boot and Install Pop!_OS

1. Insert USB, power on, press **`F7`** (or `F11`) for boot menu
2. Select the USB device
3. Choose **Clean Install** → select the NVMe drive
4. Partition mode: **Custom / Advanced** → see Phase 02 (partitioning) for the layout
5. Set hostname: `hal-10k`
6. Create user: `ragnarokkrr`
7. Complete installation and reboot

> Note: The Pop!_OS installer creates its own EFI + root partitions. The `/srv/platform`
> and `/timeshift` partitions are created separately via GParted Live (Phase 02).

### Step 3 — First Boot: Update System

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

### Step 4 — Install XFCE Desktop

```bash
sudo apt install -y xfce4 xfce4-goodies
# Set XFCE as default session (optional, for console login)
sudo update-alternatives --set x-session-manager /usr/bin/xfce4-session
```

### Step 5 — Install and Configure XRDP

```bash
sudo apt install -y xrdp
sudo systemctl enable --now xrdp

# Allow XRDP through firewall
sudo ufw allow 3389/tcp

# Configure XRDP to use XFCE
echo "startxfce4" > ~/.xsession
chmod +x ~/.xsession
```

**Verify**:
```bash
sudo systemctl status xrdp
# Expected: active (running)
```

### Step 6 — Install Remmina (Remote Desktop Client)

```bash
sudo apt install -y remmina remmina-plugin-rdp remmina-plugin-vnc
```

### Step 7 — Install VSCode

```bash
# Via snap
sudo snap install code --classic

# Or via Microsoft APT repo
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | \
  sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
  https://packages.microsoft.com/repos/code stable main" | \
  sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update && sudo apt install -y code
```

---

## Verify

```bash
# OS version
lsb_release -a
# Expected: Ubuntu 24.04 / Pop!_OS 24.x

# XRDP
sudo systemctl status xrdp | grep Active

# VSCode
code --version
```

---

## Rollback

Reinstall from USB. No partial rollback available for OS installation.

---

## Sources

- Obsidian vault note: `[[bosgame-m5-initial-software-popos-xrdp-xfce-remmina]]`
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`
