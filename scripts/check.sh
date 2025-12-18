#!/bin/bash

# Configuration
TARGET_DIRS="${MUSIC_DIR:-/music}"
LOG_FILE="${LOG_FILE:-/logs/corrupt_files.log}"
DB_PATH="${DB_FILE:-/logs/history.db}"
WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
DAYS=${RECHECK_DAYS:-30}
EXPIRY_SECONDS=$((DAYS * 86400))
LOOP_SLEEP=${LOOP_DELAY:-3600}

# Initialize Database
init_db() {
    sqlite3 -batch -cmd ".timeout 2000" "$DB_PATH" "CREATE TABLE IF NOT EXISTS file_checks (
        filepath TEXT PRIMARY KEY,
        last_checked INTEGER,
        status TEXT
    );"
}

# Escape single quotes for SQL
escape_string() {
    echo -n "$1" | sed "s/'/''/g"
}

# Send Notification
send_discord_alert() {
    [ -z "$WEBHOOK_URL" ] && return
    
    local filepath="$1"
    local error_msg="$2"
    local filename=$(basename "$filepath")
    local filesize="Unknown"
    [ -f "$filepath" ] && filesize=$(du -ah "$filepath" | cut -f1)

    local json_payload=$(jq -n \
        --arg title "❌ AUDIO CORRUPTION DETECTED" \
        --arg filename "$filename" \
        --arg filepath "$filepath" \
        --arg filesize "$filesize" \
        --arg error "$error_msg" \
        '{
            username: "Audio Watchdog",
            embeds: [{
                title: $title,
                color: 15548997,
                fields: [
                    {name: "File", value: $filename, inline: true},
                    {name: "Size", value: $filesize, inline: true},
                    {name: "Path", value: $filepath},
                    {name: "Error", value: ("```" + $error + "```")}
                ]
            }]
        }')
    curl -s -H "Content-Type: application/json" -X POST -d "$json_payload" "$WEBHOOK_URL" > /dev/null
}

# Verify file integrity
check_file() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"
    
    if [ "$ext" == "flac" ]; then
        timeout 120s flac -t "$file" 2>&1
    else
        timeout 120s ffmpeg -v error -xerror -i "$file" -f null - 2>&1
    fi
}

# Prune database entries for deleted files
cleanup_db() {
    echo "[INFO] Pruning database..."
    local temp_list=$(mktemp)
    sqlite3 -batch -noheader "$DB_PATH" "SELECT filepath FROM file_checks;" > "$temp_list"
    
    local deleted_count=0
    while IFS= read -r db_path; do
        if [ ! -f "$db_path" ]; then
            local safe_path=$(escape_string "$db_path")
            sqlite3 -batch "$DB_PATH" "DELETE FROM file_checks WHERE filepath = '$safe_path';"
            deleted_count=$((deleted_count + 1))
        fi
    done < "$temp_list"
    rm "$temp_list"
    
    [ "$deleted_count" -gt 0 ] && echo "[INFO] Removed $deleted_count obsolete entries."
}

# Print Summary
show_statistics() {
    echo "[$(date)] [STATS] Summary after cleanup:"
    local total=$(sqlite3 -batch "$DB_PATH" "SELECT count(*) FROM file_checks;")
    local corrupt=$(sqlite3 -batch "$DB_PATH" "SELECT count(*) FROM file_checks WHERE status = 'CORRUPT';")
    echo "   -----------------------------------------"
    echo "   Total tracked files : $total"
    echo "   Corrupt files       : $corrupt"
    echo "   -----------------------------------------"
    echo "   Breakdown by extension:"
    sqlite3 -batch -noheader "$DB_PATH" "SELECT filepath FROM file_checks;" | \
    sed 's/.*\.//' | \
    tr '[:upper:]' '[:lower:]' | \
    sort | uniq -c | sort -nr | \
    while read count ext; do
        echo "       - $ext : $count file(s)"
    done
    echo "   -----------------------------------------"
}

# Main Loop
init_db
echo "[INFO] Service Started. Targets: $TARGET_DIRS"

while true; do
    echo "[INFO] Starting Scan Cycle: $(date)"
    
    TEMP_LIST=$(mktemp)
    find $TARGET_DIRS -type f \( -iname "*.flac" -o -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.ape" \) 2>/dev/null > "$TEMP_LIST"
    
    TOTAL_FILES=$(wc -l < "$TEMP_LIST")
    CURRENT_COUNT=0
    
    if [ "$TOTAL_FILES" -gt 0 ]; then
        while IFS= read -r file; do
            CURRENT_COUNT=$((CURRENT_COUNT + 1))
            CURRENT_TIME=$(date +%s)
            SAFE_FILE=$(escape_string "$file")
            
            LAST_CHECK=$(sqlite3 -batch "$DB_PATH" "SELECT last_checked FROM file_checks WHERE filepath = '$SAFE_FILE';")
            [ -z "$LAST_CHECK" ] && LAST_CHECK=0
            
            if [ $((CURRENT_TIME - LAST_CHECK)) -gt "$EXPIRY_SECONDS" ]; then
                PERCENT=$((CURRENT_COUNT * 100 / TOTAL_FILES))
                echo "[SCAN] $PERCENT% - Checking: $(basename "$file")"
                
                if output=$(check_file "$file"); then
                    sqlite3 -batch "$DB_PATH" "INSERT OR REPLACE INTO file_checks (filepath, last_checked, status) VALUES ('$SAFE_FILE', $CURRENT_TIME, 'OK');"
                else
                    echo "[ERROR] CORRUPT: $file" | tee -a "$LOG_FILE"
                    exit_code=$?
                    short_error=$([ $exit_code -eq 124 ] && echo "TIMEOUT > 120s" || echo "$output" | tail -n 3)
                    
                    send_discord_alert "$file" "$short_error"
                    sqlite3 -batch "$DB_PATH" "INSERT OR REPLACE INTO file_checks (filepath, last_checked, status) VALUES ('$SAFE_FILE', $CURRENT_TIME, 'CORRUPT');"
                fi
            fi
        done < "$TEMP_LIST"
    fi
    rm "$TEMP_LIST"
    
    cleanup_db
    show_statistics
    
    echo "[INFO] Cycle finished. Sleeping for ${LOOP_SLEEP}s."
    sleep $LOOP_SLEEP
done