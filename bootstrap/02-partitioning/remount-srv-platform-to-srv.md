# How-To: Remount Platform Partition from /srv/platform to /srv

**Phase**: bootstrap/02 — partitioning
**Status**: Pending
**ADR**: [ADR-0002](../../docs/decisions/adr/ADR-0002-remount-platform-partition-to-srv.md)

Context: [[create-srv-platform-partition-gparted-live|Create /srv/platform Partition Using GParted Live]]

---

**Goal**: change the partition mount point from `/srv/platform` → `/srv`, and move all existing top-level directories into a new `platform/` subdirectory inside the partition. After the change, paths like `/srv/platform/models` become `/srv/platform/models` (unchanged from the user's perspective), but the partition itself is now mounted at `/srv`.

> [!warning] Prerequisites
> - Stop Docker and any service writing to `/srv/platform` before unmounting
> - `/srv` already exists as a standard Linux directory — mounting there will shadow any content previously in it (check `ls /srv` first)
> - **Backup** or snapshot with Timeshift before starting

---

## Step 1 — Stop services using the partition

```bash
sudo systemctl stop docker
# Verify nothing is using the mount
sudo lsof +D /srv/platform 2>/dev/null | wc -l
```

## Step 2 — Unmount the partition from its current location

```bash
sudo umount /srv/platform
# If busy: sudo umount -l /srv/platform (lazy unmount — use as last resort)
```

## Step 3 — Mount the partition at a temporary location

```bash
sudo mkdir -p /mnt/platform-tmp
# Find device name (look for 'platform' label or ext4 ~1.3T)
lsblk -f
sudo mount UUID=<PARTITION_UUID> /mnt/platform-tmp
```

## Step 4 — Create the `platform/` subdirectory inside the partition

```bash
sudo mkdir -p /mnt/platform-tmp/platform
```

## Step 5 — Move all top-level directories into `platform/`

```bash
for dir in backups  compose  databases  datasets  docker  dockge  logs  lost+found  models  stacks  vector  volumes; do
  [ -d /mnt/platform-tmp/$dir ] && sudo mv /mnt/platform-tmp/$dir /mnt/platform-tmp/platform/
done
```

Verify:

```bash
ls /mnt/platform-tmp/platform/
# Expected: backups  compose  databases  datasets  docker  dockge  logs  models  stacks  vector
```

## Step 6 — Unmount from temporary location

```bash
sudo umount /mnt/platform-tmp
sudo rmdir /mnt/platform-tmp
```

## Step 7 — Update `/etc/fstab`

```bash
sudo nano /etc/fstab
```

Change:
```
UUID=YOUR-UUID  /srv/platform  ext4  defaults,noatime  0  2
```
To:
```
UUID=YOUR-UUID  /srv           ext4  defaults,noatime  0  2
```

## Step 8 — Mount at the new location and verify

```bash
sudo mount -a
df -h | grep nvme0n1p5
# Expected: ~1.3T mounted at /srv
ls /srv/platform/
# Expected: all directories present
```

## Step 9 — Restart Docker and validate

```bash
sudo systemctl start docker
docker ps
ls /srv/platform/models/
```

> [!tip] After the remount
> Update any hardcoded `/srv/platform` paths in Docker Compose files, `.env` files, and `hal-10k-platform` provisioning scripts to use `/srv/platform` (unchanged) — since `platform/` is now a directory inside the mount, the paths themselves do not change. Only the fstab mount point changes.
