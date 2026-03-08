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

## Spec-Kit / Open-Spec ADD Integration (Planned)

Future automation of Docker Compose stack generation will be driven by **Spec-Kit** or
**Open-Spec ADD** specifications. When that pipeline is in place:

1. Author a service spec in `specs/<stack>.add.yaml`
2. Run `spec-kit generate compose specs/<stack>.add.yaml` → outputs `compose/<stack>/`
3. Review generated output, adjust, commit

See ROADMAP.md Phase 5 for details.
