#!/bin/bash

################################################################################
# Torrent Transfer Script
#
# Purpose: Download torrents to local SSD, wait for Plex to be idle, then
#          transfer to NAS and update qBittorrent with new location
#
# Usage: ./torrent-transfer.sh <torrent-hash>
#        ./torrent-transfer.sh --check-all
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/torrent-transfer.conf"
LOG_FILE="${SCRIPT_DIR}/torrent-transfer.log"

# Default values (can be overridden in config file)
LOCAL_DOWNLOAD_DIR="/Volumes/WD_BLACK_SN770_1TB/torrents"
NAS_DESTINATION="/Volumes/media/torrents/complete"
QBITTORRENT_HOST="localhost"
QBITTORRENT_PORT="8080"
QBITTORRENT_USERNAME="admin"
QBITTORRENT_PASSWORD=""
TAUTULLI_HOST="localhost"
TAUTULLI_PORT="8181"
TAUTULLI_API_KEY=""
MAX_ACTIVE_STREAMS=0
CHECK_INTERVAL=300  # 5 minutes
VERIFY_AFTER_TRANSFER=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        log "INFO" "Configuration loaded from $CONFIG_FILE"
    else
        log "WARN" "Config file not found at $CONFIG_FILE"
        log "WARN" "Creating example config file..."
        create_example_config
        log "ERROR" "Please edit $CONFIG_FILE and run again"
        exit 1
    fi
}

# Create example configuration file
create_example_config() {
    cat > "$CONFIG_FILE" <<'EOF'
# Torrent Transfer Configuration

# Local download directory (on fast SSD)
LOCAL_DOWNLOAD_DIR="/Volumes/WD_BLACK_SN770_1TB/torrents"

# NAS destination directory
NAS_DESTINATION="/Volumes/media/torrents/complete"

# qBittorrent Web UI settings
QBITTORRENT_HOST="localhost"
QBITTORRENT_PORT="8080"
QBITTORRENT_USERNAME="admin"
QBITTORRENT_PASSWORD="your-password-here"

# Tautulli settings
TAUTULLI_HOST="localhost"
TAUTULLI_PORT="8181"
TAUTULLI_API_KEY="your-api-key-here"

# Maximum number of active Plex streams allowed before transfer (0 = wait for no streams)
MAX_ACTIVE_STREAMS=0

# How often to check Plex activity (in seconds) when waiting
CHECK_INTERVAL=300

# Verify torrent after transfer (recommended)
VERIFY_AFTER_TRANSFER=true
EOF
    chmod 600 "$CONFIG_FILE"
}

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
        *)       echo -e "[${level}] $message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Check if required directories exist
check_directories() {
    if [[ ! -d "$LOCAL_DOWNLOAD_DIR" ]]; then
        log "ERROR" "Local download directory does not exist: $LOCAL_DOWNLOAD_DIR"
        return 1
    fi

    if [[ ! -d "$NAS_DESTINATION" ]]; then
        log "ERROR" "NAS destination does not exist: $NAS_DESTINATION"
        log "ERROR" "Is the NFS mount active? Check: mount | grep tower.local"
        return 1
    fi

    return 0
}

# Check Tautulli for active Plex streams
check_plex_activity() {
    local api_url="http://${TAUTULLI_HOST}:${TAUTULLI_PORT}/api/v2"
    local activity

    activity=$(curl -s "${api_url}?apikey=${TAUTULLI_API_KEY}&cmd=get_activity" || echo "")

    if [[ -z "$activity" ]]; then
        log "ERROR" "Failed to get Plex activity from Tautulli"
        return 1
    fi

    local stream_count
    stream_count=$(echo "$activity" | grep -o '"stream_count":[0-9]*' | cut -d: -f2 || echo "0")

    log "INFO" "Current Plex streams: $stream_count"

    if [[ $stream_count -le $MAX_ACTIVE_STREAMS ]]; then
        return 0
    else
        return 1
    fi
}

# Wait for Plex to be idle
wait_for_plex_idle() {
    log "INFO" "Waiting for Plex activity to decrease to $MAX_ACTIVE_STREAMS or fewer streams..."

    while true; do
        if check_plex_activity; then
            log "SUCCESS" "Plex is idle (streams <= $MAX_ACTIVE_STREAMS)"
            return 0
        else
            log "INFO" "Plex is busy, checking again in $CHECK_INTERVAL seconds..."
            sleep "$CHECK_INTERVAL"
        fi
    done
}

