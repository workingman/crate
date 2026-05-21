# Source from ~/.zshrc (or ~/.bashrc) on the macOS host to get crate aliases.
#
#   echo '[ -f "$HOME/dev/crate/aliases.sh" ] && . "$HOME/dev/crate/aliases.sh"' >> ~/.zshrc
#
# `crate`         — launch a fresh container shell (rm on exit)
# `crate-build`   — incremental build of the image
# `crate-rebuild` — full no-cache rebuild
#
# Corp CA: if $CRATE_CORP_CA points to a readable file (default ~/cloudflare-ca.pem),
# crate-build and crate-rebuild pass it via `docker build --secret` so the cert is
# installed into the image's trust store without ever entering the build context.
# Leave the file absent on non-corporate machines; the Dockerfile skips silently.

export CRATE_DIR="$HOME/dev/crate"
export CRATE_IMAGE="crate:latest"
: "${CRATE_CORP_CA:=$HOME/cloudflare-ca.pem}"

alias crate='docker run --rm -it --init \
  --hostname crate \
  -v "$HOME/docker-home:/home/geoff" \
  -v "$HOME/dev:/home/geoff/dev" \
  -w /home/geoff \
  "$CRATE_IMAGE"'

# Functions (not aliases) so we can conditionally inject --secret.
crate-build() {
    local secret_args=()
    if [ -r "$CRATE_CORP_CA" ]; then
        secret_args=(--secret "id=corp-ca,src=$CRATE_CORP_CA")
    fi
    docker build \
        "${secret_args[@]}" \
        --build-arg UID=$(id -u) \
        --build-arg GID=$(id -g) \
        -t "$CRATE_IMAGE" "$CRATE_DIR"
}

crate-rebuild() {
    local secret_args=()
    if [ -r "$CRATE_CORP_CA" ]; then
        secret_args=(--secret "id=corp-ca,src=$CRATE_CORP_CA")
    fi
    docker build --no-cache \
        "${secret_args[@]}" \
        --build-arg UID=$(id -u) \
        --build-arg GID=$(id -g) \
        -t "$CRATE_IMAGE" "$CRATE_DIR"
}
