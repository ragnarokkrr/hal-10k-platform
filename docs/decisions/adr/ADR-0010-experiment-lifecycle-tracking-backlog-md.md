# ADR-0010: Experiment Lifecycle Tracking with Backlog.md

**Date**: 2026-03-14
**Status**: Accepted

---

## Context

The HAL-10k platform has a formal two-layer architecture: a stable Platform Layer
(Docker Compose, `/srv/platform`) and a disposable Experimentation Layer (Distrobox,
`/srv/experiments/`). The Experimentation Layer architecture is documented in
`docs/architecture/experimentation-layer.md`, including six lifecycle states from
`IDEA` through `PROMOTED` and four explicit graduation criteria.

No tooling existed to track which containers are in which state. Without tracking:

- It is not clear which experiments have met graduation criteria and should move to the
  Platform Layer.
- There is no version-controlled record of what has been explored, abandoned, or promoted.
- The graduation gating ("2 weeks daily use, config stabilized, runbook drafted") exists
  only as prose in the architecture doc — it is not enforced or visible.
- There is no trigger to open a spec-driven change when an experiment is graduation-ready.

## Decision

Track Distrobox experiment lifecycle using **[Backlog.md](https://github.com/MrLesk/Backlog.md)**
with the project rooted at `experiments/backlog/` inside the provisioning repo.

### Storage structure

Backlog.md stores one Markdown file per task. The on-disk layout after `backlog init`:

```
experiments/
└── backlog/
    ├── config.yml              # Project config: statuses, labels, task prefix
    ├── tasks/                  # Active tasks — one file per container
    │   └── exp-NNN - <title>.md
    ├── drafts/                 # Pre-promotion drafts
    └── completed/              # Closed / retired tasks
```

Each task file carries YAML front matter (`id`, `title`, `status`, `labels`,
`created_date`, `priority`) and a Markdown body with Description and Acceptance Criteria
sections. There is no single-file mode in Backlog.md — the directory-of-files layout
is the only supported format.

### Label taxonomy

The six lifecycle states map to a Backlog.md `status` + `label` pair:

| Lifecycle State        | status       | label                  | Meaning                                                    |
|------------------------|--------------|------------------------|------------------------------------------------------------|
| `IDEA`                 | `To Do`      | `idea`                 | Container not yet created; concept noted                   |
| `RAW`                  | `To Do`      | `raw`                  | Container created, active exploration, not yet stable      |
| `VALIDATED`            | `In Progress`| `validated`            | Stable in container; used consistently                     |
| `GRADUATION-CANDIDATE` | `In Progress`| `graduation-candidate` | 2+ weeks daily use; config stabilized; runbook drafted     |
| `GRADUATING`           | `In Progress`| `graduating`           | OpenSpec proposal raised; Docker stack in progress         |
| `PROMOTED`             | `Done`       | `promoted`             | Docker Compose stack merged; Distrobox container retired   |
| `ABANDONED`            | `Done`       | `abandoned`            | Experiment closed; not worth promoting; container removed  |

### Acceptance criteria (graduation checklist)

Every task file includes the same four Acceptance Criteria items:

1. Daily use confirmed (≥ 2 weeks)
2. Core dependencies, ports, and data paths stabilized
3. Reboot persistence required
4. Runbook stub drafted in `docs/runbooks/`

When all four are checked and the container has been in `GRADUATION-CANDIDATE` for at
least one week, trigger the OpenSpec handoff:

```
/opsx:propose add-<name>-to-platform
```

### Seed state

The five standard containers are seeded as task files (`EXP-001` through `EXP-005`),
all in `To Do` / `idea` state:
`ml-lab`, `llama-build`, `agents-dev`, `ragna-ml`, `torch-nightly`.

## Rationale

- **Repo-native** — experiment state is version-controlled alongside the compose stacks
  it may graduate into; no external tool or auth required.
- **CLI-queryable** — `backlog list --label graduation-candidate` surfaces all
  graduation-ready containers without manual grep.
- **Proper Backlog.md format** — the `experiments/backlog/` directory layout matches
  exactly what the Backlog.md CLI creates and manages; no custom format or shim needed.
- **Lifecycle alignment** — Backlog.md's `status` + `label` model maps cleanly onto the
  six lifecycle states already defined in the architecture document.
- **Graduation gating** — the four Acceptance Criteria items turn the prose graduation
  criteria into machine-visible, checkable gates visible in `git diff`.
- **OpenSpec integration** — the `GRADUATING` label and the `/opsx:propose` trigger create
  a clean handoff between informal experiment tracking and the spec-driven change workflow.

## Alternatives Considered

| Alternative | Reason rejected |
|-------------|-----------------|
| GitHub Issues | External to the repo; requires GitHub auth on HAL-10k; state is not version-controlled alongside compose stacks; no offline access |
| `vault/Tasks/` (Obsidian / plain tasks) | Wrong scope — personal knowledge management, not infrastructure provisioning; no CLI query; not colocated with the repo |
| Plain README in `experiments/` | No structured lifecycle states; no label taxonomy; no CLI-queryable status; graduation criteria remain prose with no visible gate |
| Full project management tool (Linear, Jira) | Overkill for a single-operator homelab; external dependency; no repo integration |

## Consequences

**Positive**:
- Experiment lifecycle state is version-controlled and `git diff`-visible at the
  per-container granularity.
- Graduation from Distrobox to Docker Compose is explicitly gated by four checkboxes —
  no experiment promotes silently or informally.
- The `GRADUATING` state creates a clean handoff to OpenSpec; each Platform Layer addition
  begins as a documented experiment rather than an ad-hoc request.
- The `experiments/backlog/` layout is fully managed by the Backlog.md CLI with no
  custom format shims.

**Negative**:
- Backlog.md CLI must be installed separately (`npm install -g`); it is not a system package.
- Manual discipline required to keep task status and labels updated after each work session.
- The `experiments/backlog/` sub-directory adds one level of nesting relative to the repo
  root; this is the required Backlog.md layout and cannot be flattened.

## Installation

```bash
# Verify the current npm package name against the Backlog.md GitHub README before running
npm install -g @mrleskbacklog/backlog.md

# Bootstrap non-interactively from the repo root.
# --defaults preserves the pre-seeded config.yml and task files on re-init;
# --task-prefix exp ensures the glob scan finds exp-*.md files if config is absent;
# --integration-mode none skips the AI/MCP setup wizard.
cd experiments
backlog init "HAL-10k Experiments" --defaults --task-prefix exp --integration-mode none
```

The pre-seeded task files (`exp-001` through `exp-005`) are picked up automatically
after init — Backlog.md has no import step; it scans `backlog/tasks/exp-*.md` on every
command. The next `backlog task create` will produce `EXP-006`.

**Do not run `backlog init` interactively** (without `--defaults`) against this repo —
the interactive wizard will overwrite `backlog/config.yml` with a fresh config that may
drop the custom statuses and label taxonomy defined above.

## References

- Experimentation Layer Architecture: `docs/architecture/experimentation-layer.md`
- Backlog project: `experiments/backlog/`
- Lifecycle and graduation docs: `experiments/README.md`
- Experiment Tracking workflow: `WORKFLOW.md#experiment-tracking`
- Roadmap: Phase 6.5 — Experiment Lifecycle Tracking (Backlog.md)
- [Backlog.md project](https://github.com/MrLesk/Backlog.md)
