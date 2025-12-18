# Use the official Alpine image as the base
FROM alpine:latest

# OCI labels
LABEL maintainer="SilverKnightKMA"
LABEL description="Periodic Audio Integrity Checker (FLAC/MP3/M4A) with Discord Alerts"

# Install dependencies
RUN apk add --no-cache \
    flac \
    ffmpeg \
    bash \
    curl \
    jq \
    coreutils \
    procps \
    sqlite \
    shadow \
    su-exec

# Copy scripts
COPY scripts/ /scripts/

# Set permissions
RUN chmod +x /scripts/*.sh

# Define volumes
VOLUME ["/logs", "/music"]

# Entrypoint
ENTRYPOINT ["/scripts/init.sh"]