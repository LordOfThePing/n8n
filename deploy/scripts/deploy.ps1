# =============================================================================
# deploy.ps1 - start/stop/status helpers for the n8n + Cloudflare stack
# Usage:
#   ./scripts/deploy.ps1 up        # build + start all services (detached)
#   ./scripts/deploy.ps1 logs      # tail combined logs
#   ./scripts/deploy.ps1 logs N    # tail logs, follow
#   ./scripts/deploy.ps1 down      # stop and remove containers
#   ./scripts/deploy.ps1 status    # docker compose ps
# =============================================================================
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$envFile = Join-Path $root '.env'

if (-not (Test-Path $envFile)) {
    throw "Missing .env. Run: Copy-Item deploy/.env.example deploy/.env and fill it in."
}

$compose = { & docker compose --env-file $envFile @args }

switch ($args[0]) {
    'up'     { & $compose 'up' '-d'; break }
    'logs'   { & $compose 'logs' '-f' '--tail=100'; break }
    'down'   { & $compose 'down'; break }
    'status' { & $compose 'ps'; break }
    'restart' { & $compose 'restart'; break }
    default  {
        "Usage: deploy.ps1 {up|logs|down|status|restart}"
        exit 1
    }
}
