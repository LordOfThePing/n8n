#!/usr/bin/env bash
# =============================================================================
# provision-tunnel.sh  (run on the server)
# One-time Cloudflare Tunnel + DNS setup for n8n.flynnpedroa.engineer.
#
# Creates the named tunnel via the Cloudflare API, adds the DNS route, and
# writes the tunnel credentials JSON into the cloudflared_cert docker volume.
#
# Requires: .env populated (copy .env.example -> .env), docker + compose, and
# an API token with Tunnel:Edit/Read + DNS:Edit on the flynnpedroa.engineer zone.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

# --- load .env (simple KEY=VALUE parse; no expansion weirdness) --------------
env_file=.env
[ -f "$env_file" ] || { echo "ERROR: deploy/.env missing (copy .env.example -> .env)" >&2; exit 1; }

get_var() {
  local key=$1 required="${2:-true}"
  local val
  val=$(grep -E "^${key}=" "$env_file" | head -n1 | cut -d= -f2- || true)
  if $required && [ -z "$val" ]; then
    echo "ERROR: missing $key in deploy/.env" >&2; exit 1
  fi
  printf '%s' "$val"
}

token=$(get_var CLOUDFLARE_API_TOKEN)
acct=$(get_var CLOUDFLARE_ACCOUNT_TAG)
zone=$(get_var CLOUDFLARE_ZONE_ID)
tname=$(get_var TUNNEL_NAME)
hostname=$(get_var TUNNEL_HOSTNAME)

vol="n8n-cloudflare_cloudflared_cert"
auth=(-H "Authorization: Bearer $token" -H "Content-Type: application/json")
base="https://api.cloudflare.com/client/v4"

echo "==> Looking for existing tunnel '$tname'..."
list=$(curl -sS "$base/accounts/$acct/cfd_tunnel?is_deleted=false" "${auth[@]}")
echo "$list" | grep -q '"success":false' && { echo "ERROR listing tunnels: $list" >&2; exit 1; }

tunnel_id=$(printf '%s' "$list" | grep -o "\"name\":\"$tname\"[^}]*\"id\":\"[^\"]*\"" | grep -o '[0-9a-f-]\{36\}' | head -n1)
secret=""

if [ -n "$tunnel_id" ]; then
  echo "Using existing tunnel $tunnel_id"
  if docker run --rm -v "$vol:/in" busybox sh -c "test -f /in/$tname.json" 2>/dev/null; then
    echo "Credentials already in volume - keeping them."
  else
    echo "WARNING: tunnel exists but credentials not in volume." >&2
    echo "The secret can't be read back from the API; regenerating below. Use" >&2
    echo "'cloudflared tunnel login' instead if you want to avoid regenerating." >&2
    secret=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
  fi
else
  echo "==> Creating tunnel '$tname'..."
  resp=$(curl -sS -X POST "$base/accounts/$acct/cfd_tunnel" "${auth[@]}" \
         -d "{\"name\":\"$tname\",\"config_src\":\"cloudflared\"}")
  echo "$resp" | grep -q '"success":false' && { echo "ERROR creating tunnel: $resp" >&2; exit 1; }
  tunnel_id=$(printf '%s' "$resp" | grep -o '"id":"[0-9a-f-]\{36\}"' | head -n1 | cut -d'"' -f4)
  secret=$(printf '%s' "$resp" | grep -o '"secret":"[^"]*"' | head -n1 | cut -d'"' -f4)
  echo "Created tunnel $tunnel_id"
fi

echo "==> Adding DNS route for $hostname..."
dns=$(curl -sS -X POST "$base/accounts/$acct/cfd_tunnel/$tunnel_id/dns" "${auth[@]}" \
      -d "{\"hostname\":\"$hostname\",\"service\":\"http://$hostname\"}")
echo "$dns" | grep -q '"success":false' && { echo "ERROR creating DNS route: $dns" >&2; exit 1; }

if [ -n "$secret" ]; then
  echo "==> Writing credentials into volume '$vol'..."
  creds="{\"AccountTag\":\"$acct\",\"TunnelID\":\"$tunnel_id\",\"TunnelName\":\"$tname\",\"Secret\":\"$secret\"}"
  docker run --rm -v "$vol:/out" busybox sh -c "mkdir -p /out && printf '%s' '$creds' > /out/$tname.json"
  echo "Credentials written."
fi

echo
echo "Done. Start the stack:"
echo "  docker compose --env-file deploy/.env up -d"
echo "Then open: https://$hostname"
