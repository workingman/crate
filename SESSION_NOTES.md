# Session Notes
_Last updated: Sat Jul 18, 2026, PDT_

## Project Context
`crate` is a Docker-based Ubuntu 24.04 personal workstation. Ghostty on the Mac connects through `crate-connect`; persistent home and development data are mounted from `~/docker-home` and `~/dev`. Source lives in `~/dev/crate`, while deployed runtime artifacts live under `~/.local/opt/crate` and entry points under `~/.local/bin`; runtime services must never depend on the git working tree. The image is used on two machines: a Cloudflare corp Mac (`groutledge`) and a personal Mac (`geoff`).

## Current Status
The container is healthy but Colima currently has only 6 GiB RAM and no swap. Geoff wants 10+ concurrent Ghostty windows, each running OpenCode. Measurements across six live OpenCode sessions showed 4.22 GiB total PSS, averaging 703 MiB per session; ten similar sessions project to about 7 GiB for OpenCode alone. The current 6 GiB VM is therefore not equipped for that workload. A 12 GiB Colima allocation is recommended, leaving the other 12 GiB of the 24 GiB Mac for macOS and Chrome.

The deployed `/usr/local/bin/mem-check` still has the old aggressive defaults (`>1` process or `>800 MiB` RSS). Source has been corrected but has not been rebuilt/redeployed. Active sessions will be interrupted by resizing Colima and recreating the container, so Geoff should do that when ready.

The local checkout had diverged from `origin/main` for several weeks (local kept building on an older common ancestor instead of pulling first). Merged both histories back together on Jul 18. `origin/main`'s "generic-by-default" refactor (generic `gitlab.com` default, `Host *` SSH config, portable `crate-connect` docker discovery, bash-3.2-safe array expansion) was kept as-is since it didn't touch anything the running container currently depends on. Where the two histories genuinely conflicted — corp CA cert handling — the currently-running local approach (plain `CORP_CA_B64` build `ARG`) was kept over `origin/main`'s more secure BuildKit `--secret` mount, deliberately, to match what's actually deployed right now. See Todo for the follow-up review.

## Completed This Session
- Reassessed the login warning using Linux `MemAvailable` rather than misleading raw free memory.
- Measured per-process PSS from `/proc/<pid>/smaps_rollup`; six sessions averaged 703 MiB and projected ten sessions at roughly 7 GiB.
- Removed process count as an independent warning condition; legitimate session count is not memory pressure.
- Changed `scripts/mem-check` from summed RSS to PSS so shared pages are not double-counted.
- Set source defaults to warn below 1024 MiB available RAM, above 1200 MiB PSS for one process, or above 75% aggregate OpenCode PSS.
- Replaced the unusable in-container `docker exec ... pkill` advice with `ps -o pid,etime,rss,cmd -C opencode` for inspection.
- Moved mem-check invocation into the generated `.bashrc` after `.bashrc.local`, allowing documented environment overrides to work.
- Verified shell syntax, normal silent behavior, per-process warning behavior, aggregate warning behavior, and `git diff --check`.
- Committed all outstanding local work (Colima login automation, Vault CLI/network, cron, `oc()`, mem-check) and merged with `origin/main`'s "generic-by-default" refactor, resolving conflicts in favor of the currently-running local configuration.

