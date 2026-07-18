# Session Notes
_Last updated: Thu Jul 16, 2026, evening PST_

## Project Context
`crate` is a Docker-based personal Linux workstation image (Ubuntu 24.04) used as a persistent singleton dev sandbox. Ghostty on Mac automatically connects to the container via `crate-connect`. The container mounts `~/docker-home` as `/home/crate` (persistent home) and `~/dev` as `/home/crate/dev`. It runs a full Cloudflare toolchain: wrangler, glab, gh, terraform, gcloud, cloudflared, flarectl, rclone, trivy, pandoc, opencode, claude-code, varlock, and more.

Runtime is intentionally decoupled from the git repo: `~/dev/crate` is source, `~/.local/opt/crate` is the deployed runtime, `~/.local/bin` holds entry points. Run `./scripts/deploy` after repo changes to push them into runtime.

## Current Status
Everything is healthy. Colima is registered as a brew service (auto-starts at Mac login). The image is freshly rebuilt and running. `mem-check` is baked in and verified working. All auth flows (opencode MCP, gcloud, wrangler) confirmed working interactively. Backlog is zero.

## Completed This Session
- Confirmed Colima started and registered as a brew service via `brew services start colima`.
- Ran `./scripts/crate-rebuild` to bake `mem-check` into the image (note: `crate-build` is the preferred cached build for routine changes — see Build Scripts below).
- Discovered `~/docker-home/.bashrc.local` was already clean — no OrbStack block to remove.
- Identified that rebuilt container was not automatically restarted; ran `compose down && up -d` to get onto the new image.
- Verified `mem-check` is present at `/usr/local/bin/mem-check`, executable, and exits 0 silently (healthy state).
- Confirmed all three interactive auth flows work end-to-end: `opencode mcp auth`, `gcloud auth login`, `wrangler login`.
- Documented full tool inventory in the image.

## Todo
- No pending items. Clean slate.

## Build Scripts

| Script | Command | When to use |
|---|---|---|
| `scripts/crate-build` | `docker compose build` (with cache) | **Default. Use this for routine changes** — adding scripts, editing configs, wiring new tools. Fast; reuses unchanged layers. |
| `scripts/crate-rebuild` | `docker compose build --no-cache` | Full nuke. Use only when you need a fresh base image pull, busted apt cache, new corp CA cert, or a downloaded tool URL changed. |

**Rule of thumb:** reach for `crate-build` first. Only escalate to `crate-rebuild` when you know something external changed or layers are provably stale.

## Key Decisions Made
| Decision | Rationale |
|---|---|
| `~/.colima/default/colima.yaml` as persistence mechanism | Colima reads this on every start; `colima start --flags` just writes it. No separate plist needed for the config itself. |
| Login-time warning (not cron, not pre-launch) | Simple and visible; fires once per new shell session without adding latency to `opencode` launches. |
| Source `mem-check` rather than exec it | Runs in current shell context; no subshell overhead; cleans up the `_mem_check` function via `unset -f` after run. |
| Configurable thresholds via env vars | `WARN_FREE_MIB`, `WARN_OC_COUNT`, `WARN_OC_RSS_MIB` can be overridden in `.bashrc.local` without touching the image. |
| Bake `mem-check` into image at `/usr/local/bin/` | Follows existing pattern for `xdg-open` and `entrypoint.sh`; survives container rebuilds; sourced from `bashrc.default` which is also image-baked. |
| `crate-build` (cached) as default build script | `crate-rebuild` (no-cache) is overkill for routine changes. Use cached build unless external dependencies changed. |

## Dead Ends / What Didn't Work
- No dead ends this session.

## Relevant Files
| File | Purpose |
|---|---|
| `Dockerfile` | Image definition; COPYs `scripts/mem-check` and `xdg-open` shim to `/usr/local/bin/` |
| `scripts/mem-check` | Login-time memory health check; warns on low VM RAM or excess opencode sessions |
| `scripts/crate-build` | Cached incremental build — use this by default |
| `scripts/crate-rebuild` | No-cache full rebuild — use only when external deps changed |
| `bashrc.default` | Sources `mem-check` at login; also contains wrangler + opencode OAuth wrappers |
| `compose.yaml` | Runtime config; no memory limits set (container uses all of Colima's RAM) |
| `~/.colima/default/colima.yaml` | Colima VM config: `cpu: 4`, `memory: 6`, `disk: 100` — persistent across reboots |
| `scripts/deploy` | Materializes runtime from repo into `~/.local`; installs/reloads launchd agent |
| `~/.local/opt/crate/` | Deployed runtime: `compose.yaml`, `.env`, `.deployed-from` (git SHA stamp) |
| `~/.local/bin/` | Deployed entry points: `crate-connect`, `docker-bin` |
| `~/docker-home/.bashrc.local` | Personal shell overrides; clean (no stale OrbStack blocks) |

## Open Questions / Blockers
- No memory limits set on the container in `compose.yaml`. If Colima RAM grows scarce again (e.g., other containers added), consider adding `mem_limit` to cap the crate container.

## Immediate Next Action
No pending work. Start fresh with whatever comes up next.
