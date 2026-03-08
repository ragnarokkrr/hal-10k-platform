# ADR-0001: Secrets Management with SOPS + age

**Date**: 2026-03-08
**Status**: Accepted

---

## Context

The `hal-10k-platform` repository contains Docker Compose stacks that require sensitive
values: API keys, passwords, tokens. These must be available at deploy time on HAL-10k
but must never be committed in plaintext to git.

The platform is single-node, self-hosted, with no existing secret store (Vault, AWS
Secrets Manager, etc.).

## Decision

Use **SOPS** (Secrets OPerationS) with **age** as the encryption backend.

- All secret files committed to git use the naming convention `secrets/*.enc.yaml`
- Plaintext files live only in `/srv/platform/secrets/` (gitignored)
- Decryption is performed at deploy time via `scripts/secrets-decrypt.sh`
- The age private key is held per-engineer and backed up offline

## Consequences

**Positive**:
- No external secret store required
- Encrypted secrets are diff-friendly (SOPS encrypts values, not the whole file)
- Simple CLI workflow; integrates with existing git + shell toolchain
- age is modern, audited, and has no complex key management

**Negative**:
- Key rotation requires re-encrypting all secrets
- No automatic rotation or short-lived credentials
- Developer onboarding requires sharing the age public key or re-encrypting for each new key

## Alternatives Considered

| Alternative | Reason rejected |
|-------------|-----------------|
| HashiCorp Vault | Overkill for single-node; adds ops burden |
| git-crypt | AES-256, but symmetric key sharing is less ergonomic |
| Ansible Vault | Only viable if Ansible is adopted for automation |
| Plaintext .env files | Unacceptable; secrets would be committed to git |
