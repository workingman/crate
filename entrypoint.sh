#!/usr/bin/env bash
# Seed default dotfiles into the persistent home on first run.
# Idempotent — only writes files that don't already exist, so user edits survive.
set -euo pipefail

SKEL=/etc/skel-devbox

if [ -d "$SKEL" ]; then
    for name in bashrc profile; do
        target="$HOME/.${name}"
        source="$SKEL/${name}.default"
        if [ ! -e "$target" ] && [ -f "$source" ]; then
            cp "$source" "$target"
        fi
    done
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

exec "$@"
