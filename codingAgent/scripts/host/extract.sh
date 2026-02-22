#!/bin/bash
# Host Machine Extraction Script
# Monitors reports directory and logs new reports

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR"))"
REPORTS_PENDING="$PROJECT_ROOT/volumes/reports/pending"
REPORTS_ARCHIVED="$PROJECT_ROOT/volumes/reports/archived"
LOG_FILE="$PROJECT_ROOT/logs/host-monitor.log"
POLL_INTERVAL="${POLL_INTERVAL:-2}"  # seconds

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Extract summary from report MD file
extract_summary() {
    local file="$1"
    awk '
        /^## 执行摘要/ { in_summary=1; next }
        in_summary && /^## / { exit }
        in_summary && NF { print }
    ' "$file"
}

# Extract status from frontmatter
extract_status() {
    local file="$1"
    awk '
        /^---$/ { in_fm++; next }
        in_fm == 1 && /^status:/ {
            sub(/^status:[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

# Extract session ID from frontmatter
extract_session_id() {
    local file="$1"
    awk '
        /^---$/ { in_fm++; next }
        in_fm == 1 && /^session_id:/ {
            sub(/^session_id:[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

# Process a report file
process_report() {
    local report_file="$1"
    local filename=$(basename "$report_file")

    log "INFO" "=== Processing report: $filename ==="

    # Extract key information
    local status=$(extract_status "$report_file")
    local session_id=$(extract_session_id "$report_file")
    local summary=$(extract_summary "$report_file")

    # Log the summary
    log "INFO" "Report: $filename | Status: $status | Session: $session_id"
    log "INFO" "Summary: $summary"

    # Archive the report
    local archive_path="$REPORTS_ARCHIVED/$filename"
    mv "$report_file" "$archive_path"
    log "INFO" "Report archived to: $archive_path"
    log "INFO" "================================"
}

# Main monitoring loop
main() {
    log "INFO" "=== Host Monitor Starting ==="
    log "INFO" "Reports directory: $REPORTS_PENDING"
    log "INFO" "Archive directory: $REPORTS_ARCHIVED"
    log "INFO" "Log file: $LOG_FILE"

    # Process any existing pending reports
    for report_file in "$REPORTS_PENDING"/*.md; do
        if [ -f "$report_file" ]; then
            process_report "$report_file"
        fi
    done

    # Check if inotify is available
    if command -v inotifywait &> /dev/null; then
        log "INFO" "Using inotify for file watching"
        watch_with_inotify
    else
        log "INFO" "Using polling for file watching (interval: ${POLL_INTERVAL}s)"
        watch_with_polling
    fi
}

# Watch using inotify
watch_with_inotify() {
    inotifywait -m -e create -e moved_to "$REPORTS_PENDING" --format '%f' 2>/dev/null | while read filename; do
        if [[ "$filename" == *.md ]]; then
            sleep 1  # Wait for file to be fully written
            process_report "$REPORTS_PENDING/$filename"
        fi
    done
}

# Watch using polling (fallback)
watch_with_polling() {
    while true; do
        for report_file in "$REPORTS_PENDING"/*.md; do
            if [ -f "$report_file" ]; then
                process_report "$report_file"
            fi
        done
        sleep "$POLL_INTERVAL"
    done
}

# Handle interrupt
cleanup() {
    log "INFO" "Host monitor stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Run main
main "$@"
