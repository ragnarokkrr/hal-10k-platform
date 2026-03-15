# No changes to traefik-core-proxy requirements in this phase.
#
# Original design (D1) proposed that compose/core/ would create the ai_internal network.
# During implementation, this was revised (Option B): compose/ai/ owns ai_internal
# with `name: ai_internal`, and compose/proxy/ references it as external.
# compose/core/docker-compose.yml was not modified.
