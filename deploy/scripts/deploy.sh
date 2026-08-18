#!/usr/bin/env bash
# =============================================================================
# deploy.sh  (run on the server)
# Pull the referenced images and manage the n8n + Cloudflare Tunnel stack.
#
#   ./scripts/deploy.sh pull    # docker compose pull (official n8nio/n8n image)
#   ./scripts/deploy.sh up      # pull + start services detached
#   ./scripts/deploy.sh logs    # follow logs
#   ./scripts/deploy.sh down    # stop and remove containers
#   ./scripts/deploy.sh status  # docker compose ps
#   ./scripts/deploy.sh restart
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

root=$(pwd)
env_file="$root/.env"
[ -f "$env_file" ] || { echo "ERROR: deploy/.env missing (copy .env.example -> .env)" >&2; exit 1; }

cmd=${1:-up}
shift || true

case "$cmd" in
  pull)   docker compose --env-file "$env_file" pull "$@";;
  up)     docker compose --env-file "$env_file" up -d "$@";;
  logs)   docker compose --env-file "$env_file" logs -f --tail=100 "$@";;
  down)   docker compose --env-file "$env_file" down "$@";;
  status) docker compose --env-file "$env_file" ps "$@";;
  restart)docker compose --env-file "$env_file" restart "$@";;
  *)
    echo "Usage: deploy.sh {pull|up|logs|down|status|restart} [-- extra args]"
    exit 1;;
esac
