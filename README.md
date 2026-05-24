# crate

Personal Linux workstation container. Ubuntu 24.04 base with a curated set of dev tools baked in.

## Build & Run

```bash
# First time (or after UID/GID changes):
echo "UID=$(id -u)" > .env && echo "GID=$(id -g)" >> .env

# Build (no corporate CA):
docker compose build

# Build (with corporate CA — required when behind Cloudflare WARP / TLS inspection):
# docker compose does NOT support --secret; use docker build directly.
docker build \
  --secret id=corp-ca,src=/Users/groutledge/cloudflare-ca.pem \
  --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
  -t crate:latest .

# Run:
docker compose run --rm crate
```

Home directory is persisted via `~/docker-home` volume mount. `~/dev` is mounted at `/home/crate/dev`.

> **Note:** `docker compose run` normally ignores `ports:`, but here it works correctly because the port bindings are declared in `compose.yaml` (not passed as CLI flags). No `--service-ports` flag needed.

> **Note:** `docker compose build --secret` is not supported in Compose v5. Always use `docker build` directly when injecting BuildKit secrets.

---

## Headless Auth (no browser in the container)

The container has no browser. Two approaches depending on the tool:

### OAuth callback ports (browser flow works natively)

Some tools start a local HTTP server to receive the OAuth callback. The following ports are published to Mac loopback (`127.0.0.1` only — not exposed on the LAN), so the browser flow works transparently from your Mac.

> **OrbStack limitation:** OrbStack can only forward to listeners bound on `0.0.0.0` inside the container. Listeners bound to `127.0.0.1` or `::1` will accept the TCP handshake but silently drop all data (you'll see `ERR_EMPTY_RESPONSE`). Tools that default to `localhost` need an explicit flag to bind on `0.0.0.0` — see the `wl` alias below.

| Tool | Port | Notes |
|---|---|---|
| `opencode` MCP auth | 19876 | Just run `opencode mcp auth` — browser flow works |
| `wrangler login` | 8976 | Run `wl` (alias for `wrangler login --callback-host 0.0.0.0`) — OrbStack requires `0.0.0.0` binding, not `localhost` |

### Headless / device-flow mode

For tools that don't use a local callback server, use these flags to print a URL you visit on your Mac:

| Tool | Headless flag | Notes |
|---|---|---|
| `gcloud auth login` | `--no-launch-browser` | Prints a URL; paste auth code back at the prompt |
| `gh auth login` | *(interactive by default)* | Choose "Login with a web browser" — prints a one-time code, paste it after visiting the URL |
| `terraform login` | *(no flag needed)* | Already uses device flow; prints URL + code, works headless out of the box |

### Corporate CA / TLS inspection

If you're behind a TLS-intercepting proxy (Cloudflare WARP, Zscaler, etc.), provide your corp CA at build time:

```bash
docker build \
  --secret id=corp-ca,src=/Users/groutledge/cloudflare-ca.pem \
  --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
  -t crate:latest .
```

The cert is injected via BuildKit secret — never copied into the image layer. `--build-arg UID/GID` is required alongside `--secret` since we can't use `docker compose build` here (Compose v5 doesn't support `--secret`).

`~/cloudflare-ca.pem` is the Cloudflare WARP corporate CA. Export it from your Mac's Keychain (look for "Cloudflare for Teams ECC Certificate Authority") or ask your IT/SE team for the PEM file.

---

## Installed Tools

- **Node.js LTS** + npm
- **Wrangler** (Cloudflare Workers CLI)
- **GitHub CLI** (`gh`)
- **Terraform**
- **cloudflared** (Cloudflare Tunnel client)
- **rclone** (cloud storage CLI — native R2, GCS, S3 support)
- **claude-code** + **opencode-ai**
- **yq** (Mike Farah's YAML processor)
- Standard utilities: `git`, `vim`, `tmux`, `htop`, `jq`, `ripgrep`, `fzf`, `tree`, and friends
