# ADR-0002: Remount Platform Partition from /srv/platform to /srv

**Date**: 2026-03-09
**Status**: Accepted

---

## Context

The `platform` partition (nvme0n1p5, ~1.35 TB, ext4) was originally mounted at
`/srv/platform`. The Experimentation Layer design (see
`docs/architecture/experimentation-layer.md`) introduces a second top-level directory,
`/srv/experiments/`, to house Distrobox-based ML containers alongside the Platform Layer.

With the partition mounted at `/srv/platform`, both trees cannot coexist under a single
dedicated partition:

- `/srv/platform/` — Docker Compose stacks, models, data (Platform Layer)
- `/srv/experiments/` — Distrobox containers (Experimentation Layer)

Placing experiments on the OS root partition (`/`) is undesirable: the root is on a 350 GB
partition primarily sized for the OS, and experiment data (model weights, datasets,
container rootfs) can grow to hundreds of gigabytes.

## Decision

Remount the `platform` partition at **`/srv`** instead of `/srv/platform`.

Inside the partition, all existing top-level directories (`compose`, `docker`, `models`,
`datasets`, etc.) are moved into a new `platform/` subdirectory. After the migration:

| Path | Old location | New location |
|------|-------------|-------------|
| Compose stacks | `/srv/platform/compose/` | `/srv/platform/compose/` |
| Model weights | `/srv/platform/models/` | `/srv/platform/models/` |
| Experiment containers | (did not exist) | `/srv/experiments/` |

From the application's perspective, all `/srv/platform/*` paths are **unchanged**. Only
the fstab mount point changes (`/srv/platform` → `/srv`).

The `/etc/fstab` entry is updated from:

```
UUID=<uuid>  /srv/platform  ext4  defaults,noatime  0  2
```

to:

```
UUID=<uuid>  /srv           ext4  defaults,noatime  0  2
```

No changes to Docker Compose files, `.env` files, or provisioning scripts are required,
because `/srv/platform/` continues to resolve to the same physical location.

## Consequences

**Positive**:
- Both Platform Layer (`/srv/platform/`) and Experimentation Layer (`/srv/experiments/`)
  share the same 1.35 TB partition, with no changes to existing application paths
- Avoids consuming OS root partition space for experiment data
- Single partition to monitor, back up, and snapshot with Timeshift
- Clean separation of concerns: the partition boundary is at `/srv`, logical boundaries
  are at `/srv/platform/` and `/srv/experiments/`

**Negative**:
- Requires a brief service outage (Docker stop → umount → remount → Docker start) to
  perform the migration
- `/srv` on Linux is a standard FHS directory; mounting the partition there shadows any
  OS-level content that was previously at `/srv` (verified empty on this system)
- Any future documentation or runbooks referencing the fstab mount point must use `/srv`

## Alternatives Considered

| Alternative | Reason rejected |
|-------------|-----------------|
| Keep partition at `/srv/platform`, add a second partition for `/srv/experiments/` | Wastes unallocated space; partition resizing is risky on a live system |
| Keep partition at `/srv/platform`, bind-mount `/srv/experiments` → `/srv/platform/experiments/` | Adds indirection; breaks clean path semantics; non-obvious to operators |
| Add a separate physical drive for experiments | No available drive slot without hardware changes |
| Store experiments on OS root (`/`) | Root partition is 350 GB and primarily sized for OS; insufficient for large model/dataset workloads |

## Implementation

See runbook: `bootstrap/02-partitioning/remount-srv-platform-to-srv.md`
