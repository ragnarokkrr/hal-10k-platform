# Runbook: Storage Partitioning — /srv/platform + /timeshift

**Phase**: bootstrap/02 — partitioning
**Status**: Verified
**Last verified**: 2026-03-07
**Performed by**: ragnarokkrr

---

## Purpose

Create the dedicated `/srv/platform` (1.35 TB) and `/timeshift` (250 GB) partitions on
the 2 TB NVMe SSD using GParted Live, then mount them persistently and scaffold the
platform directory structure.

---

## Prerequisites

- [ ] Phase 01 (OS install) complete
- [ ] USB drive with GParted Live ISO
- [ ] Know target disk: `/dev/nvme0n1` (verify with `lsblk`)

---

## Final Partition Layout

| # | Mount | Size | Filesystem | Purpose |
|---|-------|------|------------|---------|
| 1 | /boot/efi | 512 MB | FAT32 | UEFI boot |
| 2 | /boot | 2 GB | ext4 | Kernel / initrd |
| 3 | / | 350 GB | ext4 | OS root |
| 4 | /srv/platform | 1.35 TB | ext4 | Service data |
| 5 | (no mount) | 250 GB | ext4 | Timeshift snapshots |

---

## Procedure

### Step 1 — Boot GParted Live

1. Insert GParted Live USB, power on, select from boot menu
2. Accept defaults for language / keymap / display
3. GParted opens automatically

### Step 2 — Identify Free Space

The Pop!_OS installer will have created partitions 1–3. Verify the remaining ~1.6 TB
shows as unallocated space.

```
Device: /dev/nvme0n1
```

### Step 3 — Create /srv/platform Partition (1.35 TB)

In GParted:
1. Right-click unallocated → **New**
2. New size: `1382400 MiB` (~1.35 TB)
3. Filesystem: `ext4`
4. Label: `platform`
5. Click **Add**

### Step 4 — Create /timeshift Partition (250 GB)

1. Right-click remaining unallocated → **New**
2. New size: `256000 MiB` (~250 GB)
3. Filesystem: `ext4`
4. Label: `timeshift`
5. Click **Add**

### Step 5 — Apply Changes

Click **Apply All Operations** (green checkmark). Wait for completion (~5–10 min).

### Step 6 — Reboot into Pop!_OS

Remove GParted USB, reboot.

### Step 7 — Add fstab Entries

```bash
# Get UUIDs
sudo blkid | grep nvme0n1

# Edit fstab
sudo nano /etc/fstab
```

Add these lines (replace UUIDs with actual values from blkid):

```
UUID=<platform-uuid>   /srv/platform   ext4   defaults,noatime   0   2
UUID=<timeshift-uuid>  /mnt/timeshift  ext4   defaults,noatime   0   2
```

```bash
sudo mkdir -p /srv/platform /mnt/timeshift
sudo mount -a
df -h | grep -E 'platform|timeshift'
```

### Step 8 — Scaffold /srv/platform Directory Structure

```bash
sudo mkdir -p /srv/platform/{compose,docker,models,datasets,vectordb,backups,secrets,repos,logs}
sudo chown -R $USER:$USER /srv/platform
chmod 750 /srv/platform/secrets
```

**Verify**:
```bash
ls -la /srv/platform/
# Expected: compose  docker  models  datasets  vectordb  backups  secrets  repos  logs
df -h /srv/platform
# Expected: ~1.35T total
```

---

## Rollback

Partitions are non-destructive additions to existing free space. To undo:
- Boot GParted Live again
- Delete the `platform` and `timeshift` partitions
- Remove the fstab entries

---

## Sources

- Obsidian vault note: `[[create-srv-platform-partition-gparted-live]]`
- Obsidian vault note: `[[service-platform-partition-strategy]]`
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`
