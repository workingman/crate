# Crate Working Rules

## Source vs. Runtime (Deployment Model)

Runtime services must NEVER depend on the git working tree. A repo can be on a
branch, mid-rebase, dirty, moved, or deleted — login-time services and entry
points must not care.

- **`~/dev/crate`** = source of truth. Editable, git-tracked, allowed to be broken.
- **`~/.local/opt/crate`** = deployed runtime artifacts (compose.yaml, .env,
  `.deployed-from` provenance stamp). What services actually point at.
- **`~/.local/bin`** = deployed entry points + helpers (`crate-connect`,
  `docker-bin`), already on PATH.
- **`~/docker-home`** = data plane (container home). Distinct from the control
  plane above.
- **`~/Library/LaunchAgents`** = launchd's required location for agents; the
  plist there points into `~/.local`, never `~/dev`.

Layout follows XDG-ish convention: `~/.local/bin` for executables, `~/.local/opt/<app>`
for self-contained deployment roots (mirrors system `/opt`).

### Deploy flow

`scripts/deploy` materializes the runtime subset from the repo into `~/.local`,
stamps the git SHA into `~/.local/opt/crate/.deployed-from`, installs/reloads the
launchd agent. Runtime never reads the repo directly.

- Edit repo → run `scripts/deploy` to push changes into runtime.
- Use **copies, not symlinks** — true decoupling is the whole point. The SHA
  stamp is how you detect "repo changed but not deployed" drift.

## Container Changes

- If it should survive rebuilds, change the repo.
- If you change the repo, ask whether the running container also needs a temporary hot patch now.
- If you hot-patch the running container, treat it as temporary until the image is rebuilt.
- After any hot patch, record it immediately so future-you does not have to do forensic science on a snowflake container.

## Practical Flow

1. Make the real change in `~/dev/crate`.
2. Decide whether the current running container needs the fix immediately.
3. If yes, hot-patch the running container too.
4. Rebuild soon after so the image becomes the source of truth again.
5. Verify the running container is now correct because of the image, not because of one-off live edits.

## Drift Model

- Changes under mounted paths like `~/docker-home` and `~/dev` are expected persistent state.
- Changes under container-local paths like `/usr/local/bin`, `/etc`, `/usr`, installed packages, or generated system config should be assumed ephemeral unless they came from the image build.
- Runtime noise from Docker, Colima, cert injection, and `/tmp` scratch files is normal and should be distinguished from intentional system drift.
