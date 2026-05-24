# crate

Personal Linux workstation container. Ubuntu 24.04 base with a curated set of dev tools baked in.

## Architecture

crate runs as a **persistent singleton**: one long-lived container, started at Mac login via launchd.
Each Ghostty window attaches to it with `docker exec` (via the `crate-connect` script). Multiple windows share
the same container — no port conflicts, no ephemeral containers, no tmux required.

```
Mac login
  → launchd starts crate container (docker compose up -d)
  → Ghostty window 1:  crate-connect  →  docker exec -it crate bash -l
  → Ghostty window 2:  crate-connect  →  docker exec -it crate bash -l
  → Ghostty window N:  crate-connect  →  docker exec -it crate bash -l
```

Ports `8976` (wrangler) and `19876` (opencode MCP) are bound once at container start. All windows
share them with no conflicts.

---

## First-time Setup

### 1. Build the image

```bash
# Generate .env with your UID/GID:
echo "UID=$(id -u)" > .env && echo "GID=$(id -g)" >> .env

# Build (no corporate CA):
docker compose build

# Build (with corporate CA — required when behind Cloudflare WARP / TLS inspection):
# docker compose does NOT support --secret; use docker build directly.
docker build \
  --secret id=corp-ca,src=/Users/groutledge/cloudflare-ca.pem \
  --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
  -t crate:latest .
```

### 2. Install the launchd agent (start at login)

```bash
cp com.groutledge.crate.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.groutledge.crate.plist
```

This starts `docker compose up -d` at every login. The container's `restart: unless-stopped` policy
keeps it alive if it crashes between logins.

### 3. Configure Ghostty

```bash
bash setup-ghostty.sh
```

This writes `~/.config/ghostty/config` pointing at the `crate-connect` script. Each new Ghostty window
runs `crate-connect`, which does `docker exec -it crate bash -l`.

### 4. Start the container now (without rebooting)

```bash
docker compose up -d
```

Then open Ghostty. You should land at `crate@crate:~$`.

---

## Daily Use

| Action | Command |
|---|---|
| Open a new terminal in crate | Open a new Ghostty window — `crate-connect` runs automatically |
| Start container manually | `docker compose up -d` (from `~/dev/crate`) |
| Stop container | `docker compose down` |
| Restart container | `docker compose restart` |
| Rebuild image | `docker compose build` then `docker compose up -d` |

Home directory is persisted via `~/docker-home` volume mount. `~/dev` is mounted at `/home/crate/dev`.

> **Note:** `docker compose build --secret` is not supported in Compose v5. Always use `docker build`
> directly when injecting BuildKit secrets.

---

## Headless Auth (no browser in the container)

The container has no browser. Two approaches depending on the tool:

### OAuth callback ports (browser flow works natively)

Some tools start a local HTTP server to receive the OAuth callback. The following ports are published
to Mac loopback (`127.0.0.1` only — not exposed on the LAN), so the browser flow works transparently
from your Mac.

> **OrbStack limitation:** OrbStack can only forward to listeners bound on `0.0.0.0` inside the
> container. Listeners bound to `127.0.0.1` or `::1` will accept the TCP handshake but silently drop
> all data (you'll see `ERR_EMPTY_RESPONSE`). Tools that default to `localhost` need an explicit flag
> to bind on `0.0.0.0` — see the `wl` alias below.

| Tool | Port | Notes |
|---|---|---|
| `opencode` MCP auth | 19876 | Just run `opencode mcp auth` — browser flow works |
| `wrangler login` | 8976 | Run `wl` (alias for `wrangler login --callback-host 0.0.0.0`) |

### Headless / device-flow mode

For tools that don't use a local callback server:

| Tool | Headless flag | Notes |
|---|---|---|
| `gcloud auth login` | `--no-launch-browser` | Prints a URL → open in Mac browser → paste auth code back |
| `gh auth login` | *(interactive)* | Choose "Login with a web browser" — prints a one-time code |
| `terraform login` | *(no flag needed)* | Already uses device flow; prints URL + code |

### Corporate CA / TLS inspection

If you're behind a TLS-intercepting proxy (Cloudflare WARP, Zscaler, etc.), provide your corp CA
at build time:

```bash
docker build \
  --secret id=corp-ca,src=/Users/groutledge/cloudflare-ca.pem \
  --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
  -t crate:latest .
```

`~/cloudflare-ca.pem` is the Cloudflare WARP corporate CA. Export it from your Mac's Keychain
(look for "Cloudflare for Teams ECC Certificate Authority").

---

## Installed Tools

- **Node.js LTS** + npm
- **Wrangler** (Cloudflare Workers CLI)
- **Miniflare** (local Cloudflare Workers runtime — offline dev and demos)
- **flarectl** (Cloudflare CLI — quick DNS/zone/account ops)
- **GitHub CLI** (`gh`)
- **Terraform**
- **cloudflared** (Cloudflare Tunnel client)
- **rclone** (cloud storage CLI — native R2, GCS, S3 support)
- **trivy** (vulnerability scanner — npm deps, container images, IaC, secrets)
- **claude-code** + **opencode-ai**
- **yq** (Mike Farah's YAML processor)
- Standard utilities: `git`, `vim`, `tmux`, `htop`, `jq`, `ripgrep`, `fzf`, `tree`, and friends
