#!/usr/bin/env bash
# secrets-decrypt.sh — Decrypt all SOPS-encrypted secret files to /srv/platform/secrets/
#
# Usage: ./scripts/secrets-decrypt.sh [stack]
#   stack: optional; decrypt only secrets/<stack>.enc.yaml
#
# Prerequisites:
#   - SOPS_AGE_KEY_FILE env var set to age private key path
#   - sops binary in PATH

set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/../secrets" && pwd)"
RUNTIME_DIR="/srv/platform/secrets"

if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
  echo "ERROR: SOPS_AGE_KEY_FILE is not set." >&2
  echo "  export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt" >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

if [[ $# -ge 1 ]]; then
  FILES=("$SECRETS_DIR/$1.enc.yaml")
else
  mapfile -t FILES < <(find "$SECRETS_DIR" -name "*.enc.yaml" | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No encrypted secret files found in $SECRETS_DIR"
  exit 0
fi

for enc_file in "${FILES[@]}"; do
  [[ -f "$enc_file" ]] || { echo "WARN: $enc_file not found, skipping"; continue; }
  base="$(basename "$enc_file" .enc.yaml)"
  out="$RUNTIME_DIR/$base.yaml"
  echo "Decrypting: $enc_file → $out"
  sops --decrypt "$enc_file" > "$out"
  chmod 600 "$out"
done

echo "Done. Secrets written to $RUNTIME_DIR"
