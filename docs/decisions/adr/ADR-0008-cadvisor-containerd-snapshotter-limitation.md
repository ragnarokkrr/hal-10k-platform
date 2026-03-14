# ADR-0008: cAdvisor Container Discovery Failure with Docker Containerd Snapshotter

**Date**: 2026-03-14
**Status**: Accepted

---

## Context

During Phase 5 observability deployment, cAdvisor v0.52.0 was deployed to collect
per-container CPU, memory, and resource metrics. Prometheus targets for cAdvisor showed
`UP`, meaning the scrape succeeded, but the Container Resources dashboard showed no
per-container data. All container CPU series in Prometheus had only generic labels
(`id`, `instance`, `job`) — no `container_label_com_docker_compose_service` or `name`
labels that the dashboard queries relied on.

Investigation revealed:

```
E0314 Failed to create existing container: /system.slice/docker-<id>.scope:
failed to identify the read-write layer ID for container "<id>".
open /rootfs/srv/platform/docker/image/overlayfs/layerdb/mounts/<id>/mount-id:
no such file or directory
```

### Root Cause

Docker 29.x defaults to the **containerd snapshotter** (`io.containerd.snapshotter.v1`)
when started with `--containerd=/run/containerd/containerd.sock`. In this mode:

- Docker stores image layer metadata inside containerd's content store (a boltdb at
  `containerd/daemon/io.containerd.metadata.v1.bolt/meta.db`)
- The classic `image/overlayfs/layerdb/mounts/<container-id>/mount-id` path that
  cAdvisor's Docker factory uses **does not exist**
- `docker inspect <container>` returns `"GraphDriver": null`

cAdvisor discovers Docker containers via two factories:

1. **Docker factory** — watches `/system.slice/docker-<id>.scope` cgroup paths,
   resolves them using the Docker storage API by reading `layerdb/mounts/<id>/mount-id`.
   Fails with containerd snapshotter.

2. **Containerd factory** — lists tasks in a specified containerd namespace and resolves
   their cgroup paths. With `--containerd-namespace=moby`, this factory registers
   successfully but does not match the Docker-named systemd scope cgroup paths, so the
   containers remain undiscovered.

Neither factory successfully maps the running Docker containers to named metrics.

### Environment

| Property | Value |
|----------|-------|
| Docker version | 29.3.0 |
| Storage driver | `overlayfs` (`io.containerd.snapshotter.v1`) |
| cAdvisor version | v0.52.0 |
| Docker data-root | `/srv/platform/docker` |
| Platform | HAL-10k (Pop!_OS 24.x, single node) |

---

## Decision

**Accept the limitation for now.** Do not switch Docker's storage driver during Phase 5.

Switching from the containerd snapshotter to `overlay2` requires:

1. Stopping all running containers across all stacks
2. Running `docker image prune -a` (all images are in the wrong format)
3. Restarting the Docker daemon
4. Re-pulling all images (~5 GB across all stacks, 30–60 min)

This is a scheduled maintenance task, not an emergency. The observability stack
delivers full value without per-container CPU/memory breakdown:

- **Host Overview** dashboard: CPU, RAM, disk, network — fully operational via
  Node Exporter
- **Traefik** dashboard: request rate, error rate, latency — fully operational
- **Container Resources** dashboard: no per-container data until fixed

The fix is recorded as a backlog item and can be executed during a planned maintenance
window without any data loss (model weights are in Docker volumes, not images).

---

## Rationale

### Why not fix immediately

- All Ollama model weights (~130 GB total across three models) are stored in a Docker
  **volume** bind-mounted at `/srv/platform/models/` — they survive the image prune
- However, re-pulling images requires an active internet connection and 30–60 min of
  service downtime
- Phase 5 objectives are met without per-container metrics; host-level metrics are
  sufficient for the current operational need
- Switching storage drivers mid-phase adds unplanned risk to an otherwise working deploy

### Why not use a different container exporter

- `dockerd-exporter` / `prom/container_exporter` use the Docker stats API but expose
  fewer metrics than cAdvisor (no CPU throttling, no filesystem per-container, no
  per-interface network I/O)
- Long-term, cAdvisor with `overlay2` is the correct solution; introducing a second
  exporter would create technical debt

### Why the containerd factory does not solve it

Docker's containerd integration places container tasks in the `moby` namespace.
cAdvisor's containerd factory queries this namespace but expects cgroup paths in the
form `/system.slice/containerd-<task-pid>.scope`. Docker creates scopes named
`/system.slice/docker-<container-id>.scope`. The name mismatch means the containerd
factory registers successfully but discovers zero containers.

This is an upstream cAdvisor limitation tracked in
[google/cadvisor#3468](https://github.com/google/cadvisor/issues/3468) and related
issues. Resolution requires a cAdvisor code change or a workaround at the Docker
configuration level.

---

## Consequences

- **Positive**: No service disruption during Phase 5 deployment.
- **Positive**: Issue is fully documented, reproducible, and reversible.
- **Negative**: Container Resources Grafana dashboard shows no per-container data until
  the fix is applied.
- **Negative**: Per-container CPU/memory alerting cannot be configured until fixed.

---

## Resolution Plan

To fix in a scheduled maintenance window:

**Step 1** — Update `/etc/docker/daemon.json`:
```json
{
  "data-root": "/srv/platform/docker",
  "features": { "containerd-snapshotter": false },
  ...
}
```

**Step 2** — Stop all stacks:
```bash
docker compose -f compose/observability/docker-compose.yml down
docker compose -f compose/ai/docker-compose.yml down
docker compose -f compose/core/docker-compose.yml down
```

**Step 3** — Prune images (volumes are preserved):
```bash
docker image prune -a --force
```

**Step 4** — Restart Docker daemon:
```bash
sudo systemctl restart docker
```

**Step 5** — Re-pull images and bring stacks back up:
```bash
docker compose -f compose/core/docker-compose.yml pull && docker compose -f compose/core/docker-compose.yml up -d
docker compose -f compose/ai/docker-compose.yml pull && docker compose -f compose/ai/docker-compose.yml up -d
docker compose -f compose/observability/docker-compose.yml pull && docker compose -f compose/observability/docker-compose.yml up -d
```

**Step 6** — Verify cAdvisor discovers containers:
```bash
docker exec prometheus wget -qO- \
  'http://localhost:9090/api/v1/series?match[]=container_cpu_usage_seconds_total{container_label_com_docker_compose_service!=""}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['data']), 'container series found')"
# Expected: > 0
```

---

## Alternatives Considered

| Option | Rejected Because |
|--------|-----------------|
| Switch to `overlay2` immediately | Unplanned ~60 min downtime across all stacks; not justified by urgency |
| Use `dockerd-exporter` as interim | Fewer metrics than cAdvisor; creates tech debt |
| Pin Docker to an older version | Containerd snapshotter was backported; not a long-term solution |
| Patch cAdvisor Docker factory | Requires building custom image; maintenance burden |
