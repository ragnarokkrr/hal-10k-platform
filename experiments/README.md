# experiments/ — Experiment Lifecycle Tracking

This directory tracks the lifecycle of Distrobox containers in the HAL-10k
Experimentation Layer using **[Backlog.md](https://github.com/MrLesk/Backlog.md)**.

The Backlog.md project lives at `experiments/backlog/` — one task file per container
under `experiments/backlog/tasks/`, managed by the `backlog` CLI.

See [`docs/architecture/experimentation-layer.md`](../docs/architecture/experimentation-layer.md)
for the full two-layer architecture, graduation criteria, and environment catalog.

---

## Purpose

`experiments/backlog/tasks/` is the single source of truth for the state of every
Distrobox container in `/srv/experiments/`. It answers:

- Which containers exist (or are planned)?
- What lifecycle state is each one in?
- Has a container met the four graduation criteria?

This tracking lives in the provisioning repo so experiment state is version-controlled
alongside the Platform Layer stacks it may eventually graduate into.

---

## Lifecycle States

Each container maps to one of seven lifecycle states, expressed as a Backlog.md
**status** + **label** pair:

| Lifecycle State       | Backlog.md Status | Backlog.md Label       | Meaning                                                      |
|-----------------------|-------------------|------------------------|--------------------------------------------------------------|
| `IDEA`                | `todo`            | `idea`                 | Container not yet created; concept noted                     |
| `RAW`                 | `todo`            | `raw`                  | Container created, actively being explored, not yet stable   |
| `VALIDATED`           | `in-progress`     | `validated`            | Stable in the container; used consistently                   |
| `GRADUATION-CANDIDATE`| `in-progress`     | `graduation-candidate` | 2+ weeks daily use; config stabilized; runbook drafted       |
| `GRADUATING`          | `in-progress`     | `graduating`           | OpenSpec proposal raised; Docker stack in progress           |
| `PROMOTED`            | `done`            | `promoted`             | Docker Compose stack merged; Distrobox container retired     |
| `ABANDONED`           | `done`            | `abandoned`            | Experiment closed; not worth promoting; container removed    |

A container not worth promoting exits the lifecycle as `ABANDONED` (`Done` / `abandoned`):
move it to `experiments/backlog/completed/`, remove it from `/srv/experiments/`, and
record a brief reason in the task body.

---

## How to Create a New Experiment Entry

1. Create a new task file in `experiments/backlog/tasks/`:

   ```
   experiments/backlog/tasks/exp-NNN - <name>-<short-description>.md
   ```

   With the following content:

   ```markdown
   ---
   id: EXP-NNN
   title: <name> — <one-line description>
   status: To Do
   assignee: []
   created_date: 'YYYY-MM-DD'
   labels:
     - idea
   priority: medium
   ---

   ## Description

   <One-paragraph description of what this experiment is for.>

   ## Acceptance Criteria
   <!-- AC:BEGIN -->
   - [ ] #1 Daily use confirmed (≥ 2 weeks)
   - [ ] #2 Core dependencies, ports, and data paths stabilized
   - [ ] #3 Reboot persistence required
   - [ ] #4 Runbook stub drafted in docs/runbooks/
   <!-- AC:END -->
   ```

2. Create the Distrobox container on HAL-10k and record the creation command in
   `/srv/experiments/create.sh`.

3. Update the task `labels` from `idea` to `raw` once the container is running.

4. Commit the backlog update to the repo.

---

## Graduation Trigger

When all four checklist items in a task are checked **and** the container has been
in `GRADUATION-CANDIDATE` state for at least a week, run the following in the
provisioning repo:

```
/opsx:propose add-<name>-to-platform
```

This opens a new OpenSpec change to add the experiment as a Docker Compose service
in `compose/`. The Distrobox container is retired once the stack is deployed and
verified.

---

## Reference

- Architecture: [`docs/architecture/experimentation-layer.md`](../docs/architecture/experimentation-layer.md)
- Backlog tasks: [`experiments/backlog/tasks/`](./backlog/tasks/)
- OpenSpec workflow: [`WORKFLOW.md`](../WORKFLOW.md#experiment-tracking)
- ADR: [`docs/decisions/adr/ADR-0010-experiment-lifecycle-tracking-backlog-md.md`](../docs/decisions/adr/ADR-0010-experiment-lifecycle-tracking-backlog-md.md)
