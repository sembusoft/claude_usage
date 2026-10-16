FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force

WORKDIR /app
COPY poller.py index.html icon.svg /app/

ENV TZ=Europe/Berlin \
    PORT=8088 \
    POLL_SECONDS=300 \
    CLAUDE_CONFIG_DIR=/data/claude

EXPOSE 8088
CMD ["python3", "-u", "/app/poller.py"]
