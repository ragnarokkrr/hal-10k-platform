# ADR-0003: Spec-Driven Development with OpenSpec

**Date**: 2026-03-09
**Status**: Accepted

---

## Context

The `hal-10k-platform` provisioning project uses Claude Code for infrastructure automation.
Without a lightweight spec layer, changes can drift from original intent, reviews become
ad-hoc, and there is no artifact trail of *why* a change was designed a certain way.

The project already uses `CLAUDE.md`, `AGENTS.md`, and runbooks to define conventions and
document procedures. What is missing is a per-change planning and review layer that:

- Persists intent across AI sessions
- Injects project context into Claude's planning automatically
- Produces reviewable, diffable, committable artifacts before any repo changes are made
- Reduces "AI rewrote half the repo" incidents by requiring a proposal step

Two candidates were evaluated: **Spec-Kit** and **OpenSpec** (by Fission AI).

## Decision

Adopt **[OpenSpec](https://github.com/Fission-AI/OpenSpec)** as the spec-driven development
(SDD) framework for `hal-10k-platform`, using the **core profile**
(`propose → apply → archive`).

OpenSpec is installed globally and integrated with Claude Code via `--tools claude-code`.
It adds a per-change folder structure under `openspec/changes/` without replacing any
existing conventions.

**What to use OpenSpec for:**

- New platform services
- Significant bootstrap changes
- Observability additions
- Backup/restore changes
- Security-impacting changes

**What NOT to use OpenSpec for:**

- Typo and documentation fixes
- One-line Compose edits
- Routine image version bumps

### Workflow per meaningful change

```
/opsx:propose   → define the change
review spec     → sanity-check before Claude touches anything
/opsx:apply     → generate/implement repo changes
manual validate → run bootstrap/compose checks
/opsx:archive   → close the change
```

One OpenSpec change corresponds to one operational change. Examples:
`add-traefik-internal-ingress`, `add-postgres-backup-restore`,
`baseline-grafana-prometheus-loki`, `move-docker-data-root-to-platform`.

### Repo shape after integration

```
hal-10k-platform/
  openspec/
    config.yaml       ← project context + rules (injected into every planning request)
    changes/          ← one folder per operational change
    schemas/          ← custom schemas (later)
  bootstrap/
  compose/
  docs/
  CLAUDE.md           ← unchanged; remains authoritative
  AGENTS.md           ← unchanged; remains authoritative
```

### `openspec/config.yaml` (initial)

```yaml
context: |
  Single-node AI lab on BOSGAME M5 running Pop!_OS 24.04.
  Platform services run in Docker Compose.
  Experiments run in Distrobox, not on the host.
  No secrets in git; use SOPS + age.
  Do not expose services to 0.0.0.0 unless explicitly documented.
  Every service must define healthchecks, named volumes, explicit ports, and restart policy.
  Every infrastructure change must update docs/services-catalog.md, docs/ports.md, and relevant runbooks.
  Create a new ADR if meaningful architectural changes are introduced.

rules:
  proposal: |
    State target outcome, rationale, risks, validation, rollback, and resource impact.
  design: |
    Include directory changes, compose impacts, networking, storage paths, and secret handling.
  tasks: |
    Break work into small reversible steps. Prefer smallest safe change first.
  specs: |
    Use precise operational language. Avoid vague success criteria.
```

> The `context` block is injected into every planning request — keep it concise.
> Bloated context degrades output quality.

### Custom schema (future, Phase 2+)

The default `spec-driven` schema is `proposal → specs → design → tasks → implement`.
A future custom schema for infrastructure changes will be:

```
proposal → design → tasks
```

Most infra changes do not need product-style specs — they need what/why/architecture
impact/execution steps. Custom schemas can be created or forked from built-in ones.

## Consequences

**Positive**:
- Per-change artifact trail (proposals, specs, design docs) — reviewable and diffable
- Project context is injected automatically into Claude planning, reducing context drift
- Proposals are first-class git artifacts; intent is preserved across sessions
- Aligns with the existing HAL-10k philosophy of structured, documented operations
- `CLAUDE.md` and `AGENTS.md` are preserved and remain authoritative; OpenSpec is additive

**Negative**:
- Extra workflow overhead for every meaningful change
- Risk of over-documenting trivial changes if the threshold is not respected
- Another layer to maintain; requires Node.js 20.19.0+ on the workstation
- Failure mode: using OpenSpec for everything → friction → abandoned

## Alternatives Considered

| Alternative | Reason rejected |
|-------------|-----------------|
| Spec-Kit | Less mature Claude Code integration; OpenSpec has native `/opsx:*` slash commands and explicit `--tools claude-code` init flag |
| No spec layer (status quo) | No artifact trail; intent drifts across sessions; ad-hoc reviews |
| Full Jira/Linear issue tracking | Overkill for a single-operator homelab platform |

## Installation

```bash
npm install -g @fission-ai/openspec@latest
openspec init --tools claude-code
```

Requires Node.js 20.19.0+.

## References

- [OpenSpec GitHub](https://github.com/Fission-AI/OpenSpec)
- Roadmap: Phase 2 — Spec-Kit / Open-Spec ADD Automation
