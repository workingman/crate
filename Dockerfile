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
        curl wget openssh-client dnsutils iputils-ping iproute2 netcat-openbsd traceroute whois \
        git vim less tmux htop jq ripgrep fzf tree file unzip zip rsync \
        python3 python3-pip python3-venv build-essential pkg-config \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# ---------- optional: install a corporate CA for TLS-intercepting proxies (Cloudflare WARP, Zscaler, etc.) ----------
# Provided via BuildKit secret mount so the cert is NEVER copied into the build context
# (and therefore can't accidentally be committed to a public repo).
#
# Usage:  docker build --secret id=corp-ca,src=/path/to/your-corp-ca.pem ...
# Skipped silently if no secret is provided.
RUN --mount=type=secret,id=corp-ca,required=false \
    if [ -s /run/secrets/corp-ca ]; then \
        cp /run/secrets/corp-ca /usr/local/share/ca-certificates/corp-ca.crt && \
        update-ca-certificates && \
        echo "Installed corporate CA cert(s)."; \
    else \
        echo "No corp CA secret provided; using default trust store."; \
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
# OrbStack's IPv6 port forwarding has flaky data delivery; IPv4 is rock-solid.
# Without this, wrangler (and other Node tools) bind to [::1] and OAuth
# callbacks from the Mac browser never get their HTTP request bytes delivered.
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

# ---------- HashiCorp Terraform ----------
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
         | gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
         > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

# ---------- kubectl (Kubernetes apt repo) ----------
# Pin to a stable minor; bump as needed. kubectl is forward-compatible across most operations.
ARG K8S_MINOR=v1.32
RUN curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
         | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
         > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update && apt-get install -y --no-install-recommends kubectl \
    && rm -rf /var/lib/apt/lists/*

# ---------- helm ----------
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---------- cloudflared (Cloudflare Tunnel client) ----------
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL -o /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" \
    && chmod +x /usr/local/bin/cloudflared

# ---------- wrangler (Cloudflare); claude-code + opencode are installed at the very end of the file ----------
RUN npm install -g --omit=dev wrangler

# ---------- xdg-open shim ----------
# The container has no browser. This shim replaces xdg-open so tools like
# wrangler don't fail when they try to launch a browser — it prints the URL
# for the user to open manually on their Mac, then exits 0 so the tool's
# OAuth callback listener stays alive. Port bindings in compose.yaml route
# the callback back into the container automatically.
COPY xdg-open /usr/local/bin/xdg-open
RUN chmod 0755 /usr/local/bin/xdg-open

# ---------- skel files + entrypoint ----------
RUN mkdir -p /etc/skel-devbox
COPY bashrc.default   /etc/skel-devbox/bashrc.default
COPY profile.default  /etc/skel-devbox/profile.default
COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# ---------- user (build args last so UID/GID changes don't bust upstream cache) ----------
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

# ---------- VOLATILE (last so version bumps cause minimal rebuild) ----------
# claude-code and opencode ship near-daily. Placed after user creation but before
# USER directive so the global npm install runs as root. Re-running this layer
# is the only work needed for a routine "pick up new versions" rebuild.
# HOME is intentionally NOT set yet here — npm would otherwise write its cache
# to /home/${USERNAME}/.npm as root and lock the user out of their own home.
RUN npm install -g --omit=dev @anthropic-ai/claude-code opencode-ai

ENV HOME=/home/${USERNAME}
WORKDIR /home/${USERNAME}
USER ${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
