#!/usr/bin/env bash
# secrets-encrypt.sh — Encrypt a plaintext YAML file with SOPS into secrets/
#
# Usage: ./scripts/secrets-encrypt.sh <plaintext-file> [output-name]
#   plaintext-file: path to the plaintext YAML to encrypt
#   output-name:    base name for the output (default: basename of input without .yaml)
#
# The encrypted file is written to secrets/<output-name>.enc.yaml

set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/../secrets" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <plaintext-file> [output-name]" >&2
  exit 1
fi

PLAINTEXT="$1"
BASE="${2:-$(basename "$PLAINTEXT" .yaml)}"
OUT="$SECRETS_DIR/${BASE}.enc.yaml"

if [[ ! -f "$PLAINTEXT" ]]; then
  echo "ERROR: $PLAINTEXT not found" >&2
  exit 1
fi

echo "Encrypting $PLAINTEXT → $OUT"
sops --encrypt "$PLAINTEXT" > "$OUT"
echo "Done. Review and commit $OUT"
echo "REMINDER: Delete the plaintext file now."
