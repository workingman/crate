# Crate Working Rules

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
- Runtime noise from Docker, OrbStack, cert injection, and `/tmp` scratch files is normal and should be distinguished from intentional system drift.
