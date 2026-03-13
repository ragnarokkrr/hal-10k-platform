#!/usr/bin/env bash
# create-traefik-network.sh — Idempotently create the shared traefik Docker network.
#
# The traefik network MUST exist before any stack that depends on Traefik routing
# is brought up. This script is safe to run multiple times.
#
# Usage: ./scripts/create-traefik-network.sh

set -euo pipefail

NETWORK_NAME="traefik"

if docker network inspect "$NETWORK_NAME" > /dev/null 2>&1; then
  echo "Network '$NETWORK_NAME' already exists — nothing to do."
else
  docker network create "$NETWORK_NAME"
  echo "Network '$NETWORK_NAME' created."
fi
