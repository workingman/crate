# Personal Linux workstation image.
# See twinkling-yawning-crown.md plan for design notes.
# Build:  docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t devbox:latest .
# Run:    docker run --rm -it -v ~/docker-home:/home/geoff -v ~/dev:/home/geoff/dev devbox:latest

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------- base apt packages ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash sudo locales ca-certificates gnupg lsb-release apt-transport-https \
        curl wget openssh-client dnsutils iputils-ping iproute2 netcat-openbsd traceroute whois \
        git vim less tmux htop jq ripgrep fzf tree file unzip zip rsync \
        python3 python3-pip python3-venv build-essential pkg-config \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# yq is not in default Ubuntu repos; install Mike Farah's standalone binary (multi-arch).
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" \
    && chmod +x /usr/local/bin/yq

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

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

# ---------- npm globals: wrangler (Cloudflare) + opencode (TUI AI assistant) ----------
RUN npm install -g --omit=dev wrangler opencode-ai

# ---------- skel files + entrypoint ----------
RUN mkdir -p /etc/skel-devbox
COPY bashrc.default   /etc/skel-devbox/bashrc.default
COPY profile.default  /etc/skel-devbox/profile.default
COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# ---------- user (build args last so UID/GID changes don't bust upstream cache) ----------
ARG UID=501
ARG GID=20
ARG USERNAME=geoff

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

ENV HOME=/home/${USERNAME}
ENV PATH=/home/${USERNAME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /home/${USERNAME}
USER ${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
