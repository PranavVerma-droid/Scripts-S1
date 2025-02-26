#!/bin/bash

# 1GB: CHUNK_SIZE=1073741824
# 2GB: CHUNK_SIZE=2147483648
# 4GB: CHUNK_SIZE=4294967296
# 8GB: CHUNK_SIZE=8589934592
# 5MB: CHUNK_SIZE=5242880
CHUNK_SIZE=8589934592
BACKUP_TIMESTAMP="server_backup_$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_FOLDER="$NAS_MOUNT_POINT/$BACKUP_TIMESTAMP"
GPG_RECIPIENT="pranav@verma.net.in"
MAX_PARALLEL_JOBS=4
NAS_MOUNT_POINT="/mnt/nas"
NAS_REMOTE_PATH="//${NAS_IP}/home/Server Backup (db1)"
TEMP_DIR="/tmp/$BACKUP_TIMESTAMP"
MAIN_LOG="$TEMP_DIR/logs/full-log.log"
MUTEX_FILE="/tmp/backup_mutex_$$"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BACKUP_DIRS_WITHOUT_ARCHIVE=()
BACKUP_DIRS=(
    "/books"
    "/backups"
    "/scripts"
    "/songs"
    "/servers"
    "/github"
    "/var/www"
    "/photos"
)



if [ ! -f "$SCRIPT_DIR/.credentials" ]; then
    echo "ERROR: Credentials file not found at $SCRIPT_DIR/.credentials"
    echo "Please Create one and add the following details:"
    echo ""
    echo "NAS_IP=\"YOUR-NAS-IP\""
    echo "NAS_USER=\"YOUR-NAS-USER\""
    echo "NAS_PASSWORD=\"YOUR-NAS-USER-PASSWORD\""
    echo ""
    exit 1
fi

source "$SCRIPT_DIR/.credentials"
mkdir -p "$TEMP_DIR/archives" "$TEMP_DIR/logs" "$TEMP_DIR/status"
touch "$MAIN_LOG"
touch "$MUTEX_FILE"

log() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    flock "$MUTEX_FILE" echo "[$timestamp] $1" | tee -a "$MAIN_LOG"
}

log_to_file() {
    local file="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    flock "$MUTEX_FILE" echo "[$timestamp] $message" >> "$file"
}

