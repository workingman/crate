# Session Notes
_Last updated: Tue Jul 21, 2026, PST_

## Project Context
`crate` is a Docker-based personal Linux workstation image (Ubuntu 24.04) used as a persistent singleton dev sandbox. Ghostty on Mac automatically connects to the container via `crate-connect`. The container mounts `~/docker-home` as `/home/crate` (persistent home) and `~/dev` as `/home/crate/dev`. It runs a full Cloudflare toolchain: wrangler, glab, gh, terraform, gcloud, cloudflared, flarectl, rclone, trivy, pandoc, opencode, claude-code, varlock, and more.

Runtime is intentionally decoupled from the git repo: `~/dev/crate` is source, `~/.local/opt/crate` is the deployed runtime, `~/.local/bin` holds entry points. Run `./scripts/deploy` after repo changes to push them into runtime. Image config (`Dockerfile`) `COPY`s `bashrc.default` straight into `/etc/skel-devbox/bashrc.default` in the container.

## Current Status
Found and fixed a design regression in the `opencode`/`oc` shell wrapper. The **repo** (`bashrc.default`) already had the correct, wanted design committed on branch `fix/mcp-auth-regression` (commit `11e9bab`) — it just hadn't been pushed. Pushed it. The **running container's** `/etc/skel-devbox/bashrc.default` still has the old/regressed design and was hot-patched live by Geoff via `sudo tee` (copying repo's version over it) — but the **image itself has not been rebuilt yet**, so a container recreation will currently reintroduce the regressed version until the image is rebuilt from this branch/commit.

**Follow-up (same branch):** Geoff reversed the "no `exec`" decision below — he hot-patched the live container's `/etc/skel-devbox/bashrc.default` to add `exec` back in front of `opencode` in `oc()`, and separately decided `oc()` should always launch in yolo mode (`--auto`). Both changes have now been applied to the repo's `bashrc.default` (still uncommitted as of this note — see Todo) so they persist into the next image build. Also added a hard `rm -fr`/`rm -rf` `deny` guardrail to `~/.config/opencode/opencode.jsonc` (outside this repo, in the persistent docker-home) plus a matching note in `~/.config/opencode/AGENTS.md`, specifically because `--auto` auto-approves plain `"ask"` permission rules — only `"deny"` survives yolo mode.

## Completed This Session
- Diagnosed that `opencode` in the container is a raw Bun-compiled binary at `/usr/bin/opencode`, not a wrapper itself.
- Found the actual wrapper logic lives in shell functions sourced from `/etc/skel-devbox/bashrc.default` (via `~/.bashrc`).
- Discovered **drift**: the live running container's `set` output showed `opencode()` overridden as a function (with the mcp-auth socat relay + `command opencode` inside) and `oc()` reduced to just `exec opencode "$@"`. This did NOT match the repo's `bashrc.default`, which has the reverse: `opencode` left raw/unshadowed, `oc()` carrying the relay logic.
- Compared repo `bashrc.default` vs. the container's `/etc/skel-devbox/bashrc.default` directly — confirmed the running image has a newer, different (unwanted) design that never made it back into the repo.
- Decided to keep it simple: `opencode` stays a raw unshadowed executable; `oc()` is the only wrapper and carries the mcp-auth relay logic; no `exec` in `oc()` (Geoff didn't want the "exec replaces shell" behavior — it was surprising him with Ghostty dropping to a dead pane / "hit a key to close").
- Confirmed the repo's `bashrc.default` already reflected exactly this wanted design (no edit needed) — it's committed as `11e9bab` on branch `fix/mcp-auth-regression`, one commit ahead of `main`.
- Hot-patched the **running container** by having Geoff run (root-owned file, outside my sudo-denied permissions):
  ```bash
  sudo tee /etc/skel-devbox/bashrc.default < /home/crate/dev/crate/bashrc.default
  ```
- Pushed branch: `git push -u origin fix/mcp-auth-regression` → new branch on GitHub (`workingman/crate`), PR link offered but not yet opened.
- Geoff hot-patched the running container's `/etc/skel-devbox/bashrc.default` himself to add `exec` back to `oc()`'s final `opencode "$@"` call. Brought the repo's `bashrc.default` in line with that (`exec opencode --auto "$@"`).
- Added `--auto` (yolo mode) to that same line so every `oc` invocation launches opencode with auto-approve permissions on. Left the `opencode mcp auth` branch inside `oc()` alone — no `exec`, no `--auto` — since it needs to run cleanup (`kill "$relay"`) after opencode exits, and `--auto` is meaningless for an OAuth flow.
- Added a hard-deny guardrail for `rm -fr`/`rm -rf` (all flag-order/spelling variants) to `permission.bash` in `~/.config/opencode/opencode.jsonc`. Confirmed via opencode's docs that `--auto` auto-approves any rule that would otherwise resolve to `"ask"` — only `"deny"` rules survive auto mode — so a plain AGENTS.md instruction or an `"ask"` permission rule would NOT have been sufficient on its own once `oc()` always runs `--auto`.
- Documented the guardrail (and why `"ask"` wasn't enough) in `~/.config/opencode/AGENTS.md` under the existing `## Permissions` section, next to the `sudo` rule.

## Todo
- [ ] Rebuild the `crate` image from `fix/mcp-auth-regression` (or after merging to `main`) so `/etc/skel-devbox/bashrc.default` bakes in correctly and the hot patch isn't the only thing holding this fix in place. Use `scripts/crate-build` (cached) unless something external changed.
- [ ] Open the PR for `fix/mcp-auth-regression` → `main` (Geoff was still deciding — link was provided: https://github.com/workingman/crate/pull/new/fix/mcp-auth-regression). Do NOT open automatically; ask first. Geoff said he's "still thinking about more stuff to add to the branch" (this session's `exec`/`--auto` change is part of that) — don't push for a PR, wait for him.
- [ ] After merge + rebuild, verify a fresh container recreation (`compose down && up -d`) still has the correct `oc`/`opencode` functions (i.e., no more drift, `exec` + `--auto` present) by running `set` again post-recreation.
- [ ] Consider a lightweight guardrail so `/etc/skel-devbox/bashrc.default` in the image can't silently diverge from the committed `bashrc.default` again unnoticed (e.g., a `diff` check in `crate-versions` or a CI step) — not started, just an idea.
- [ ] Commit the `bashrc.default` `exec`/`--auto` change to `fix/mcp-auth-regression` (done this session — verify it landed) and push.
- [ ] The `rm -fr` deny guardrail and AGENTS.md note live in `~/.config/opencode/` (persistent docker-home, outside this git repo) — nothing to commit there, but worth remembering they're not visible in `git diff` for this repo.

## Key Decisions Made
| Decision | Rationale |
|---|---|
| `opencode` stays a raw, unshadowed executable | Simpler mental model — direct binary is always direct binary, no surprises when calling it from scripts/other tools. |
| `oc()` is the single wrapper, carries the mcp-auth socat relay | `opencode mcp auth` binds a fixed loopback callback (`127.0.0.1:19876`) that Docker port-forwarding can't reach; `oc` bridges it via a temporary `socat` relay bound to the container's external IP. |
| ~~No `exec` in `oc()`~~ — **superseded** | Originally avoided because it was surprising Geoff (Ghostty needed "hit a key" to notice the shell/process was gone). Geoff reversed this himself by hot-patching the container and asking for the repo to match — `exec` is back in `oc()`'s final `opencode` call. |
| `oc()` always runs `opencode --auto` (yolo mode) | Geoff's explicit request. Applies only to the primary launch path, not the `mcp auth` cleanup branch. |
| `rm -fr`/`rm -rf` hard-denied via `permission.bash`, not just AGENTS.md prose | `--auto` auto-approves `"ask"` rules; only `"deny"` is still enforced in yolo mode (confirmed via opencode docs). An AGENTS.md instruction alone is a soft ask the model could ignore — the config-level `"deny"` is the actual enforcement layer. AGENTS.md still documents it for clarity. |
| Fix the container/image to match the repo, not the other way around | Repo is source of truth per project convention; the running container had drifted to a newer, unwanted design that was never committed. |
| Hot-patch now, rebuild image soon | Per the repo's own Container Changes workflow: make the real change in the repo (already done), hot-patch the running container immediately for correctness, then rebuild the image so it becomes source of truth again instead of relying on the one-off live edit. |

## Dead Ends / What Didn't Work
- I attempted to hot-patch `/etc/skel-devbox/bashrc.default` directly via the bash tool — blocked, since `sudo` is denied for me per Geoff's global permission rules and the file is root-owned. Correctly deferred to Geoff to run the `sudo tee` command himself.

## Relevant Files
| File | Purpose |
|---|---|
| `bashrc.default` | Repo source for the image's shell defaults; contains the `wrangler()` OAuth-bind wrapper and the `oc()`/`opencode` mcp-auth relay logic. Already correct on `fix/mcp-auth-regression` (commit `11e9bab`). |
| `Dockerfile` (line ~190) | `COPY bashrc.default /etc/skel-devbox/bashrc.default` — this is the only path by which repo changes reach the image. |
| `/etc/skel-devbox/bashrc.default` (in-container, root-owned) | The actual sourced file at shell start; was hot-patched live this session to match repo; still needs the image rebuilt to make this durable. |
| `scripts/crate-build` | Cached incremental build — use this to bake the fix into a fresh image. |
| `scripts/crate-rebuild` | No-cache full rebuild — only if something external changed. |
| `scripts/deploy` | Materializes runtime from repo into `~/.local`; not directly relevant to this fix (image-level, not deploy-level), but part of the overall pipeline. |

## Open Questions / Blockers
- PR for `fix/mcp-auth-regression` has not been opened yet — waiting on Geoff's go-ahead.
- Image has not been rebuilt yet, so the correct wrapper design currently only exists via: (a) the repo commit, and (b) the live hot patch in the running container. A container recreation before rebuilding would revert to the old/regressed behavior.

## Immediate Next Action
Rebuild the `crate` image (`scripts/crate-build`) from `fix/mcp-auth-regression` so the fix survives a container recreation, then decide whether to open/merge the PR.