# Get qBittorrent cookie (login)
qbt_login() {
    local cookie_file="/tmp/qbt_cookie_$$"

    curl -s -i \
        --header "Referer: http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}" \
        --data "username=${QBITTORRENT_USERNAME}&password=${QBITTORRENT_PASSWORD}" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/auth/login" \
        -c "$cookie_file" > /dev/null

    if [[ -f "$cookie_file" ]]; then
        echo "$cookie_file"
        return 0
    else
        log "ERROR" "Failed to login to qBittorrent"
        return 1
    fi
}

# Get torrent info from qBittorrent
qbt_get_torrent_info() {
    local hash=$1
    local cookie_file=$2

    curl -s -b "$cookie_file" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/torrents/info?hashes=${hash}"
}

# Set torrent location in qBittorrent
qbt_set_location() {
    local hash=$1
    local new_location=$2
    local cookie_file=$3

    curl -s -b "$cookie_file" \
        --data "hashes=${hash}&location=${new_location}" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/torrents/setLocation"

    log "SUCCESS" "Updated qBittorrent location for ${hash} to ${new_location}"
}

# Recheck torrent in qBittorrent
qbt_recheck() {
    local hash=$1
    local cookie_file=$2

    curl -s -b "$cookie_file" \
        --data "hashes=${hash}" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/torrents/recheck"

    log "INFO" "Initiated recheck for torrent ${hash}"
}

