# Source from ~/.zshrc (or ~/.bashrc) on the macOS host to get crate aliases.
#
#   echo '[ -f "$HOME/dev/crate/aliases.sh" ] && . "$HOME/dev/crate/aliases.sh"' >> ~/.zshrc
#
# `crate`         — launch a fresh container shell (rm on exit)
# `crate-build`   — incremental rebuild of the image
# `crate-rebuild` — full no-cache rebuild

export CRATE_DIR="$HOME/dev/crate"
export CRATE_IMAGE="crate:latest"

alias crate='docker run --rm -it --init \
  --hostname crate \
  -v "$HOME/docker-home:/home/geoff" \
  -v "$HOME/dev:/home/geoff/dev" \
  -w /home/geoff \
  "$CRATE_IMAGE"'

alias crate-build='docker build \
  --build-arg UID=$(id -u) \
  --build-arg GID=$(id -g) \
  -t "$CRATE_IMAGE" "$CRATE_DIR"'

alias crate-rebuild='docker build --no-cache \
  --build-arg UID=$(id -u) \
  --build-arg GID=$(id -g) \
  -t "$CRATE_IMAGE" "$CRATE_DIR"'
