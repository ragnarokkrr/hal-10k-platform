# Runbook: Core Traefik Stack

**Stack**: `compose/core`
**Image**: `traefik:v3.3`
**Related ADR**: [ADR-0004-reverse-proxy-traefik.md](../decisions/adr/ADR-0004-reverse-proxy-traefik.md)

---

## Overview

Traefik is the single HTTP/HTTPS ingress for the HAL-10k platform. It must be the
**first stack up** and the **last stack down**. All other stacks that need external
access attach to the `traefik` Docker network and advertise themselves via labels.

---

## Prerequisites

Ensure the following are in place before starting the stack:

- [ ] Docker CE installed and running (`docker info`)
- [ ] `SOPS_AGE_KEY_FILE` env var pointing to the age private key
  ```bash
  export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
  ```
- [ ] Working directory is the repo root:
  ```bash
  cd /srv/platform/repos/hal-10k-platform
  ```

---

## Deployment

### Step 1 — Create the `traefik` Docker network

```bash
./scripts/create-traefik-network.sh
```

Verify:
```bash
docker network ls | grep traefik
```

Expected output:
```
<id>   traefik   bridge   local
```

### Step 2 — Decrypt secrets

```bash
./scripts/secrets-decrypt.sh core
```

Verify:
```bash
ls -la /srv/platform/secrets/core.yaml
```

Expected: file exists, mode `600`.

### Step 3 — Extract TLS certificate and key

The TLS cert and key are stored as base64-encoded values in `core.yaml`. Extract them
to PEM files that Traefik can mount:

```bash
# Source the decrypted env file (YAML key=value format)
eval "$(grep -E '^TRAEFIK_TLS_(CERT|KEY)' /srv/platform/secrets/core.yaml | \
  sed 's/: /=/')"

echo "$TRAEFIK_TLS_CERT" | base64 -d > /srv/platform/secrets/hal-local.crt
echo "$TRAEFIK_TLS_KEY"  | base64 -d > /srv/platform/secrets/hal-local.key
chmod 600 /srv/platform/secrets/hal-local.crt /srv/platform/secrets/hal-local.key
```

Verify:
```bash
openssl x509 -noout -subject -dates -in /srv/platform/secrets/hal-local.crt
```

Expected: subject shows `CN=*.hal.local`, dates span 10 years from creation.

### Step 4 — Start the stack

```bash
docker compose -f compose/core/docker-compose.yml up -d
```

Verify the container is healthy:
```bash
docker compose -f compose/core/docker-compose.yml ps
```

Expected: `traefik` container shows `healthy` status. Allow up to 30 seconds for
the healthcheck to pass.

### Step 5 — Verify dashboard access

Open a browser and navigate to:
```
http://hal-10k.local:8080/dashboard/
```

You will be prompted for credentials:
- **Username**: `admin`
- **Password**: set during secrets generation (default used during bootstrap: `hal10k-admin`)

Expected: Traefik dashboard loads showing registered routers and services.

---

## TLS Certificate Generation

Run this once to regenerate the self-signed wildcard cert (e.g., after expiry or key
rotation). The cert is valid for 10 years by default.

```bash
openssl req -x509 -newkey rsa:4096 \
  -keyout /tmp/hal-local.key \
  -out    /tmp/hal-local.crt \
  -days 3650 -nodes \
  -subj "/CN=*.hal.local/O=HAL-10k/C=US" \
  -addext "subjectAltName=DNS:*.hal.local,DNS:hal.local"
```

After generation, re-encrypt into secrets:
```bash
# See scripts/secrets-encrypt.sh for the full re-encryption workflow
TLS_CERT=$(base64 -w0 /tmp/hal-local.crt)
TLS_KEY=$(base64 -w0  /tmp/hal-local.key)
# Update secrets/core.enc.yaml via sops --encrypt --in-place
rm /tmp/hal-local.crt /tmp/hal-local.key
```

---

## Label Convention for Downstream Stacks

Every service that needs Traefik routing must:

1. Attach to the `traefik` external network
2. Carry the following labels (adjust per service):

```yaml
services:
  myservice:
    # ...
    networks:
      - traefik
      - default         # keep internal stack network for service-to-service comms
    labels:
      - "traefik.enable=true"
      # HTTP router (redirects to HTTPS via middleware)
      - "traefik.http.routers.myservice.rule=Host(`myservice.hal.local`)"
      - "traefik.http.routers.myservice.entrypoints=web"
      - "traefik.http.routers.myservice.middlewares=redirect-to-https@file"
      # HTTPS router
      - "traefik.http.routers.myservice-secure.rule=Host(`myservice.hal.local`)"
      - "traefik.http.routers.myservice-secure.entrypoints=websecure"
      - "traefik.http.routers.myservice-secure.tls=true"
      - "traefik.http.services.myservice.loadbalancer.server.port=<container-port>"

networks:
  traefik:
    external: true
  default: {}
```

Hostname convention: `<service>.hal.local` (wildcard TLS covers all subdomains).

---

## Operations

### View logs

```bash
docker compose -f compose/core/docker-compose.yml logs -f
```

### Reload dynamic config

Dynamic config (`compose/core/config/dynamic/`) is watched automatically (`watch: true`).
Edit any file under `dynamic/` and Traefik will reload it within seconds — no restart
needed.

### Restart the stack

```bash
docker compose -f compose/core/docker-compose.yml restart
```

### Update the image

```bash
docker compose -f compose/core/docker-compose.yml pull
docker compose -f compose/core/docker-compose.yml up -d
```

---

## Rollback

```bash
docker compose -f compose/core/docker-compose.yml down
```

All other stacks fall back to direct `hal-10k.local:<port>` access automatically.
The `traefik` network and secrets are left in place for re-deployment.

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Container exits immediately | `docker compose -f compose/core/docker-compose.yml logs` — often a missing volume or env_file |
| Dashboard returns 401 | Verify `TRAEFIK_DASHBOARD_AUTH` in `/srv/platform/secrets/core.yaml` is in `user:hash` htpasswd format |
| TLS cert not loaded | Verify `/srv/platform/secrets/hal-local.crt` and `.key` exist (Step 3 above) |
| Service not routed | Check `traefik.enable=true` label is present and service is on the `traefik` network |
| `traefik` network missing | Run `./scripts/create-traefik-network.sh` |