# Transfer a single torrent
transfer_torrent() {
    local hash=$1

    log "INFO" "Starting transfer process for torrent: $hash"

    # Login to qBittorrent
    local cookie_file
    cookie_file=$(qbt_login) || return 1

    # Get torrent info
    local torrent_info
    torrent_info=$(qbt_get_torrent_info "$hash" "$cookie_file")

    if [[ -z "$torrent_info" || "$torrent_info" == "[]" ]]; then
        log "ERROR" "Torrent not found: $hash"
        rm -f "$cookie_file"
        return 1
    fi

    local torrent_name
    local save_path
    local state

    torrent_name=$(echo "$torrent_info" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\//g')
    save_path=$(echo "$torrent_info" | grep -o '"save_path":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\//g')
    state=$(echo "$torrent_info" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

    log "INFO" "Torrent name: $torrent_name"
    log "INFO" "Current location: $save_path"
    log "INFO" "Current state: $state"

    # Check if torrent is in local download directory
    if [[ ! "$save_path" =~ $LOCAL_DOWNLOAD_DIR ]]; then
        log "WARN" "Torrent is not in local download directory, skipping"
        rm -f "$cookie_file"
        return 0
    fi

    # Check if download is complete
    if [[ "$state" != "uploading" && "$state" != "stalledUP" && "$state" != "pausedUP" && "$state" != "queuedUP" ]]; then
        log "WARN" "Torrent is not finished downloading (state: $state), skipping"
        rm -f "$cookie_file"
        return 0
    fi

    local source_path="${save_path}/${torrent_name}"
    local dest_path="${NAS_DESTINATION}/${torrent_name}"

    # Check if source exists
    if [[ ! -e "$source_path" ]]; then
        log "ERROR" "Source path does not exist: $source_path"
        rm -f "$cookie_file"
        return 1
    fi

    # Check if destination already exists
    if [[ -e "$dest_path" ]]; then
        log "ERROR" "Destination already exists: $dest_path"
        log "ERROR" "Please resolve manually"
        rm -f "$cookie_file"
        return 1
    fi

    # Wait for Plex to be idle
    wait_for_plex_idle || {
        log "ERROR" "Failed to check Plex activity"
        rm -f "$cookie_file"
        return 1
    }

    # Transfer the files
    log "INFO" "Transferring files from SSD to NAS..."
    log "INFO" "Source: $source_path"
    log "INFO" "Destination: $dest_path"

    if [[ -d "$source_path" ]]; then
        # Directory transfer
        rsync -ah --progress --info=progress2 "$source_path" "$NAS_DESTINATION/" || {
            log "ERROR" "Failed to transfer directory"
            rm -f "$cookie_file"
            return 1
        }
    else
        # Single file transfer
        rsync -ah --progress --info=progress2 "$source_path" "$dest_path" || {
            log "ERROR" "Failed to transfer file"
            rm -f "$cookie_file"
            return 1
        }
    fi

    log "SUCCESS" "Transfer complete"

    # Update qBittorrent location
    qbt_set_location "$hash" "$NAS_DESTINATION" "$cookie_file"

    # Verify if requested
    if [[ "$VERIFY_AFTER_TRANSFER" == "true" ]]; then
        log "INFO" "Initiating verification..."
        qbt_recheck "$hash" "$cookie_file"

        log "INFO" "Waiting 5 seconds for recheck to start..."
        sleep 5

        log "INFO" "Please monitor qBittorrent to ensure verification completes successfully"
        log "INFO" "Once verified, the local files will be deleted"
    fi

    # Wait for verification to complete if enabled
    if [[ "$VERIFY_AFTER_TRANSFER" == "true" ]]; then
        log "INFO" "Waiting for verification to complete..."
        local retries=0
        local max_retries=60  # 5 minutes max

        while [[ $retries -lt $max_retries ]]; do
            local current_state
            current_state=$(qbt_get_torrent_info "$hash" "$cookie_file" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

            if [[ "$current_state" == "uploading" || "$current_state" == "stalledUP" || "$current_state" == "pausedUP" || "$current_state" == "queuedUP" ]]; then
                log "SUCCESS" "Verification complete! State: $current_state"
                break
            elif [[ "$current_state" == "checkingUP" || "$current_state" == "checkingResumeData" ]]; then
                log "INFO" "Still verifying... (state: $current_state)"
                sleep 5
                ((retries++))
            else
                log "WARN" "Unexpected state during verification: $current_state"
                sleep 5
                ((retries++))
            fi
        done

        if [[ $retries -ge $max_retries ]]; then
            log "WARN" "Verification timeout - please check qBittorrent manually"
            log "WARN" "Local files will NOT be deleted automatically"
            rm -f "$cookie_file"
            return 1
        fi
    fi

    # Delete local copy
    log "INFO" "Deleting local copy from SSD..."
    rm -rf "$source_path"
    log "SUCCESS" "Local copy deleted: $source_path"

    # Cleanup
    rm -f "$cookie_file"

    log "SUCCESS" "Transfer process completed successfully for: $torrent_name"
    return 0
}

# Check all torrents in local directory
check_all_torrents() {
    log "INFO" "Checking all torrents in local download directory..."

    local cookie_file
    cookie_file=$(qbt_login) || return 1

    local all_torrents
    all_torrents=$(curl -s -b "$cookie_file" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/torrents/info")

    # Extract hashes of torrents in local directory
    local hash
    while IFS= read -r line; do
        local save_path
        save_path=$(echo "$line" | grep -o '"save_path":"[^"]*"' | cut -d'"' -f4 | sed 's/\\//g')

        if [[ "$save_path" =~ $LOCAL_DOWNLOAD_DIR ]]; then
            hash=$(echo "$line" | grep -o '"hash":"[^"]*"' | cut -d'"' -f4)
            local name
            name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/\\//g')
            local state
            state=$(echo "$line" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)

            log "INFO" "Found torrent in local directory: $name (state: $state, hash: $hash)"

            if [[ "$state" == "uploading" || "$state" == "stalledUP" || "$state" == "pausedUP" || "$state" == "queuedUP" ]]; then
                log "INFO" "This torrent is ready for transfer"
            fi
        fi
    done < <(echo "$all_torrents" | grep -o '{[^}]*}')

    rm -f "$cookie_file"
}

# Main function
main() {
    log "INFO" "=== Torrent Transfer Script Started ==="

    # Load configuration
    load_config

    # Check directories
    check_directories || exit 1

    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 <torrent-hash> | --check-all"
        exit 1
    fi

    if [[ "$1" == "--check-all" ]]; then
        check_all_torrents
    else
        local torrent_hash=$1
        transfer_torrent "$torrent_hash"
    fi

    log "INFO" "=== Script Completed ==="
}

# Run main function
main "$@"