cleanup() {
    local exit_code=$?
    log "Cleaning up..."
    
    jobs -p | xargs -r kill -SIGTERM 2>/dev/null
    
    wait 2>/dev/null
    
    if [ $exit_code -ne 0 ]; then
        if [ -d "$BACKUP_FOLDER" ]; then
            log "Backup was interrupted or failed. Removing incomplete backup folder: $BACKUP_FOLDER"
            rm -rf "$BACKUP_FOLDER"
        fi
    fi
    
    if [ $exit_code -eq 0 ]; then
        rm -rf "$TEMP_DIR"
    else
        log "Backup failed. Logs are preserved at: $TEMP_DIR/logs/"
    fi
    
    rm -f "$MUTEX_FILE"
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

mount_nas() {
    log "Checking if NAS is already mounted..."
    if mountpoint -q "$NAS_MOUNT_POINT"; then
        log "NAS is already mounted. Skipping mount."
        return
    fi
    
    log "Mounting NAS at $NAS_MOUNT_POINT..."
    sudo mount -t cifs "$NAS_REMOTE_PATH" "$NAS_MOUNT_POINT" -o username="$NAS_USER",password="$NAS_PASSWORD",iocharset=utf8,file_mode=0777,dir_mode=0777
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to mount NAS! Exiting..."
        exit 1
    fi
    log "NAS mounted successfully."
}

encrypt_file() {
    local src="$1"
    local dest="$2"
    local log_file="$3"
    
    mkdir -p "$(dirname "$dest")"
    
    if gpg --batch --yes --encrypt --sign --recipient "$GPG_RECIPIENT" --output "$dest" "$src" 2>> "$log_file"; then
        log_to_file "$log_file" "Successfully encrypted: $src -> $dest"
        return 0
    else
        log_to_file "$log_file" "ERROR: Failed to encrypt: $src"
        return 1
    fi
}

process_directory_without_archive() {
    local dir="$1"
    local status_file="$TEMP_DIR/status/$(basename "$dir")"
    local log_file="$TEMP_DIR/logs/$(basename "$dir")_backup.log"
    local failed=0
    
    if [ ! -d "$dir" ]; then
        log "WARNING: Directory $dir does not exist, skipping..."
        echo "1" > "$status_file"
        return
    fi
    
    local base_name=$(basename "$dir")
    log "Processing directory: $dir (Log: $log_file)"
    
    find "$dir" -type f | while read -r file; do
        local rel_path="${file#$dir/}"
        local dest_file="$BACKUP_FOLDER/$base_name/${rel_path}.gpg"
        
        log_to_file "$log_file" "Processing: $file"
        encrypt_file "$file" "$dest_file" "$log_file"
        
        if [ $? -ne 0 ]; then
            log "ERROR: Failed to encrypt $file"
            log_to_file "$log_file" "ERROR: Failed to encrypt $file"
            failed=1
        fi
    done
    
    if [ $failed -eq 0 ]; then
        log_to_file "$log_file" "Backup Done for Folder: $dir"
    fi
    
    echo "$failed" > "$status_file"
}

process_directory_with_archive() {
    local dir="$1"
    local status_file="$TEMP_DIR/status/$(basename "$dir")"
    local log_file="$TEMP_DIR/logs/$(basename "$dir")_archive.log"
    local failed=0
    
    if [ ! -d "$dir" ]; then
        log "WARNING: Directory $dir does not exist, skipping..."
        echo "1" > "$status_file"
        return
    fi
    
    local base_name=$(basename "$dir")
    local archive_path="$TEMP_DIR/archives/${base_name}.zip"
    
    log "Creating archive for $dir..."
    log_to_file "$log_file" "Starting archive creation for: $dir"
    
    if zip -r -MM "$archive_path" "$dir" > >(tee -a "$log_file") 2>&1; then
        log_to_file "$log_file" "Archive created successfully: $archive_path"
    else
        if [ ! -f "$archive_path" ] || [ ! -s "$archive_path" ]; then
            log "ERROR: Failed to create archive for $dir"
            log_to_file "$log_file" "ERROR: Failed to create archive for $dir"
            echo "1" > "$status_file"
            return
        fi
    fi

    local archive_size=$(stat -c%s "$archive_path")
    log "Archive size is: $archive_size bytes (Chunk size is: $CHUNK_SIZE bytes)"
    
    if [ $archive_size -gt $CHUNK_SIZE ]; then
        log "Archive size ($archive_size bytes) exceeds chunk size ($CHUNK_SIZE bytes). Splitting into chunks..."

        split -b $CHUNK_SIZE "$archive_path" "${archive_path}.chunk."
        
        local chunk_failed=0
        for chunk in "${archive_path}.chunk."*; do
            local chunk_name=$(basename "$chunk")
            local encrypted_path="$BACKUP_FOLDER/${base_name}.zip.${chunk_name}.gpg"
            
            log "Encrypting chunk: $chunk_name ($(stat -c%s "$chunk") bytes)"
            encrypt_file "$chunk" "$encrypted_path" "$log_file"
            if [ $? -ne 0 ]; then
                log "ERROR: Failed to encrypt chunk: $chunk"
                chunk_failed=1
            fi
            rm -f "$chunk"
        done
        
        if [ $chunk_failed -eq 1 ]; then
            failed=1
        fi
    else
        local encrypted_path="$BACKUP_FOLDER/${base_name}.zip.gpg"
        encrypt_file "$archive_path" "$encrypted_path" "$log_file"
        if [ $? -ne 0 ]; then
            log "ERROR: Failed to encrypt archive for $dir"
            failed=1
        fi
    fi
    
    rm -f "$archive_path"
    echo "$failed" > "$status_file"
}

backup_without_archiving() {
    log "Starting backup of directories without archiving..."
    local running_jobs=0
    
    for dir in "${BACKUP_DIRS_WITHOUT_ARCHIVE[@]}"; do
        process_directory_without_archive "$dir" &
        ((running_jobs++))
        if [ $running_jobs -ge $MAX_PARALLEL_JOBS ]; then
            wait -n
            ((running_jobs--))
        fi
    done

    wait
    
    local failed=0
    for dir in "${BACKUP_DIRS_WITHOUT_ARCHIVE[@]}"; do
        local status_file="$TEMP_DIR/status/$(basename "$dir")"
        if [ -f "$status_file" ] && [ "$(cat "$status_file")" != "0" ]; then
            failed=1
        fi
    done
    
    return $failed
}

create_archive_backup() {
    log "Starting backup of directories with archiving..."
    local running_jobs=0
    
    for dir in "${BACKUP_DIRS[@]}"; do
        process_directory_with_archive "$dir" &

        ((running_jobs++))

        if [ $running_jobs -ge $MAX_PARALLEL_JOBS ]; then
            wait -n
            ((running_jobs--))
        fi
    done
    
    wait
    
    local failed=0
    for dir in "${BACKUP_DIRS[@]}"; do
        local status_file="$TEMP_DIR/status/$(basename "$dir")"
        if [ -f "$status_file" ] && [ "$(cat "$status_file")" != "0" ]; then
            failed=1
        fi
    done
    
    return $failed
}

rotate_backups() {
    local max_backups=3
    log "Checking for old backups to rotate (keeping $max_backups most recent)..."
    
    local backup_dirs=($(find "$NAS_MOUNT_POINT" -maxdepth 1 -type d -name "server_backup_*" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-))
    
    local count=${#backup_dirs[@]}
    local to_delete=$((count - max_backups))
    
    if [ $to_delete -le 0 ]; then
        log "No backup rotation needed (found $count backup(s))"
        return 0
    fi
    
    log "Found $count backups, removing $to_delete old backup(s)..."
    
    for ((i=0; i<to_delete; i++)); do
        log "Removing old backup: ${backup_dirs[i]}"
        rm -rf "${backup_dirs[i]}"
        if [ $? -ne 0 ]; then
            log "WARNING: Failed to remove old backup: ${backup_dirs[i]}"
        fi
    done
    
    log "Backup rotation completed"
}


log "Starting backup process..."
mount_nas
mkdir -p "$BACKUP_FOLDER"


log "Step 1: Processing directories without archiving..."
backup_without_archiving
direct_backup_status=$?

if [ $direct_backup_status -eq 0 ]; then
    log "Direct file encryption completed successfully."
    
    log "Step 2: Processing directories that need archiving..."
    create_archive_backup
    archive_status=$?
    
    if [ $archive_status -eq 0 ]; then
        log "Complete backup process finished successfully!"
        cp "$MAIN_LOG" "$BACKUP_FOLDER/backup_log.txt"
        rotate_backups
        
        exit 0
    else
        log "ERROR: Archive backup process failed!"
        exit 2
    fi
else
    log "ERROR: Direct file encryption process failed!"
    exit 1
fi
