# Runbook: Secrets Management — SOPS + age

**Phase**: bootstrap/06 — secrets-sops-age
**Status**: Ready
**Last verified**: —
**Performed by**: —

---

## Purpose

Install SOPS and age, generate an age keypair for the `hal-10k-platform` repository,
and establish the secrets management workflow. After this phase, all sensitive values
(API keys, passwords, tokens) are encrypted at rest using SOPS + age before being
committed to git.

---

## Prerequisites

- [ ] Phase 05 (Docker) complete
- [ ] Git repository cloned to `/srv/platform/repos/hal-10k-platform`
- [ ] `golang` or pre-built binaries available (internet required)

---

## Procedure

### Step 1 — Install age

```bash
# Via apt (Ubuntu 24.04 ships age)
sudo apt install -y age

# Verify
age --version
# Expected: v1.x.x
```

### Step 2 — Install SOPS

```bash
# Download latest SOPS binary (check https://github.com/getsops/sops/releases)
SOPS_VERSION=3.9.1
curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
  -o /tmp/sops
sudo install /tmp/sops /usr/local/bin/sops

# Verify
sops --version
# Expected: sops 3.9.x ...
```

### Step 3 — Generate age Keypair

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Display the public key (copy it — needed for .sops.yaml)
cat ~/.config/sops/age/keys.txt | grep "# public key"
```

> **CRITICAL**: Back up `~/.config/sops/age/keys.txt` to a secure offline location
> (password manager, encrypted USB). Loss of this file means permanent loss of access
> to all encrypted secrets in this repository.

### Step 4 — Configure SOPS in the Repository

Edit `hal-10k-platform/.sops.yaml`:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Replace `age1xxx...` with your actual public key from Step 3.

```bash
cd /srv/platform/repos/hal-10k-platform
git add .sops.yaml
git commit -m "chore: add SOPS age encryption config"
```

### Step 5 — Set the SOPS_AGE_KEY_FILE Environment Variable

Add to `~/.zshrc` (or `~/.bashrc`):

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

```bash
source ~/.zshrc
```

### Step 6 — Create and Encrypt Your First Secret File

```bash
cd /srv/platform/repos/hal-10k-platform

# Create plaintext (never commit this)
cat > /tmp/test-secret.yaml <<'EOF'
example_password: "changeme123"
example_api_key: "sk-test-xxxx"
EOF

# Encrypt with SOPS
sops --encrypt /tmp/test-secret.yaml > secrets/test.enc.yaml
rm /tmp/test-secret.yaml

# Verify encryption
cat secrets/test.enc.yaml
# Expected: SOPS-encrypted YAML with ENC[] values
```

### Step 7 — Test Decryption

```bash
sops --decrypt secrets/test.enc.yaml
# Expected: plaintext YAML with original values
```

### Step 8 — Configure Decryption Scripts

```bash
# Create runtime secrets directory (gitignored)
mkdir -p /srv/platform/secrets

# Test decrypt script
./scripts/secrets-decrypt.sh
```

---

## .gitignore Additions

Ensure these patterns exist in the repository's `.gitignore`:

```gitignore
# Secrets (plaintext — never commit)
secrets/*.yaml
!secrets/*.enc.yaml
/srv/platform/secrets/
*.env
!*.env.example
.age-key*
```

---

## Key Backup Checklist

Before proceeding to Phase 1:

- [ ] age private key backed up to password manager
- [ ] age public key recorded in `.sops.yaml`
- [ ] `SOPS_AGE_KEY_FILE` set in shell profile
- [ ] Test encrypt + decrypt cycle successful
- [ ] `.gitignore` updated to exclude plaintext secrets

---

## Rollback

SOPS/age are additive tools. To stop using them:

1. Decrypt all `secrets/*.enc.yaml` files
2. Remove SOPS binaries: `sudo rm /usr/local/bin/sops`
3. Remove `.sops.yaml` from the repository

Encrypted files remain readable as long as the age key is available.

---

## Sources

- SOPS project: https://github.com/getsops/sops
- age project: https://github.com/FiloSottile/age
- Inspired by: `m5-platform/PROJECT_CONTEXT.md` secrets management pattern
- Tags: `homelab/bosgame-m5-ai`, `homelab/hal-10k`, `devops/security`