## Previously Completed (Jun 7 session, on `origin/main`)
- Pulled 26 commits from `origin/main` to bring the personal Mac up to date.
- Fixed `scripts/crate-{build,rebuild,update}`: bash-3.2 `set -u` tripped on `"${CRATE_SECRET_ARGS[@]}"` when no corp CA was present. Switched to the `${arr[@]+"${arr[@]}"}` idiom so empty-array expansion is safe. (Note: local's own build scripts now go through `docker compose build` via `docker-bin`/`colima-bin` instead, so this idiom no longer applies on this machine — see Dead Ends.)
- Audited the repo for corp-only assumptions. Only real defect: `glab-config.yml` was hard-wired to `gitlab.cfdata.org` (unreachable on a non-corp network).
- Refactored to generic defaults: `glab-config.yml` → `gitlab.com`; `entrypoint.sh` SSH config seeds `Host *` with the crate key; `ssh-keyscan` pre-trusts `github.com` + `gitlab.com`.
- Added `cf-glab-config.yml` at the repo root: corp glab config plus a recipe header for the corp laptop.
- Considered and rejected a two-image (generic base + corp overlay) pattern — only the CA cert is a genuine buildtime corp concern.
- Fixed `crate-connect`: replaced hardcoded `/usr/local/bin/docker` with a probe chain. (Superseded locally by the dedicated `scripts/docker-bin`/`scripts/colima-bin` helpers, which additionally handle dead symlinks and Colima.)

## Todo
- [ ] On the Mac, stop Colima and restart it with 12 GiB: `colima stop && colima start --memory 12`.
- [ ] Build the corrected image with `cd ~/dev/crate && ./scripts/crate-build`.
- [ ] Recreate the runtime container from the deployed compose file: `docker compose --env-file ~/.local/opt/crate/.env -f ~/.local/opt/crate/compose.yaml up -d --force-recreate crate`.
- [ ] Open several Ghostty/OpenCode sessions and verify mem-check remains silent while memory is healthy.
- [ ] Confirm whether Colima has been registered for login startup with `brew services start colima`; prior notes listed this as pending.
- [ ] Verify `opencode mcp auth` works end-to-end with the socat relay.
- [ ] Consider updating corp cert handling — assess but don't fix until after discussion. `origin/main` implemented the corp CA cert as a BuildKit `--secret` mount (never persisted in image layers); local currently bakes it in as a plain `ARG CORP_CA_B64`, which does persist in `docker history`. Kept local's approach for now because it matches what's actually deployed; revisit once there's time to test the secret-mount path end-to-end.
- [ ] On the corp Mac (if/when a second machine is onboarded), decide whether to adopt the generic `glab-config.yml` + `cf-glab-config.yml` overlay pattern, or keep the corp-specific default baked in as it is on this machine.

## Key Decisions Made
| Decision | Rationale |
|---|---|
| Allocate 12 GiB to Colima | Ten OpenCode sessions project to ~7 GiB PSS; 10 GiB would work but leave little guest headroom, while 12 GiB still leaves half of the 24 GiB Mac for Chrome/macOS. |
| Warn on memory, not session count | Ten or more sessions are intentional; count alone cannot distinguish legitimate work from orphans. |
| Use PSS instead of RSS | Summed RSS double-counts shared pages. PSS proportionally allocates shared memory and gives a meaningful aggregate. |
| Keep `MemAvailable < 1024 MiB` as the primary system-pressure signal | Linux page cache makes raw `free` RAM look dangerously low even when reclaimable memory is healthy. |
| Run mem-check after `.bashrc.local` | Threshold environment variables must exist before the check executes. |
| Use incremental `scripts/crate-build` | No external downloads or busted cache require a no-cache rebuild. |
| On merge conflict, favor the config that matches the currently-running container | Predictability over theoretical improvement — a security sweep can happen deliberately later rather than as a side effect of a routine merge. |
| Keep `origin/main`'s generic-by-default SSH/glab defaults | They only affect freshly-seeded homes, not the already-configured running container, so accepting them carries no risk to current behavior. |
| Generic-by-default image, corp overlay as one self-documenting checked-in file (from Jun 7 session) | Works everywhere with no gymnastics; the file's existence in repo root is the reminder. |
| `crate-connect` probes installer-specific docker locations via `scripts/docker-bin`, PATH last | Works under launchd (no PATH inheritance) and across OrbStack/Colima/Docker Desktop installs, including dead symlinks. |

## Dead Ends / What Didn't Work
- The initial reassessment summed RSS and called 166 MiB raw free memory "razor thin." That was incorrect: RSS double-counted shared pages and `MemAvailable` was about 2.8 GiB. PSS and `MemAvailable` are now used instead.
- The previous kill command began with `docker exec`, but login warnings appear inside the container where no Docker CLI exists. It was removed.
- `.bashrc.local` overrides could not affect mem-check because the check ran before that file was sourced. Invocation was moved after personal overrides.
- Continuing local work for weeks without pulling `origin/main` first caused a real divergence (corp-CA build-secret approach vs. plain build ARG, plus overlapping edits to `crate-connect` and the build scripts). Costly enough to be worth calling out: pull before starting a new multi-day thread of work.

## Relevant Files
| File | Purpose |
|---|---|
| `scripts/mem-check` | PSS-based login-time memory health check, installed into the image at `/usr/local/bin/mem-check`. |
| `Dockerfile` | Installs cron and Vault CLI; copies mem-check into the image. |
| `entrypoint.sh` | Generates `.bashrc` (invokes mem-check after `.bashrc.local`); seeds generic SSH config/keys/known_hosts; loads a repo-mounted crontab if present. |
| `bashrc.default` | Shell defaults and OpenCode wrappers, including `oc()` to exec opencode as the session's main process. |
| `compose.yaml` | Defines the singleton `crate` container; joins the shared `crate-net` network; sets `VAULT_ADDR`; still carries the (now unused) `GITLAB_HOST` env var. |
| `scripts/crate-build` / `crate-rebuild` / `crate-update` | Build via `docker compose build`, using `scripts/docker-bin` for portable docker discovery. |
| `scripts/colima-bin` | Portable Colima binary discovery, mirrors `scripts/docker-bin`. |
| `com.groutledge.colima.plist` | LaunchAgent that starts Colima at login, before crate/vault compose come up. |
| `glab-config.yml` | Generic `gitlab.com` default config seeded into every container. |
| `cf-glab-config.yml` | Corp overlay + recipe header for the work-laptop setup (not currently applied on this machine). |
| `~/.colima/default/colima.yaml` | Host-side Colima config, currently 4 CPUs / 6 GiB RAM / 100 GiB disk. |
| `~/.local/opt/crate/` | Deployed compose and environment files used to recreate the runtime container. |

## Open Questions / Blockers
- Resizing Colima and recreating the container must be run from the Mac host and will terminate active OpenCode sessions.
- Colima brew-service registration and the OpenCode MCP OAuth relay remain unverified.
- Corp CA cert handling (build ARG vs. BuildKit secret) needs a deliberate security review — see Todo.
- `com.groutledge.crate.plist` is still corp-specific (hardcoded paths/label); no urgent need to genericize since only one machine is onboarded, but worth deciding before a second machine is set up.

## Immediate Next Action
Close or save active OpenCode sessions, then run `colima stop && colima start --memory 12` on the Mac.
