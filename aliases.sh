# Source from ~/.zshrc (or ~/.bashrc) on the macOS host to get crate aliases.
#
#   echo '[ -f "$HOME/dev/crate/aliases.sh" ] && . "$HOME/dev/crate/aliases.sh"' >> ~/.zshrc
#
# `crate`           — launch a fresh container shell (rm on exit)
# `crate-build`     — incremental build of the image
# `crate-rebuild`   — full no-cache rebuild
# `crate-versions`  — print versions of major tools in the current image
# `crate-update`    — pull latest base, no-cache rebuild, show before/after versions
# `crate-check-ca`  — diagnose the corporate CA cert bundle (file/parse/curl tests)
#
# Corp CA: if $CRATE_CORP_CA points to a readable file (default ~/cloudflare-ca.pem),
# crate-build/rebuild/update pass it via `docker build --secret` so the cert is
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

# Internal: emit --secret args if the corp CA file is present.
_crate_secret_args() {
    if [ -r "$CRATE_CORP_CA" ]; then
        printf -- '--secret\nid=corp-ca,src=%s\n' "$CRATE_CORP_CA"
    fi
}

crate-build() {
    local -a secret_args=()
    while IFS= read -r line; do
        [ -n "$line" ] && secret_args+=("$line")
    done < <(_crate_secret_args)
    docker build \
        "${secret_args[@]}" \
        --build-arg UID=$(id -u) \
        --build-arg GID=$(id -g) \
        -t "$CRATE_IMAGE" "$CRATE_DIR"
}

crate-rebuild() {
    local -a secret_args=()
    while IFS= read -r line; do
        [ -n "$line" ] && secret_args+=("$line")
    done < <(_crate_secret_args)
    docker build --no-cache \
        "${secret_args[@]}" \
        --build-arg UID=$(id -u) \
        --build-arg GID=$(id -g) \
        -t "$CRATE_IMAGE" "$CRATE_DIR"
}

# Print versions of major installed tools in the current image.
crate-versions() {
    if ! docker image inspect "$CRATE_IMAGE" >/dev/null 2>&1; then
        echo "(no image $CRATE_IMAGE yet — run crate-build first)"
        return 1
    fi
    docker run --rm "$CRATE_IMAGE" bash -lc '
        printf "%-13s %s\n" "node"        "$(node -v 2>/dev/null)"
        printf "%-13s %s\n" "npm"         "$(npm -v 2>/dev/null)"
        printf "%-13s %s\n" "python3"     "$(python3 --version 2>&1 | cut -d" " -f2)"
        printf "%-13s %s\n" "gh"          "$(gh --version 2>/dev/null | head -1 | awk "{print \$3}")"
        printf "%-13s %s\n" "wrangler"    "$(wrangler --version 2>&1 | tail -1)"
        printf "%-13s %s\n" "claude-code" "$(claude --version 2>&1 | head -1)"
        printf "%-13s %s\n" "opencode"    "$(opencode --version 2>&1 | tail -1)"
        printf "%-13s %s\n" "terraform"   "$(terraform -v 2>&1 | head -1 | awk "{print \$2}")"
        printf "%-13s %s\n" "kubectl"     "$(kubectl version --client 2>&1 | head -1 | awk "{print \$3}")"
        printf "%-13s %s\n" "helm"        "$(helm version --short 2>&1)"
        printf "%-13s %s\n" "cloudflared" "$(cloudflared --version 2>&1 | head -1 | awk "{print \$3}")"
        printf "%-13s %s\n" "yq"          "$(yq --version 2>&1 | awk "{print \$NF}")"
        printf "%-13s %s\n" "jq"          "$(jq --version 2>&1)"
        printf "%-13s %s\n" "ripgrep"     "$(rg --version 2>&1 | head -1 | awk "{print \$2}")"
    '
}

# Diagnose the corporate CA cert bundle (file presence, parse, curl-through-MITM test).
crate-check-ca() {
    bash "$CRATE_DIR/check-corp-ca.sh" "$@"
}

# Pull latest base image + no-cache rebuild + show version delta.
crate-update() {
    local -a secret_args=()
    while IFS= read -r line; do
        [ -n "$line" ] && secret_args+=("$line")
    done < <(_crate_secret_args)

    echo "=== current image versions ==="
    crate-versions 2>&1 || echo "(no prior image; first-time build)"
    echo

    echo "=== building with --pull --no-cache ==="
    docker build --pull --no-cache \
        "${secret_args[@]}" \
        --build-arg UID=$(id -u) \
        --build-arg GID=$(id -g) \
        -t "$CRATE_IMAGE" "$CRATE_DIR" || return 1
    echo

    echo "=== new image versions ==="
    crate-versions
}
