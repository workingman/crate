# Session Notes
_Last updated: Sat Jul 18, 2026, PDT_

## Project Context
`crate` is a Docker-based Ubuntu 24.04 personal workstation. Ghostty on the Mac connects through `crate-connect`; persistent home and development data are mounted from `~/docker-home` and `~/dev`. Source lives in `~/dev/crate`, while deployed runtime artifacts live under `~/.local/opt/crate` and entry points under `~/.local/bin`; runtime services must never depend on the git working tree.

## Current Status
The container is healthy but Colima currently has only 6 GiB RAM and no swap. Geoff wants 10+ concurrent Ghostty windows, each running OpenCode. Measurements across six live OpenCode sessions showed 4.22 GiB total PSS, averaging 703 MiB per session; ten similar sessions project to about 7 GiB for OpenCode alone. The current 6 GiB VM is therefore not equipped for that workload. A 12 GiB Colima allocation is recommended, leaving the other 12 GiB of the 24 GiB Mac for macOS and Chrome.

The deployed `/usr/local/bin/mem-check` still has the old aggressive defaults (`>1` process or `>800 MiB` RSS). Source has been corrected but has not been rebuilt/redeployed. Active sessions will be interrupted by resizing Colima and recreating the container, so Geoff should do that when ready.

## Completed This Session
- Reassessed the login warning using Linux `MemAvailable` rather than misleading raw free memory.
- Measured per-process PSS from `/proc/<pid>/smaps_rollup`; six sessions averaged 703 MiB and projected ten sessions at roughly 7 GiB.
- Removed process count as an independent warning condition; legitimate session count is not memory pressure.
- Changed `scripts/mem-check` from summed RSS to PSS so shared pages are not double-counted.
- Set source defaults to warn below 1024 MiB available RAM, above 1200 MiB PSS for one process, or above 75% aggregate OpenCode PSS.
- Replaced the unusable in-container `docker exec ... pkill` advice with `ps -o pid,etime,rss,cmd -C opencode` for inspection.
- Moved mem-check invocation into the generated `.bashrc` after `.bashrc.local`, allowing documented environment overrides to work.
- Verified shell syntax, normal silent behavior, per-process warning behavior, aggregate warning behavior, and `git diff --check`.

## Todo
- [ ] On the Mac, stop Colima and restart it with 12 GiB: `colima stop && colima start --memory 12`.
- [ ] Build the corrected image with `cd ~/dev/crate && ./scripts/crate-build`.
- [ ] Recreate the runtime container from the deployed compose file: `docker compose --env-file ~/.local/opt/crate/.env -f ~/.local/opt/crate/compose.yaml up -d --force-recreate crate`.
- [ ] Open several Ghostty/OpenCode sessions and verify mem-check remains silent while memory is healthy.
- [ ] Confirm whether Colima has been registered for login startup with `brew services start colima`; prior notes listed this as pending.
- [ ] Verify `opencode mcp auth` works end-to-end with the socat relay.

## Key Decisions Made
| Decision | Rationale |
|---|---|
| Allocate 12 GiB to Colima | Ten OpenCode sessions project to ~7 GiB PSS; 10 GiB would work but leave little guest headroom, while 12 GiB still leaves half of the 24 GiB Mac for Chrome/macOS. |
| Warn on memory, not session count | Ten or more sessions are intentional; count alone cannot distinguish legitimate work from orphans. |
| Use PSS instead of RSS | Summed RSS double-counts shared pages. PSS proportionally allocates shared memory and gives a meaningful aggregate. |
| Keep `MemAvailable < 1024 MiB` as the primary system-pressure signal | Linux page cache makes raw `free` RAM look dangerously low even when reclaimable memory is healthy. |
| Run mem-check after `.bashrc.local` | Threshold environment variables must exist before the check executes. |
| Use incremental `scripts/crate-build` | No external downloads or busted cache require a no-cache rebuild. |

## Dead Ends / What Didn't Work
- The initial reassessment summed RSS and called 166 MiB raw free memory "razor thin." That was incorrect: RSS double-counted shared pages and `MemAvailable` was about 2.8 GiB. PSS and `MemAvailable` are now used instead.
- The previous kill command began with `docker exec`, but login warnings appear inside the container where no Docker CLI exists. It was removed.
- `.bashrc.local` overrides could not affect mem-check because the check ran before that file was sourced. Invocation was moved after personal overrides.

## Relevant Files
| File | Purpose |
|---|---|
| `scripts/mem-check` | Corrected PSS-based login-time memory health check; currently untracked and must be included in a future commit. |
| `Dockerfile` | Copies mem-check into the image at `/usr/local/bin/mem-check`. |
| `entrypoint.sh` | Generates `.bashrc`; now invokes mem-check after `.bashrc.local`. |
| `bashrc.default` | Shell defaults and OpenCode wrappers; mem-check invocation was removed from here. |
| `compose.yaml` | Defines the singleton `crate` container with `restart: unless-stopped`; no container memory limit. |
| `scripts/crate-build` | Incremental Docker Compose image build; preferred for this update. |
| `~/.colima/default/colima.yaml` | Host-side Colima config, currently 4 CPUs / 6 GiB RAM / 100 GiB disk. |
| `~/.local/opt/crate/` | Deployed compose and environment files used to recreate the runtime container. |

## Open Questions / Blockers
- Resizing Colima and recreating the container must be run from the Mac host and will terminate active OpenCode sessions.
- The source working tree is already dirty with related prior-session work (`Dockerfile`, `bashrc.default`, `entrypoint.sh`, and untracked `scripts/mem-check`) plus `SESSION_NOTES.md`; nothing has been committed.
- Colima brew-service registration and the OpenCode MCP OAuth relay remain unverified.

## Immediate Next Action
Close or save active OpenCode sessions, then run `colima stop && colima start --memory 12` on the Mac.
