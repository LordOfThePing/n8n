# n8n behind a Cloudflare Tunnel

Exposes the full n8n instance — editor UI **and** public REST API — at:

> **https://n8n.flynnpedroa.engineer**

The stack runs two containers on the same Docker network:

| Service      | Image                              | Purpose                                       |
| ------------ | ---------------------------------- | --------------------------------------------- |
| `n8n`        | `docker.io/n8nio/n8n:latest`       | The n8n workflow automation backend + UI      |
| `cloudflared`| `cloudflare/cloudflared:latest`    | Cloudflare Tunnel that publishes the hostname |

n8n is bound to `127.0.0.1:5678` only; it is **not** published on the public
interface. Cloudflared reaches it over the internal Compose network, so inbound
requests never touch a machine-exposed port.

> **No custom image required.** This stack uses the official `n8nio/n8n` image
> pulled from Docker Hub. Nothing is built or pushed from your PC — only the
> `.env` configuration needs to land on the server.

## How the tunnel works here

Contrary to an earlier version of this setup, this uses cloudflared's **`--token`
run mode** — the standard way to run a tunnel created in the Cloudflare
dashboard. There is **no** API token, **no** credentials file, and **no**
`cert.pem` involved:

- You create a tunnel in the dashboard (`Networks → Tunnels → Create`).
- You add the public hostname `n8n.flynnpedroa.engineer` → `http://localhost:5678`
  for that tunnel.
- You put the tunnel's **token** (the `eyJ...` string) in `.env` as `TUNNEL_TOKEN`.
- cloudflared runs with that token and connects.

## Files

```
deploy/
├── docker-compose.yml      # n8n + cloudflared (--token mode)
├── .env.example            # environment template (copy to .env)
└── scripts/
    ├── deploy.sh           # (server) pull / up / logs / down / status
    └── deploy.ps1          # (PC, optional) Windows helpers
```

## Prerequisites

- Docker + Docker Compose v2 on the server.
- A tunnel already created in Cloudflare, with the public hostname route.

## Setup — one time

**A. In the Cloudflare dashboard:**

1. `Networks → Tunnels → Create a tunnel`.
2. Choose a name (e.g. `n8n`).
3. On the tunnel's **Public Hostname** tab, add:
   | Field | Value |
   |-------|-------|
   | Subdomain | `n8n` |
   | Domain | `flynnpedroa.engineer` |
   | Type / Service | `HTTP` → `localhost:5678` |
4. Copy the **token** shown for the tunnel (also under `Networks → Tunnels → <tunnel>
   → Configure → Token`). It looks like `eyJ...`.

**B. On the server (once):**

```bash
cd deploy
cp .env.example .env
nano .env        # set N8N_ENCRYPTION_KEY and TUNNEL_TOKEN
```

`N8N_ENCRYPTION_KEY` = `openssl rand -hex 24`. `TUNNEL_TOKEN` = the `eyJ...` token.

> Copying the `deploy/` folder to the server carries the populated `.env` with it
> (it's gitignored, so it won't be committed).

## Start / stop

```bash
cd deploy
chmod +x scripts/*.sh
./scripts/deploy.sh up      # pulls images + starts n8n + cloudflared
./scripts/deploy.sh logs    # tail logs
./scripts/deploy.sh down    # stop
```

When cloudflared connects, the log shows `Registered tunnel connection` and a
`Connection n8n.flynnpedroa.engineer ... OK` line. Then open
**https://n8n.flynnpedroa.engineer** and create the n8n owner account.

## Configuration notes

- **Public API:** n8n serves its public API under `/api/v1/...`; the same
  hostname serves webhook + API access.
- **Webhooks:** `WEBHOOK_URL` is set so generated webhook URLs use the public host.
- **Encryption key:** keep `N8N_ENCRYPTION_KEY` stable across restarts, or n8n
  can no longer decrypt stored credentials.
- **Credentials persistence:** n8n data lives in the `n8n_data` volume.
- **DNS route:** managed in the Cloudflare dashboard (Public Hostnames), not in
  this repo.

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| Cloudflared `Cannot determine ... origin certificate` | The old config.yml/credentials approach is still running. Rebuild from the new compose: `./scripts/deploy.sh down && ./scripts/deploy.sh up`. |
| Cloudflared `error parsing tunnel ID` / no connection | `TUNNEL_TOKEN` empty or wrong; confirm the `eyJ...` token is set in `.env` and that the dashboard tunnel exists. |
| DNS works but site errors | Tunnel connected but the dashboard public-hostname service points at the wrong backend. Confirm it routes `HTTP` → `localhost:5678`. |
| Stored credentials unreadable in n8n | `N8N_ENCRYPTION_KEY` changed; restore the previous value. |

## Resource requirements (RAM)

n8n's actual memory use depends on how you run executions. This stack uses the
defaults (lightest configuration): regular execution mode, no separate worker,
no Redis.

| Container | Typical RAM |
| --------- | ----------- |
| `n8n` (regular mode) | ~0.5–1.5 GB idle, more during heavy workflows |
| `cloudflared` | ~50–100 MB |
| **Total baseline** | **2 GB comfortable, ≥4 GB recommended for active use** |

- The official image does **not** set `--max-old-space-size`, so the main
  process heap is capped at Node's default (~2 GB) even on a bigger server. To
  use more headroom, add to `.env`:
  ```
  NODE_OPTIONS=--max-old-space-size=3072
  ```
- `docker stats` on the server shows live per-container CPU/RAM.

### Minimum / recommended server sizes

- **1 GB** — risky; idles OK, OOMs fast under real load.
- **2 GB** — minimum safe for light/occasional workflows.
- **4 GB** — recommended to start.
