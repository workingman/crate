# crate

Personal Linux workstation container. Ubuntu 24.04 base with a curated set of dev tools baked in.

## Architecture

crate runs as a **persistent singleton**: one long-lived container, started at Mac login via launchd.
Each Ghostty window attaches to it with `docker exec` (via the `crate-connect` script). Multiple windows share
the same container — no port conflicts, no ephemeral containers, no tmux required.

Three independent `launchd` LaunchAgents make up the full boot chain — none of them run inside any
container; they're host-side triggers that call `docker compose up -d` on your behalf:

```
Mac login
  → colima start                                      (com.groutledge.colima.plist)
  → launchd starts crate container (docker compose up -d)   (com.groutledge.crate.plist)
  → launchd starts vault container (docker compose up -d)   (see ~/dev/vault)
  → Ghostty window 1:  crate-connect  →  docker exec -it crate bash -l
  → Ghostty window 2:  crate-connect  →  docker exec -it crate bash -l
  → Ghostty window N:  crate-connect  →  docker exec -it crate bash -l
```

launchd gives no ordering guarantee between separate agents, so crate's (and vault's) agent doesn't
assume Colima already finished starting — it polls `docker info` until the daemon responds, which
works regardless of firing order.

Ports `8976` (wrangler) and `19876` (opencode MCP) are bound once at container start. All windows
share them with no conflicts.

---

## First-time Setup

### 0. Create the shared network (one-time, idempotent)

```bash
docker network create crate-net
```

Shared with the separate [`vault`](../vault/README.md) container so crate can
reach it at `http://vault:8200` by container name. Safe to re-run — both this
container's launchd job and vault's own also create it idempotently at login,
so after today you never have to think about this again. Skip this if you're
not setting up Vault.

### 1. Build the image

```bash
# Incremental build:
./docker/crate-build

# Full no-cache rebuild:
./docker/crate-rebuild
```

Corp CA cert is injected at runtime — no build-time secret needed. See the TLS section below.

> **Never run `docker build` directly.** The scripts pass the correct build args (UID, GID, USERNAME=crate).
> Running `docker build` by hand risks leaking shell env vars like `$USERNAME` as build args, producing a broken image.

### 2. Deploy runtime artifacts + install the launchd agents

```bash
cp docker/.env.example docker/.env
echo -e "UID=$(id -u)\nGID=$(id -g)" >> docker/.env
./docker/deploy
```

This decouples the runtime from the git repo (see AGENTS.md "Source vs. Runtime"). It checks host
prerequisites (docker, colima; auto-installs `socat` via Homebrew for `crate-fwd`), copies the
entry points (`crate-connect`, `docker-bin`, `colima-bin`, `crate-fwd`) into `~/.local/bin`, the
runtime config (`compose.yaml`, `.env`) into `~/.local/opt/crate`, stamps the deployed git SHA, and
installs + reloads **two** launchd agents: `com.groutledge.colima` (starts Colima itself) and
`com.groutledge.crate` (starts the crate container). Both fire at every login; the container's
`restart: unless-stopped` policy keeps it alive between logins, and `colima start` is a fast no-op
if Colima's already running.

The two plists are checked-in templates containing an `@CRATE_HOME@` placeholder — launchd can't
expand `$HOME` or `~` itself, so `docker/deploy` substitutes the real path in when it renders them
into `~/Library/LaunchAgents`. It reads `CRATE_HOME` from `docker/.env`, defaulting to `$HOME` of
whoever runs the script; only set it explicitly if you're deploying for a different user.

**Re-run `./docker/deploy` after any change you want reflected at runtime** — services never read
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
| Rebuild image | `./docker/crate-rebuild` then `docker compose up -d` |
| Push repo changes to runtime | `./docker/deploy` |

Home directory is persisted via `~/docker-home` volume mount. `~/dev` is mounted at `/home/crate/dev`.

> **Note:** Build via `./docker/crate-build` / `crate-rebuild` (thin wrappers over `docker compose build`).
> They pick up build args and the corp CA (`CORP_CA_B64`) from `docker/.env`. `USERNAME` is pinned in
> `compose.yaml`, so there's no risk of leaking shell env vars as build args.

---

## Vault (secrets)

A separate singleton container, [`~/dev/vault`](../vault/README.md), runs
HashiCorp Vault on the same Colima foundation, reachable from inside crate at
`http://vault:8200` (already set as `VAULT_ADDR` in this container's env) via
the shared `crate-net` Docker network. Backs Varlock and anything else that
wants secrets instead of plaintext `.env` files. See that repo's README for
setup, security model, and daily use.

---

## Headless Auth (no browser in the container)

The container has no browser. Approaches, in order of preference:

### `crate-fwd` — the general fix for any OAuth callback (use this first)

Most CLI tools handle OAuth by starting a temporary HTTP server inside the container
(usually bound to `127.0.0.1:<port>`) and sending your browser to `localhost:<port>` at the
end of the flow. That's unreachable from the Mac — the browser tab fails with
"localhost refused to connect", and the failing URL shows the port.

`crate-fwd` (installed to `~/.local/bin` by `./docker/deploy`) forwards Mac
`localhost:<port>` into the container's loopback via `docker exec` + `socat` — the
`kubectl port-forward` trick. No compose changes, no published ports, works for any
tool and any port, including listeners bound to `127.0.0.1` inside the container:

```
crate-fwd 1455        # then reload the failed browser tab; Ctrl-C when done
```

The container's `xdg-open` shim prints the exact `crate-fwd <port>` command alongside
the auth URL whenever it spots a localhost callback in the flow. Requires `socat` on
the Mac (`./docker/deploy` auto-installs it via Homebrew).

### OAuth callback ports (zero-touch, pre-wired per tool)

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

New tools don't get added here — use `crate-fwd` instead. Per-tool wiring costs a compose
edit + container recreate (and often a bashrc wrapper) for every tool; only these two
predate `crate-fwd` and stay for zero-touch convenience.

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
sed -i '' '/^CORP_CA_B64=/d' docker/.env
printf 'CORP_CA_B64=%s\n' "$(base64 < ~/docker-home/.corp-ca.pem | tr -d '\n')" >> docker/.env

# 3. Rebuild:
docker compose -f docker/compose.yaml build
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
- **Vault CLI** (talks to the separate `vault` container — see "Vault" above)
- **varlock** (AI-safe env/secrets manager)
- **cloudflared** (Cloudflare Tunnel client)
- **rclone** (cloud storage CLI — native R2, GCS, S3 support)
- **trivy** (vulnerability scanner — npm deps, container images, IaC, secrets)
- **claude-code** + **opencode-ai**
- **yq** (Mike Farah's YAML processor)
- Standard utilities: `git`, `vim`, `tmux`, `htop`, `jq`, `ripgrep`, `fzf`, `tree`, and friends
