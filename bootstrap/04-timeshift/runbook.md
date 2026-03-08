# Runbook: Timeshift Backup Configuration

**Phase**: bootstrap/04 — timeshift
**Status**: Verified
**Last verified**: 2026-03-08
**Performed by**: ragnarokkrr

---

## Purpose

Configure Timeshift in RSYNC mode on the dedicated 250 GB partition to provide
system-level snapshot backups of the OS root (`/`). Docker volumes, model weights, and
caches are explicitly excluded.

---

## Prerequisites

- [ ] Phase 02 (partitioning) complete — `/mnt/timeshift` mounted
- [ ] Timeshift installed (included in Pop!_OS by default, else: `sudo apt install timeshift`)

---

## Retention Policy

| Schedule | Count |
|----------|-------|
| Boot | Enabled |
| Hourly | Off |
| Daily | 5 |
| Weekly | 3 |
| Monthly | 2 |

---

## Procedure

### Step 1 — Open Timeshift GUI (Initial Setup)

```bash
sudo timeshift-gtk
```

Or configure via CLI directly (Step 2).

### Step 2 — Configure via CLI

```bash
sudo timeshift --config
```

Alternatively, write the config directly:

```bash
sudo nano /etc/timeshift/timeshift.json
```

Paste:

```json
{
  "backup_device_uuid": "<UUID-of-timeshift-partition>",
  "parent_device_uuid": "",
  "do_first_run": "false",
  "btrfs_mode": "false",
  "include_btrfs_home_for_backup": "false",
  "include_btrfs_home_for_restore": "false",
  "stop_cron_emails": "true",
  "btrfs_use_qgroup": "true",
  "schedule_monthly": "true",
  "schedule_weekly": "true",
  "schedule_daily": "true",
  "schedule_hourly": "false",
  "schedule_boot": "true",
  "count_monthly": "2",
  "count_weekly": "3",
  "count_daily": "5",
  "count_hourly": "6",
  "count_boot": "3",
  "snapshot_size": "",
  "snapshot_count": "",
  "date_format": "%Y-%m-%d %H:%M:%S",
  "exclude": [
    "/srv/platform/**",
    "/home/**/.cache/**",
    "/home/**/node_modules/**",
    "/tmp/**",
    "/var/tmp/**",
    "/var/cache/**",
    "/var/log/**"
  ],
  "exclude-apps": []
}
```

Replace `<UUID-of-timeshift-partition>` with the actual UUID from `blkid`.

### Step 3 — Take First Snapshot

```bash
sudo timeshift --create --comments "Phase 04 baseline — post-ROCm install"
```

### Step 4 — Verify

```bash
sudo timeshift --list
# Expected: at least one snapshot listed with today's date
df -h /mnt/timeshift
# Expected: snapshot subdirectory with ~10–30 GB used
```

---

## Exclusions Rationale

| Excluded Path | Reason |
|---------------|--------|
| `/srv/platform/**` | Large data; managed separately (model weights, Docker volumes) |
| `/home/**/.cache` | Ephemeral; regenerable |
| `/tmp`, `/var/tmp` | Ephemeral |
| `/var/cache` | Regenerable via `apt` |
| `/var/log` | Optional; restore without stale logs is cleaner |

---

## Rollback (Restore a Snapshot)

```bash
# List snapshots
sudo timeshift --list

# Restore (requires reboot into recovery or GParted Live)
sudo timeshift --restore --snapshot "YYYY-MM-DD_HH-MM-SS" --target /dev/nvme0n1p3
```

---

## Sources

- Obsidian vault note: `[[timeshift-configurations]]`
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`
