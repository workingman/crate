# Personal Linux workstation image.
# See twinkling-yawning-crown.md plan for design notes.
# Build:  echo "UID=$(id -u)" > .env && echo "GID=$(id -g)" >> .env && docker compose build
# Run:    docker compose run --rm crate

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------- restore docs/man pages/locales (Ubuntu's unminimize) ----------
# The base image is "minimized": man pages stripped, /usr/bin/man replaced with
# a placeholder stub, locale .mo files removed, /usr/share/doc gutted.
# `unminimize` is Ubuntu's official path to undo all of that — it rewrites the
# dpkg path-exclude rules, reinstalls everything, restores the real man-db,
# and rebuilds the mandb index. Costs ~50-100 MB; worth it for working docs.
RUN yes 2>/dev/null | unminimize; rm -rf /var/lib/apt/lists/*

# ---------- base apt packages ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash sudo locales ca-certificates gnupg lsb-release apt-transport-https \
        curl wget openssh-client dnsutils iputils-ping iproute2 net-tools netcat-openbsd socat traceroute whois \
        git vim less tmux htop jq ripgrep fzf tree file unzip zip rsync pandoc \
        python3 python3-pip python3-venv build-essential pkg-config cron \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# ---------- corporate CA (build-time injection) ----------
# Behind a TLS-intercepting proxy (Cloudflare WARP, Zscaler)? The corp CA must
# be in the trust store BEFORE any curl/apt-over-https calls below, or they
# fail with "self-signed certificate in certificate chain".
#
# A CA cert is PUBLIC (not a secret), so we pass it as a base64 build arg via
# .env. Empty by default → skipped on clean machines (home Mac, CI).
# See README "Corporate CA cert" for how to regenerate CORP_CA_B64.
ARG CORP_CA_B64=""
RUN if [ -n "$CORP_CA_B64" ]; then \
        echo "$CORP_CA_B64" | base64 -d > /usr/local/share/ca-certificates/corp-ca.crt && \
        update-ca-certificates && \
        echo "Installed corporate CA cert."; \
    else \
        echo "No corp CA provided; using default trust store."; \
    fi

# yq is not in default Ubuntu repos; install Mike Farah's standalone binary (multi-arch).
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" \
    && chmod +x /usr/local/bin/yq

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# Node.js doesn't use the system CA store — point it at the corp CA so
# wrangler and other Node tools work through Cloudflare WARP / TLS inspection.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
# Force Node DNS to prefer IPv4 so 'localhost' binds to 127.0.0.1 (not ::1).
# Note: Docker port forwarding (any runtime — Colima, Docker Desktop, etc.)
# only reaches listeners bound to 0.0.0.0 inside the container, NOT loopback
# (127.0.0.1 or ::1), because published-port traffic arrives via the container's
# external interface. For OAuth callback tools, pass --callback-host 0.0.0.0
# explicitly (see the wrangler wrapper in bashrc.default). This flag is kept for
# general IPv4 preference; it does not fix the loopback-bind limitation on its own.
ENV NODE_OPTIONS=--dns-result-order=ipv4first

# ---------- Node.js LTS (NodeSource) ----------
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ---------- GitHub CLI ----------
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ---------- GitLab CLI ----------
# packages.gitlab.com APT repo is gone; install from GitLab's generic package registry instead.
RUN ARCH=$(dpkg --print-architecture) \
    && GLAB_VERSION=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?per_page=1" \
         | python3 -c "import sys,json; r=json.load(sys.stdin); print(r[0]['tag_name'].lstrip('v'))") \
    && curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/glab_${GLAB_VERSION}_linux_${ARCH}.tar.gz" \
         | tar -xz -C /usr/local/bin --strip-components=1 bin/glab \
    && chmod +x /usr/local/bin/glab

# ---------- HashiCorp Terraform + Vault CLI ----------
# Vault CLI talks to the separate `vault` container (see ~/dev/vault) over
# the shared `crate-net` Docker network — VAULT_ADDR is set in compose.yaml.
# Same trusted apt repo already in use for Terraform, no new trust anchor.
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
         | gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
         > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y --no-install-recommends terraform vault \
    && rm -rf /var/lib/apt/lists/*


# ---------- Google Cloud CLI ----------
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
         | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
         > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# ---------- cloudflared (Cloudflare Tunnel client) ----------
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL -o /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" \
    && chmod +x /usr/local/bin/cloudflared

# ---------- rclone ----------
# Swiss-army knife for cloud storage — native R2, GCS, S3 support. Great for demos.
RUN curl -fsSL https://rclone.org/install.sh | bash

# ---------- trivy (Aqua Security vulnerability scanner) ----------
# Scans npm deps, container images, IaC files (Terraform, Dockerfiles), and secrets.
# Open source, no account required. Complements Cloudflare runtime security.
RUN curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
         | gpg --dearmor -o /etc/apt/keyrings/trivy.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
         > /etc/apt/sources.list.d/trivy.list \
    && apt-get update && apt-get install -y --no-install-recommends trivy \
    && rm -rf /var/lib/apt/lists/*

# ---------- flarectl (Cloudflare CLI) ----------
# Released from github.com/cloudflare/cloudflare-go under the legacy v0.x tag scheme.
RUN ARCH=$(dpkg --print-architecture) \
    && FLARECTL_VERSION=$(curl -fsSL "https://api.github.com/repos/cloudflare/cloudflare-go/releases" \
         | python3 -c "import sys,json; releases=[r for r in json.load(sys.stdin) if r['tag_name'].startswith('v0.')]; print(releases[0]['tag_name'].lstrip('v'))") \
    && curl -fsSL "https://github.com/cloudflare/cloudflare-go/releases/download/v${FLARECTL_VERSION}/flarectl_${FLARECTL_VERSION}_linux_${ARCH}.tar.gz" \
         | tar -xz -C /usr/local/bin flarectl \
    && chmod +x /usr/local/bin/flarectl

# ---------- wrangler + miniflare (Cloudflare); claude-code + opencode + pi at end of file ----------
RUN npm install -g --omit=dev wrangler miniflare

# ---------- varlock (AI-safe env/secrets manager) ----------
RUN curl -sSfL https://varlock.dev/install.sh | sh -s

# ---------- user (build args late so UID/GID changes don't bust upstream tool cache) ----------
ARG UID=501
ARG GID=20
ARG USERNAME=crate

# Handle GID-already-exists case (Ubuntu's 'dialout' = GID 20):
#   - If a group with the requested GID exists, rename it to USERNAME.
#   - Else create a fresh group.
# Then create the user pointing at that GID.
RUN set -eux; \
    existing_group=$(getent group "${GID}" | cut -d: -f1 || true); \
    if [ -n "${existing_group}" ] && [ "${existing_group}" != "${USERNAME}" ]; then \
        groupmod -n "${USERNAME}" "${existing_group}"; \
    elif [ -z "${existing_group}" ]; then \
        groupadd -g "${GID}" "${USERNAME}"; \
    fi; \
    if id -u "${USERNAME}" >/dev/null 2>&1; then \
        usermod -u "${UID}" -g "${GID}" "${USERNAME}"; \
    else \
        useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${USERNAME}"; \
    fi; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}; \
    chmod 0440 /etc/sudoers.d/${USERNAME}

ENV PATH=/home/${USERNAME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ---------- VOLATILE: npm globals (claude-code + opencode + pi ship near-daily) ----------
# Runs as root (before USER); HOME intentionally NOT set so npm doesn't write its
# cache into the user's home as root and lock them out. A routine "pick up new
# versions" rebuild only reruns this layer (and the instant COPY layers below it).
RUN npm install -g --omit=dev @anthropic-ai/claude-code opencode-ai @earendil-works/pi-coding-agent

# ---------- baked-in files (LAST so edits are cheap) ----------
# These COPY layers sit below every tool install, user creation, and the npm
# layer. Editing a dotfile, the xdg-open shim, or entrypoint.sh busts only these
# near-instant layers — nothing expensive above rebuilds. Must precede USER so
# the files land as root.
#
# xdg-open shim: the container has no browser, so this prints the URL to open on
# the Mac and exits 0 so a tool's OAuth callback listener stays alive. Port
# bindings in compose.yaml route the callback back into the container.
COPY xdg-open /usr/local/bin/xdg-open
RUN chmod 0755 /usr/local/bin/xdg-open

COPY mem-check /usr/local/bin/mem-check
RUN chmod 0755 /usr/local/bin/mem-check

RUN mkdir -p /etc/skel-devbox
COPY bashrc.default   /etc/skel-devbox/bashrc.default
COPY profile.default  /etc/skel-devbox/profile.default
COPY tui.json         /etc/skel-devbox/tui.json
COPY glab-config.yml  /etc/skel-devbox/glab-config.yml
COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENV HOME=/home/${USERNAME}
WORKDIR /home/${USERNAME}
USER ${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
