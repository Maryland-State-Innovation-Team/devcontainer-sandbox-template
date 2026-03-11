# -------------------------------------------------------
# Claude Code Secure Devcontainer — Governor's Office
# Based on Anthropic's official reference devcontainer.
# -------------------------------------------------------

FROM node:20

ARG CLAUDE_CODE_VERSION=latest

# Signals to Claude Code that it's running inside a devcontainer.
ENV DEVCONTAINER=true

# Install system tools.
# ipset, iproute2, dnsutils, aggregate: required by init-firewall.sh
#   to build IP allowlists by resolving domain names at startup.
# gh: GitHub CLI, used by init-firewall.sh to fetch GitHub's IP ranges.
# jq: JSON parser, used by init-firewall.sh to parse the GitHub API response.
# sudo: lets the node user run init-firewall.sh as root at container start.
# python3, python3-pip: available if Claude needs to run Python code.
# nano, vim: basic editors available in the terminal.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    jq \
    sudo \
    gh \
    python3 \
    python3-pip \
    nano \
    vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Give the npm global directory to the node user so Claude can
# install packages without needing root.
RUN mkdir -p /usr/local/share/npm-global && \
    chown -R node:node /usr/local/share

# Install Claude Code globally.
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Create the workspace and Claude config directories.
RUN mkdir -p /workspace /home/node/.claude && \
    chown -R node:node /workspace /home/node/.claude

# -------------------------------------------------------
# Firewall setup.
# The script is copied to a fixed absolute path so the
# sudoers entry can reference it exactly. This is what
# allows `sudo /usr/local/bin/init-firewall.sh` to run
# without prompting for a password.
# -------------------------------------------------------
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh && \
    echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
    > /etc/sudoers.d/node-firewall && \
    chmod 0440 /etc/sudoers.d/node-firewall

# -------------------------------------------------------
# Security: run as non-root for day-to-day operations.
# The node user has sudo access only for the firewall
# script above — nothing else.
# -------------------------------------------------------
USER node
WORKDIR /workspace
