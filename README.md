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
# Incremental build:
./scripts/crate-build

# Full no-cache rebuild:
./scripts/crate-rebuild
```

Corp CA cert is injected at runtime — no build-time secret needed. See the TLS section below.

> **Never run `docker build` directly.** The scripts pass the correct build args (UID, GID, USERNAME=crate).
> Running `docker build` by hand risks leaking shell env vars like `$USERNAME` as build args, producing a broken image.

### 2. Deploy runtime artifacts + install the launchd agent

```bash
./scripts/deploy
```

This decouples the runtime from the git repo (see AGENTS.md "Source vs. Runtime"). It copies the
entry points (`crate-connect`, `docker-bin`) into `~/.local/bin`, the runtime config
(`compose.yaml`, `.env`) into `~/.local/opt/crate`, stamps the deployed git SHA, and installs +
reloads the launchd agent. The agent starts `docker compose up -d` at every login; the container's
`restart: unless-stopped` policy keeps it alive between logins.

**Re-run `./scripts/deploy` after any change you want reflected at runtime** — services never read
the repo directly.

### 3. Configure Ghostty

```bash
bash setup-ghostty.sh
```

This writes `~/.config/ghostty/config` pointing at `~/.local/bin/crate-connect` (the deployed entry
point). Each new Ghostty window runs it, which does `docker exec -it crate bash -l`. Open Ghostty
and you should land at `crate@crate:~$`.

---

## Daily Use

| Action | Command |
|---|---|
| Open a new terminal in crate | Open a new Ghostty window — `crate-connect` runs automatically |
| Start container manually | `docker compose up -d` (from `~/dev/crate`) |
| Stop container | `docker compose down` |
| Restart container | `docker compose restart` |
| Rebuild image | `./scripts/crate-rebuild` then `docker compose up -d` |
| Push repo changes to runtime | `./scripts/deploy` |

Home directory is persisted via `~/docker-home` volume mount. `~/dev` is mounted at `/home/crate/dev`.

> **Note:** Build via `./scripts/crate-build` / `crate-rebuild` (thin wrappers over `docker compose build`).
> They pick up build args and the corp CA (`CORP_CA_B64`) from `.env`. `USERNAME` is pinned in
> `compose.yaml`, so there's no risk of leaking shell env vars as build args.

---

## Headless Auth (no browser in the container)

The container has no browser. Two approaches depending on the tool:

### OAuth callback ports (browser flow works natively)

Some tools start a local HTTP server to receive the OAuth callback. The following ports are published
to Mac loopback (`127.0.0.1` only — not exposed on the LAN), so the browser flow works transparently
from your Mac.

> **Docker port-forwarding limitation (runtime-agnostic):** Published-port traffic reaches the
> container via its external interface, so it only hits listeners bound to `0.0.0.0` inside the
> container — not `127.0.0.1` or `::1`. A loopback-bound listener accepts the TCP handshake but
> drops the data (`ERR_EMPTY_RESPONSE` / connection reset). Verified on Colima. The default shell
> config wraps `wrangler login` so it binds to `0.0.0.0` automatically.

| Tool | Port | Notes |
|---|---|---|
| `opencode` MCP auth | 19876 | Just run `opencode mcp auth` — browser flow works |
| `wrangler login` | 8976 | Just run `wrangler login` — the shell wrapper adds `--callback-host 0.0.0.0` automatically |

### Headless / device-flow mode

For tools that don't use a local callback server:

| Tool | Headless flag | Notes |
|---|---|---|
| `gcloud auth login` | `--no-launch-browser` | Prints a URL → open in Mac browser → paste auth code back |
| `gh auth login` | *(interactive)* | Choose "Login with a web browser" — prints a one-time code |
| `terraform login` | *(no flag needed)* | Already uses device flow; prints URL + code |

### Corporate CA / TLS inspection

If you're behind a TLS-intercepting proxy (Cloudflare WARP, Zscaler, etc.), the corp CA
must be in the image's trust store at build time or `curl`/apt steps fail with
`self-signed certificate in certificate chain`.

A CA cert is **public** (not a secret), so it's passed as a base64 build arg via `.env`.
On a clean machine (home Mac, CI) leave it empty and the build skips it.

**Regenerate `CORP_CA_B64` when the cert rotates:**

```bash
# 1. Export the cert from Keychain Access:
#    search "Cloudflare for Teams ECC Certificate Authority" → Export as .pem
#    → save to ~/docker-home/.corp-ca.pem
#
# 2. Refresh the .env line (run from the crate repo dir):
sed -i '' '/^CORP_CA_B64=/d' .env
printf 'CORP_CA_B64=%s\n' "$(base64 < ~/docker-home/.corp-ca.pem | tr -d '\n')" >> .env

# 3. Rebuild:
docker compose build
```

Cache note: the cert layer only rebuilds when the `CORP_CA_B64` value actually changes
(i.e. on cert rotation), not on every build.

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
