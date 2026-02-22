# Claude Code Docker Container with GPU Support
# Based on NVIDIA CUDA + Node.js

FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

LABEL maintainer="Claude Code Agent System"
LABEL description="Container for running Claude Code with GPU support"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    inotify-tools \
    jq \
    uuid-runtime \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    python3-yaml \
    bsdutils \
    tmux \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create app directory structure
RUN mkdir -p /app/volumes/commands/pending \
    /app/volumes/commands/processed \
    /app/volumes/reports/pending \
    /app/volumes/reports/archived \
    /app/volumes/workspace \
    /app/volumes/sessions \
    /app/volumes/claude-home \
    /app/volumes/logs \
    /app/logs \
    /app/scripts \
    /app/config \
    /app/templates \
    /app/templates/decisions

# Copy monitoring scripts
COPY scripts/container/monitor.sh /app/scripts/monitor.sh
COPY scripts/container/session.sh /app/scripts/session.sh
COPY config/settings.json /app/config/settings.json

# Copy agent memory management templates
COPY docker/templates/.clauderc /home/node/.clauderc
COPY docker/templates/AGENT_MISSION.md /app/templates/AGENT_MISSION.md
COPY docker/templates/decisions/ /app/templates/decisions/
COPY docker/templates/validate_handover.py /app/scripts/validate_handover.py

# Copy context management system
COPY docker/context/ /app/templates/context/
RUN chmod +x /app/templates/context/combine_context.py

# Make scripts executable
RUN chmod +x /app/scripts/*.sh && \
    chmod +x /app/scripts/validate_handover.py

# Create agent user (non-root for --dangerously-skip-permissions)
RUN useradd -m -u 1000 -s /bin/bash node && \
    echo "node:agent" | chpasswd && \
    mkdir -p /home/node/.claude && \
    chown -R node:node /home/node && \
    chown -R node:node /app && \
    chown node:node /home/node/.clauderc

# Ensure log file exists and is writable
RUN touch /app/logs/monitor.log && \
    touch /app/logs/claude-output.log && \
    touch /app/logs/claude-terminal.txt && \
    chown node:node /app/logs/monitor.log /app/logs/claude-output.log /app/logs/claude-terminal.txt

# Set working directory
WORKDIR /app/volumes/workspace

# Set environment variables
ENV NODE_ENV=production
ENV CLAUDE_CODE_WORKSPACE=/app/volumes/workspace
# Enable verbose logging for Claude Code
ENV CLAUDE_LOG_LEVEL=debug
ENV DEBUG=claude:*
ENV FORCE_COLOR=1

# Switch to node user (non-root)
USER node

# Entry point - start the monitor script
ENTRYPOINT ["/app/scripts/monitor.sh"]
