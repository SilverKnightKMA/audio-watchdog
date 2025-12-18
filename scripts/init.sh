#!/bin/sh
set -e

# Load ENV or default
PGID=${PGID:-65536}
PUID=${PUID:-1031}

echo "[INFO] Initializing container with UID: $PUID / GID: $PGID"

# Create Group if not exists
if ! getent group "$PGID" >/dev/null; then
    groupadd -g "$PGID" -o flacgroup
fi

# Create User if not exists
if ! id -u "$PUID" >/dev/null 2>&1; then
    useradd -u "$PUID" -g "$PGID" -m -o -s /bin/bash flacuser
fi

# Fix permissions
chown -R "$PUID":"$PGID" /logs

# Switch user and execute main script
echo "[INFO] Starting Audio Watchdog service..."
exec su-exec "$PUID":"$PGID" /bin/bash /scripts/check.sh