# WORKFLOW.md — Development & Deployment Workflow

This document describes how to develop infrastructure changes in `hal-10k-platform` and
deploy them to the runtime environment (HAL-10k / `/srv/platform`).

---

## Environments

| Environment | Host | Platform Root | Notes |
|-------------|------|---------------|-------|
| **production** | HAL-10k (BOSGAME M5) | `/srv/platform` | Single-node; no staging tier yet |

> Until a staging environment exists, test changes locally with `docker compose config`
> and `--dry-run` where supported before deploying to production.

---

## Repository Clone Location (on HAL-10k)

```
/srv/platform/repos/hal-10k-platform/
```

All compose stacks reference paths relative to `/srv/platform/` using absolute paths or
Docker named volumes. Symlinks from `/srv/platform/compose/<stack>/` to the repo are
**not** used; instead, stacks are run directly from the repo working directory.

---

## Local Development (on your workstation)

### 1. Clone & branch

```bash
git clone git@github.com:ragnarokkrr/hal-10k-platform.git
cd hal-10k-platform
git checkout -b feat/my-change
```

### 2. Edit

- Compose changes: edit files under `compose/<stack>/`
- Runbook changes: edit files under `bootstrap/` or `docs/runbooks/`
- New secret reference: add variable to `secrets/<stack>.env.example`; never add plaintext

### 3. Validate locally

```bash
# Lint compose files (requires docker)
docker compose -f compose/core/docker-compose.yml config --quiet

# Lint shell scripts (requires shellcheck)
shellcheck scripts/*.sh bootstrap/**/*.sh

# Dry-run secrets encryption
sops --encrypt secrets/example.yaml   # (after age key is configured)
```

### 4. Commit & push

```bash
git add compose/ docs/ scripts/ bootstrap/
git commit -m "feat: describe the change"
git push origin feat/my-change
```

Open a pull request on GitHub. Review, then merge to `main`.

---

## Deployment (on HAL-10k)

### Pull latest

```bash
cd /srv/platform/repos/hal-10k-platform
git pull origin main
```

### Decrypt secrets

```bash
./scripts/secrets-decrypt.sh        # outputs to /srv/platform/secrets/ (gitignored)
```

### Deploy / update a stack

```bash
# Core (Traefik)
cd compose/core
docker compose pull
docker compose up -d

# AI stack
cd ../ai
docker compose pull
docker compose up -d
```

### Verify

```bash
docker compose ps
docker compose logs --tail=50
```

### Rollback

```bash
# Roll back the git repo
git log --oneline -10
git checkout <previous-sha> -- compose/core/docker-compose.yml

# Re-deploy
docker compose up -d
```

---

## Secret Management

### One-time setup (per engineer)

```bash
# Generate your age key (save the private key securely)
age-keygen -o ~/.config/sops/age/keys.txt

# Add your public key to .sops.yaml creation_rules
```

### Encrypting a new secret file

```bash
sops --encrypt --age <public-key> secrets/my-stack.yaml > secrets/my-stack.enc.yaml
git add secrets/my-stack.enc.yaml
```

### Decrypting at deploy time

```bash
sops --decrypt secrets/my-stack.enc.yaml > /srv/platform/secrets/my-stack.yaml
```

Decrypted files live **only** in `/srv/platform/secrets/` which is excluded from git.

---

## Adding a New Service

1. Create `compose/<stack>/docker-compose.yml` and `.env.example`
2. Write the runbook in `docs/runbooks/<stack>.md` (use template)
3. Add SOPS-encrypted secrets if needed: `secrets/<stack>.enc.yaml`
4. Update `README.md` service inventory table
5. Record the decision in an ADR if the service involves a significant architectural choice
6. Open PR → merge → deploy

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production-ready; deployed to HAL-10k |
| `feat/*` | Feature / service additions |
| `fix/*` | Bug fixes and corrections |
| `docs/*` | Documentation-only changes |
| `runbook/*` | Runbook additions |

---

## OpenSpec Change Workflow

Infrastructure changes follow a spec-driven `propose → apply → archive` cycle powered by
**[OpenSpec](https://github.com/Fission-AI/OpenSpec)**. Change artifacts live under
`openspec/changes/` and are committed alongside code.

```
/opsx:propose   → define the change (proposal, design, tasks)
review spec     → sanity-check before any repo files are modified
/opsx:apply     → implement repo changes
manual validate → run bootstrap / compose checks
/opsx:archive   → close the change
```

See [ADR-0003](docs/decisions/adr/ADR-0003-spec-driven-development-openspec.md) and
the [README](README.md#spec-driven-development) for full details.

---

## Experiment Tracking

Distrobox containers in the Experimentation Layer (`/srv/experiments/`) are tracked
using **[Backlog.md](https://github.com/MrLesk/Backlog.md)** at `experiments/backlog/`.
Each container has one task entry that moves through six lifecycle states — from initial
`IDEA` through active experimentation to `PROMOTED` (a Docker Compose service) or
closed as cancelled. This gives the provisioning repo a version-controlled record of
what is being explored, what is stable, and what has graduated to the Platform Layer,
without requiring any external issue tracker.

### Lifecycle State → Backlog.md Mapping

| Lifecycle State        | status       | label                  | Meaning                                                    |
|------------------------|--------------|------------------------|------------------------------------------------------------|
| `IDEA`                 | `todo`       | `idea`                 | Container not yet created; concept noted                   |
| `RAW`                  | `todo`       | `raw`                  | Container created, active exploration, not yet stable      |
| `VALIDATED`            | `in-progress`| `validated`            | Stable in container; used consistently                     |
| `GRADUATION-CANDIDATE` | `in-progress`| `graduation-candidate` | 2+ weeks daily use; config stabilized; runbook drafted     |
| `GRADUATING`           | `in-progress`| `graduating`           | OpenSpec proposal raised; Docker stack in progress         |
| `PROMOTED`             | `done`       | `promoted`             | Docker Compose stack merged; Distrobox container retired   |
| `ABANDONED`            | `done`       | `abandoned`            | Experiment closed; not worth promoting; container removed  |

### Graduation → OpenSpec Handoff

When all four graduation checklist items in a task are checked and the container has
been in `GRADUATION-CANDIDATE` state for at least one week, trigger an OpenSpec change:

```
/opsx:propose add-<container-name>-to-platform
```

This opens a new spec-driven change to add the experiment as a Docker Compose service
under `compose/`. The Distrobox container is retired once the new stack is deployed and
verified. See `experiments/README.md` for full details.
