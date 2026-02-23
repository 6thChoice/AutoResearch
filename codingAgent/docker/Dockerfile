# Claude Code Sandbox Container with GPU Support
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

LABEL maintainer="codingAgent"
LABEL description="Sandboxed Claude Code execution with GPU support"

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    inotify-tools \
    jq \
    python3 \
    python3-pip \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# App directories
RUN mkdir -p /app/tasks/done /app/reports /app/workspace /app/scripts /app/logs

# Copy scripts
COPY scripts/monitor.py /app/scripts/monitor.py
COPY scripts/on_stop_hook.py /app/scripts/on_stop_hook.py
RUN chmod +x /app/scripts/*.py

# Non-root user
RUN useradd -m -u 1000 -s /bin/bash node && \
    mkdir -p /home/node/.claude && \
    chown -R node:node /home/node /app

# Claude Code settings with Stop hook
RUN echo '{"hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"python3 /app/scripts/on_stop_hook.py","timeout":30}]}]}}' \
    > /home/node/.claude/settings.json && \
    chown node:node /home/node/.claude/settings.json

WORKDIR /app/workspace

ENV NODE_ENV=production
ENV CLAUDE_LOG_LEVEL=debug
ENV FORCE_COLOR=1

USER node

ENTRYPOINT ["python3", "/app/scripts/monitor.py"]
