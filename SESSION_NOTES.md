# Session Notes
_Last updated: Wed Jun 03, 2026, morning PST_

## Project Context
`crate` is a Docker-based personal Linux workstation/container repo used as a persistent singleton dev sandbox launched by Ghostty on Mac. Current work is focused on making browser/OAuth-driven auth flows work cleanly inside the headless container, especially `opencode mcp auth`.

## Current Status
The `xdg-open` shim fix is working. `~/dev/crate/xdg-open` now writes the auth URL to stdout, stderr, `/tmp/xdg-open-url.txt`, and also walks the parent PID chain to find a real terminal device and write directly to it. Geoff hot-patched the running container with the updated shim and confirmed that `opencode mcp auth` now shows the URL correctly in the terminal.

## Completed This Session
- Confirmed `Dockerfile` bakes the shim into the image with `COPY xdg-open /usr/local/bin/xdg-open`.
- Updated `xdg-open` to write to stdout, stderr, `/tmp/xdg-open-url.txt`, and a discovered parent terminal device.
- Verified the repo copy still writes the URL to `/tmp/xdg-open-url.txt`.
- Restored the executable bit on `xdg-open`.
- Added `AGENTS.md` documenting the repo-first, hot-patch-optional workflow for container/system changes.
- Reviewed `docker diff crate` output from the host and determined it showed normal runtime noise, not meaningful live-container drift in key baked files.
- Hot-patched the running container from the repo copy and confirmed the fix works during `opencode mcp auth`.

## Todo
- [ ] Commit the `xdg-open` and `AGENTS.md` changes, along with any other intentional pending edits.
- [ ] Rebuild the image with `./scripts/crate-rebuild` so the working shim fix is image-backed.
- [ ] Verify `opencode mcp auth` still shows the URL in the terminal after rebuild without relying on a hot patch.
- [ ] Investigate the previously noted issue where subagents sometimes do not return.

## Key Decisions Made
| Decision | Rationale |
|---|---|
| Repo changes are the source of truth for system/container behavior | Prevents snowflake container drift and ensures fixes survive rebuilds |
| After changing the repo, explicitly decide whether to hot-patch the running container too | Keeps immediate usability separate from durable image-backed fixes |
| Treat hot patches as temporary until rebuilt into the image | Avoids relying on live edits that disappear on the next rebuild |
| `xdg-open` should walk the parent PID chain to find a usable terminal | `opencode mcp auth` can spawn `xdg-open` without a directly usable controlling TTY |

## Dead Ends / What Didn't Work
- Writing only to stdout was not enough because the caller can swallow it.
- Writing to stdout + stderr + `/tmp` still did not reliably surface the URL during `opencode mcp auth`.
- Writing to `/dev/tty` alone was not sufficient because the spawned process may not have a controlling TTY.

## Relevant Files
| File | Purpose |
|---|---|
| `xdg-open` | Headless browser shim for OAuth flows |
| `Dockerfile` | Bakes `xdg-open` into `/usr/local/bin/xdg-open` |
| `AGENTS.md` | Local workflow rules for repo-first and optional hot patches |
| `scripts/crate-build` | Standard incremental build script |
| `scripts/crate-rebuild` | Standard no-cache rebuild script |
| `README.md` | Setup and operational guidance |

## Open Questions / Blockers
- The subagents-not-returning issue remains unresolved.
- Pending edits in the repo should be reviewed and committed intentionally.

## Immediate Next Action
Commit the `xdg-open` and `AGENTS.md` changes, then rebuild the image so the working auth URL fix is image-backed.
