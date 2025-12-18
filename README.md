# Audio Watchdog

Periodic Audio Integrity Checker (FLAC/MP3/M4A) with Discord Alerts.

## Features
- Scan and verify audio files in specified directories.
- Supports FLAC, MP3, M4A, WAV, OGG, OPUS, APE.
- Logs corrupt files and sends Discord notifications.
- Maintains scan history in SQLite.
- Runs periodically in a Docker container.

## Usage

### 1. Build & Run with Docker Compose
```sh
docker-compose up --build -d
```

### 2. Environment Variables
- `PUID`, `PGID`: User/Group IDs for file permissions.
- `DISCORD_WEBHOOK_URL`: Discord webhook for alerts.
- `MUSIC_DIR`: Directory to scan (default: `/music`).
- `LOG_FILE`: Log file path (default: `/logs/corrupt_files.log`).
- `DB_FILE`: SQLite DB path (default: `/logs/history.db`).
- `RECHECK_DAYS`: Days before rechecking a file (default: 30).
- `LOOP_DELAY`: Seconds between scan cycles (default: 3600).

### 3. Volumes
- `./logs:/logs`: Persist logs and DB.
- `./music:/music`: Your music files.

## Folder Structure
- `scripts/`: Shell scripts for init and checking.
- `Dockerfile`: Container build instructions.
- `docker-compose.yml`: Multi-container orchestration.

## License
MIT
