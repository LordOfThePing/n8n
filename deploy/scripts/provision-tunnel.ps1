# =============================================================================
# provision-tunnel.ps1
# One-time Cloudflare Tunnel + DNS setup for n8n.flynnpedroa.engineer.
#
# Creates the named tunnel via the Cloudflare API and adds the DNS route that
# publishes TUNNEL_HOSTNAME to it. Writes the tunnel credentials JSON into the
# docker volume cloudflared_cert so the cloudflared service can start.
#
# Requires: .env populated (copy .env.example -> .env), docker, and an API
# token with Tunnel:Edit/Read + DNS:Edit on the flynnpedroa.engineer zone.
# =============================================================================

$ErrorActionPreference = 'Stop'

function Get-EnvVar([string]$name, [bool]$required = $true) {
    $val = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($val)) {
        # Fall back to the .env file next to this script (docker compose --env-file semantics).
        $envFile = Join-Path $PSScriptRoot '../.env'
        if (Test-Path $envFile) {
            $line = Get-Content $envFile | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
            if ($line) { $val = ($line -split '=', 2)[1] }
        }
    }
    if ($required -and [string]::IsNullOrWhiteSpace($val)) {
        throw "Missing required var: $name. Set it in deploy/.env (copy .env.example)."
    }
    return $val
}

$token        = Get-EnvVar 'CLOUDFLARE_API_TOKEN'
$accountTag   = Get-EnvVar 'CLOUDFLARE_ACCOUNT_TAG'
$zoneId       = Get-EnvVar 'CLOUDFLARE_ZONE_ID'
$tunnelName   = Get-EnvVar 'TUNNEL_NAME'
$hostname     = Get-EnvVar 'TUNNEL_HOSTNAME'

$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$base    = 'https://api.cloudflare.com/client/v4'

Write-Host '==> Looking for an existing tunnel with this name...'
$list = Invoke-RestMethod -Method Get -Uri "$base/accounts/$accountTag/cfd_tunnel?is_deleted=false" -Headers $headers
if (-not $list.success) { throw "Failed to list tunnels: $($list.errors | ConvertTo-Json -Compress)" }

# Try to find a matching tunnel by name.
$existing = @($list.result) | Where-Object { $_.name -eq $tunnelName } | Select-Object -First 1

$tunnelId = $null
$secret   = $null
$isNew    = $false

if ($existing) {
    Write-Host "Using existing tunnel: $($existing.name) ($($existing.id))"
    $tunnelId = $existing.id
    # If credentials are already in the volume, do not overwrite them: a fresh
    # random secret here would disagree with the file cloudflared is already using.
    $volumeName = 'n8n-cloudflare_cloudflared_cert'
    $probe = & docker run --rm -v "${volumeName}:/in" busybox sh -c "test -f /in/$tunnelName.json && echo present || echo absent" 2>$null
    if ($probe.Trim() -eq 'present') {
        Write-Host "Credentials already exist in volume '$volumeName' - keeping them."
    } else {
        Write-Warning (@'
Tunnel already exists but its credentials file is not in the volume. The secret
cannot be read back from the Cloudflare API. The tunnel will be regenerated with
a fresh secret below; note this must stay stable across restarts. If you only
need the fixed hostname, use `cloudflared tunnel login` instead to avoid
regenerating.
'@)
        $secret = (New-Guid).ToString().Replace('-', '')
    }
} else {
    Write-Host "Creating tunnel '$tunnelName'..."
    $body = @{ name = $tunnelName; config_src = 'cloudflared' } | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Method Post -Uri "$base/accounts/$accountTag/cfd_tunnel" -Headers $headers -Body $body
    if (-not $resp.success) { throw "Failed to create tunnel: $($resp.errors | ConvertTo-Json -Compress)" }
    $tunnelId = $resp.result.id
    $secret   = $resp.result.credentials_file.secret
    $isNew    = $true
    Write-Host "Created tunnel: $tunnelId"
}

# ---- DNS route ---------------------------------------------------------------
Write-Host "==> Adding DNS route for $hostname..."
$dnsBody = @{ hostname = $hostname; service = "http://$hostname" } | ConvertTo-Json -Compress
$dnsResp = Invoke-RestMethod -Method Post -Uri "$base/accounts/$accountTag/cfd_tunnel/$tunnelId/dns" -Headers $headers -Body $dnsBody
if (-not $dnsResp.success) {
    throw "Failed to create DNS route: $($dnsResp.errors | ConvertTo-Json -Compress)"
}
Write-Host "DNS route created: $($dnsResp.result.hostname)"

# ---- Write credentials into the docker volume (only when we have a fresh one) -
if ($secret) {
    Write-Host '==> Writing tunnel credentials into cloudflared_cert volume...'
    $creds = @{
        AccountTag = $accountTag
        TunnelID   = $tunnelId
        TunnelName = $tunnelName
        Secret     = $secret
    }
    $secretJson = $creds | ConvertTo-Json -Compress
    $volumeName = 'n8n-cloudflare_cloudflared_cert'
    # Ensure the volume exists, then drop the credentials file in place.
    & docker run --rm -v "${volumeName}:/out" busybox sh -c "mkdir -p /out && printf '%s' `"$secretJson`" > /out/$tunnelName.json" 2>&1 | Select-Object -Last 5
    Write-Host "Credentials written to '/home/nonroot/.cloudflared/$tunnelName.json'."
} else {
    Write-Host 'No new credentials to write (existing tunnel credentials are already in place).'
}

Write-Host ''
Write-Host 'Done. Start the stack with:'
Write-Host "  docker compose --env-file deploy/.env up -d"
Write-Host "Then open: https://$hostname"
