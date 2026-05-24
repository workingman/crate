# crate

Personal Linux workstation container. Ubuntu 24.04 base with a curated set of dev tools baked in.

## Build & Run

```bash
# First time (or after UID/GID changes):
echo "UID=$(id -u)" > .env && echo "GID=$(id -g)" >> .env

# Build:
docker compose build

# Run:
docker compose run --rm crate
```

Home directory is persisted via `~/docker-home` volume mount. `~/dev` is mounted at `/home/crate/dev`.

---

## Headless Auth (no browser in the container)

The container has no browser. Two approaches depending on the tool:

### OAuth callback ports (browser flow works natively)

Some tools start a local HTTP server to receive the OAuth callback. The following ports are published to Mac loopback (`127.0.0.1` only — not exposed on the LAN), so the browser flow works transparently from your Mac:

| Tool | Port | Notes |
|---|---|---|
| `opencode` MCP auth | 19876 | Just run `opencode mcp auth` — browser flow works |
| `wrangler login` | 8976 | Run `wrangler login` — `xdg-open` shim prints the URL, open it on your Mac |

### Headless / device-flow mode

For tools that don't use a local callback server, use these flags to print a URL you visit on your Mac:

| Tool | Headless flag | Notes |
|---|---|---|
| `wrangler login` | *(no flag needed)* | `xdg-open` shim prints the URL — open it in your Mac browser, callback completes via port 8976 |
| `gcloud auth login` | `--no-launch-browser` | Prints a URL; paste auth code back at the prompt |
| `gh auth login` | *(interactive by default)* | Choose "Login with a web browser" — prints a one-time code, paste it after visiting the URL |
| `terraform login` | *(no flag needed)* | Already uses device flow; prints URL + code, works headless out of the box |

### Corporate CA / TLS inspection

If you're behind a TLS-intercepting proxy (Cloudflare WARP, Zscaler, etc.), provide your corp CA at build time:

```bash
docker build --secret id=corp-ca,src=/path/to/corp-ca.pem .
```

The cert is injected via BuildKit secret — never copied into the image layer.

---

## Installed Tools

- **Node.js LTS** + npm
- **Wrangler** (Cloudflare Workers CLI)
- **GitHub CLI** (`gh`)
- **Terraform**
- **kubectl** (pinned minor via `K8S_MINOR` build arg, default `v1.32`)
- **Helm**
- **cloudflared** (Cloudflare Tunnel client)
- **claude-code** + **opencode-ai**
- **yq** (Mike Farah's YAML processor)
- Standard utilities: `git`, `vim`, `tmux`, `htop`, `jq`, `ripgrep`, `fzf`, `tree`, and friends
