# n8n behind a Cloudflare Tunnel

Exposes the full n8n instance — editor UI **and** public REST API — at:

> **https://n8n.flynnpedroa.engineer**

The stack runs two containers on the same Docker network:

| Service      | Image                              | Purpose                                       |
| ------------ | ---------------------------------- | --------------------------------------------- |
| `n8n`        | `docker.io/n8nio/n8n:latest`       | The n8n workflow automation backend + UI      |
| `cloudflared`| `cloudflare/cloudflared:latest`    | Named Cloudflare Tunnel that publishes the hostname |

n8n is bound to `127.0.0.1:5678` only; it is **not** published on the public
interface. Cloudflared reaches it over the internal Compose network, so inbound
requests never touch a machine-exposed port.

> **No custom image required.** This stack uses the official `n8nio/n8n` image
> pulled from Docker Hub. Nothing is built or pushed from your PC — only the
> `.env` configuration needs to land on the server. The server `docker compose`
> pulls the image directly.

## Files

```
deploy/
├── docker-compose.yml          # n8n + cloudflared stack (uses official image)
├── .env.example                # environment template (copy to .env)
├── cloudflared/
│   └── config.yml              # tunnel routing -> http://n8n:5678
└── scripts/
    ├── provision-tunnel.sh     # (server) one-time tunnel + DNS setup
    ├── deploy.sh               # (server) pull / up / logs / down / status
    ├── provision-tunnel.ps1    # (PC, optional) same as .sh for Windows
    └── deploy.ps1              # (PC, optional) Windows helpers
```

## Prerequisites

- Docker + Docker Compose v2.
- A Cloudflare API token with these permissions on the **flynnpedroa.engineer**
  zone:
  - Account → Cloudflare Tunnel → **Edit & Read**
  - Zone → DNS → **Edit**
  - Zone → Zone → **Read**
  Create it at <https://dash.cloudflare.com/profile/api-tokens>.
- Your Cloudflare account tag and the zone id.
  - Account tag: shown in the dashboard URL (`dash.cloudflare.com/<account>`).
  - Zone id: dashboard → `flynnpedroa.engineer` → Overview → *API* → *Zone ID*.

## Setup — one time (on the server)

```bash
cd deploy
cp .env.example .env               # then edit .env and fill in the values:
#   CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_TAG, CLOUDFLARE_ZONE_ID
#   N8N_ENCRYPTION_KEY             (openssl rand -hex 24)

# (optional) make helpers executable
chmod +x scripts/*.sh

# Creates the tunnel + DNS record and writes credentials into a docker volume:
./scripts/provision-tunnel.sh
```

`provision-tunnel.sh`:

1. Looks up or creates the named tunnel via the Cloudflare API.
2. Creates the DNS route so `n8n.flynnpedroa.engineer` points at the tunnel.
3. Writes the tunnel credentials JSON into the `cloudflared_cert` volume.

> On a **remote server**, scp the `deploy/` folder over (e.g.
> `scp -r deploy user@server:/opt/n8n/`) and fill the real `.env` values there.
> Never commit `.env` (it is gitignored).

## Start / stop (on the server)

```bash
./scripts/deploy.sh up      # pulls the official image + starts the stack
./scripts/deploy.sh logs    # tail logs
./scripts/deploy.sh down    # stop
```

All `deploy.sh` commands just wrap `docker compose`. The `up` step pulls
`docker.io/n8nio/n8n:latest` from Docker Hub automatically; you can pre-pull
with `./scripts/deploy.sh pull`.

Once cloudflared connects, open **https://n8n.flynnpedroa.engineer**. First run
prompts to create the n8n owner account.

## Configuration notes

- **Public API:** n8n serves its public API under `/api/v1/...`; with the
  editor UI also exposed you get webhook + API access at the same hostname.
- **Webhooks:** `WEBHOOK_URL` is set so generated webhook URLs use the public
  host. Outbound webhook delivery to third parties works through the tunnel.
- **Encryption key:** keep `N8N_ENCRYPTION_KEY` stable across restarts or n8n
  can no longer decrypt stored credentials / webhook secrets.
- **Credentials persistence:** n8n data lives in the `n8n_data` volume.
- **Tunnel name** and **hostname** are configurable via `TUNNEL_NAME` /
  `TUNNEL_HOSTNAME` in `.env`.

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| Cloudflared `ERR Unable to load credentials file` | Tunnel was never provisioned, or the `cloudflared_cert` volume is empty. Run `provision-tunnel.sh`. |
| DNS record exists but site errors | Tunnel isn't running/connected: `docker compose --env-file .env logs cloudflared`. |
| Stored credentials unreadable in n8n | `N8N_ENCRYPTION_KEY` changed; restore the previous value. |
| Wrong API token scope | The token needs the three permissions listed above on the `flynnpedroa.engineer` zone. |
