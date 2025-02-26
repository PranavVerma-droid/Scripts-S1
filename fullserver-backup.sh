#!/bin/bash

# Full Server Backup Script w/ Encryption and Decryption.
# Usage: ./fullserver-backup.sh

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --backup              Start backup process"
    echo "  --decrypt <folder>    Decrypt backup folder"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --backup"
    echo "  $(basename "$0") --decrypt /path/to/backup/folder"
    echo ""
    exit 1
}

decrypt_backup() {
    local TARGET_DIR="$1"
    local TEMP_DIR="/tmp/decrypt_$$"

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Error: Directory '$TARGET_DIR' does not exist."
        exit 1
    fi

    if ! gpg --list-secret-keys | grep -q "$GPG_RECIPIENT"; then
        echo "Error: GPG decryption key is missing!"
        exit 1
    fi

    mkdir -p "$TEMP_DIR"
    trap 'rm -rf "$TEMP_DIR"' EXIT

    process_chunked_archive() {
    local base_path="$1"
    local base_name="$(basename "$base_path" .chunk.aa.gpg)"
    local target_path="$TEMP_DIR/$base_name"
    local extract_dir="$(dirname "$base_path")"
    local success=true

    echo "----------------------------------------"
    echo "PROCESSING CHUNKED ARCHIVE"
    echo "Base name: $base_name"
    echo "Extract directory: $extract_dir"
    echo "This archive was split into multiple chunks"
    echo "----------------------------------------"

    local chunk_dir="$TEMP_DIR/chunks_$$"
    mkdir -p "$chunk_dir"
    
    for chunk in "$TARGET_DIR/${base_name}.chunk."*".gpg"; do
        local decrypted_chunk="$chunk_dir/$(basename "$chunk" .gpg)"
        
        echo "Decrypting chunk: $chunk"
        if ! gpg --batch --yes --decrypt --output "$decrypted_chunk" "$chunk"; then
            echo "Failed to decrypt chunk: $chunk"
            rm -rf "$chunk_dir"
            return 1
        fi
    done

    echo "Reassembling chunks into complete archive..."
    cat "$chunk_dir"/* > "$target_path"
    rm -rf "$chunk_dir"
    
    echo "Extracting reassembled archive to: $extract_dir"
    if unzip -q "$target_path" -d "$extract_dir"; then
        echo "Successfully extracted: $base_name"
        rm -f "$target_path"
        rm -f "$TARGET_DIR/${base_name}.chunk."*".gpg"
        return 0
    else
        echo "Failed to extract: $target_path"
        rm -f "$target_path"
        return 1
    fi
}

    echo "Starting decryption in: $TARGET_DIR"

    find "$TARGET_DIR" -type f -name "*.gpg" | while read -r encrypted_file; do
    if [[ $encrypted_file =~ \.chunk\.[a-z]+\.gpg$ ]]; then
        if [[ $encrypted_file =~ \.chunk\.aa\.gpg$ ]]; then
            process_chunked_archive "$encrypted_file"
        fi
        continue
    fi

    decrypted_file="${encrypted_file%.gpg}"
    
    echo "----------------------------------------"
    echo "PROCESSING SINGLE ARCHIVE"
    echo "File: $(basename "$encrypted_file")"
    echo "This is a non-chunked archive"
    echo "----------------------------------------"
    
    echo "Decrypting: $encrypted_file"
    if gpg --batch --yes --decrypt --output "$decrypted_file" "$encrypted_file"; then
        echo "Decryption successful: $decrypted_file"
        
        if [[ $decrypted_file == *.zip ]]; then
            echo "Extracting: $decrypted_file"
            if unzip -q "$decrypted_file" -d "$(dirname "$decrypted_file")"; then
                echo "Extraction successful"
                rm -f "$decrypted_file"
            else
                echo "Extraction failed: $decrypted_file"
            fi
        fi
        
        rm -v "$encrypted_file"
        else
            echo "Failed to decrypt: $encrypted_file"
        fi
    done

    echo "Decryption process completed!"
}

case "$1" in
    --backup)
        if [ ! -f "$SCRIPT_DIR/.credentials" ]; then
            echo -e "\e[31mERROR: Credentials file not found at $SCRIPT_DIR/.credentials\e[0m"
            echo -e "\e[1mPlease Create one and add the following details:\e[0m"
            echo ""
            echo -e "\e[33mNAS_IP=\"\e[34mYOUR-NAS-IP\e[33m\""
            echo -e "NAS_USER=\"\e[34mYOUR-NAS-USER\e[33m\""
            echo -e "NAS_PASSWORD=\"\e[34mYOUR-NAS-USER-PASSWORD\e[33m\""
            echo ""
            echo "export CHUNK_SIZE=8589934592"
            echo "export BACKUP_TIMESTAMP=\"server_backup_\$(date +%Y-%m-%d_%H-%M-%S)\""
            echo $'export NAS_MOUNT_POINT="\e[34m/mnt/nas\e[33m"'
            echo "export NAS_REMOTE_PATH=\"//\${NAS_IP}/home/Server Backup (db1)\""
            echo "export BACKUP_FOLDER=\"\$NAS_MOUNT_POINT/\$BACKUP_TIMESTAMP\""
            echo -e "export GPG_RECIPIENT=\"\e[34mYOUR-GPG-KEY-EMAIL@gmail.com\e[33m\""
            echo "export MAX_PARALLEL_JOBS=4"
            echo "export TEMP_DIR=\"/tmp/\$BACKUP_TIMESTAMP\""
            echo "export MAIN_LOG=\"\$TEMP_DIR/logs/full-log.log\""
            echo "export MUTEX_FILE=\"/tmp/backup_mutex_$$\""
            echo ""
            echo "declare -a BACKUP_DIRS_WITHOUT_ARCHIVE=()"
            echo -e "declare -a BACKUP_DIRS=(\n    \"\e[34m/path/to/folder1\e[33m\"\n    \"\e[34m/path/to/folder2\e[33m\"\n)\e[0m"
            echo ""
            exit 1
        fi

        source "$SCRIPT_DIR/.credentials"

        if [ -f "$MUTEX_FILE" ]; then
            echo "ERROR: Another backup process appears to be running"
            exit 1
        fi

        if ! mkdir -p "$TEMP_DIR/archives" "$TEMP_DIR/logs" "$TEMP_DIR/status"; then
            echo "ERROR: Failed to create temporary directories"
            exit 1
        fi

        if ! touch "$MAIN_LOG" "$MUTEX_FILE"; then
            echo "ERROR: Failed to create log or mutex files"
            rm -rf "$TEMP_DIR"
            exit 1
        fi

        if ! gpg --list-keys "$GPG_RECIPIENT" >/dev/null 2>&1; then
            log "ERROR: GPG recipient key not found: $GPG_RECIPIENT"
            exit 1
        fi

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

        verify_nas_mount() {
            if ! mountpoint -q "$NAS_MOUNT_POINT"; then
                log "ERROR: NAS is not mounted at $NAS_MOUNT_POINT"
                return 1
            fi
            
            if ! test -w "$NAS_MOUNT_POINT"; then
                log "ERROR: Cannot write to NAS mount point $NAS_MOUNT_POINT"
                return 1
            fi
            
            local test_file="$NAS_MOUNT_POINT/.write_test_$$"
            if ! touch "$test_file" 2>/dev/null; then
                log "ERROR: Failed to create test file on NAS"
                return 1
            fi
            rm -f "$test_file"
            
            local available_space=$(df -P "$NAS_MOUNT_POINT" | awk 'NR==2 {print $4}')
            if [ "$available_space" -lt 5242880 ]; then  # 5GB minimum
                log "ERROR: Insufficient space on NAS (less than 5GB available)"
                return 1
            fi
            
            return 0
        }

        verify_backup_paths() {
            log "Verifying backup paths..."
            
            if [ ! -d "$NAS_MOUNT_POINT" ]; then
                if ! mkdir -p "$NAS_MOUNT_POINT"; then
                    log "ERROR: Cannot create NAS mount point: $NAS_MOUNT_POINT"
                    return 1
                fi
            fi
            
            log "Creating backup folder: $BACKUP_FOLDER"
            if ! mkdir -p "$BACKUP_FOLDER"; then
                log "ERROR: Cannot create backup folder: $BACKUP_FOLDER"
                return 1
            fi
            
            if [ ! -w "$BACKUP_FOLDER" ]; then
                log "ERROR: Backup folder is not writable: $BACKUP_FOLDER"
                return 1
            fi
            
            log "Backup paths verified successfully"
            return 0
        }

        mount_nas() {
            log "Checking if NAS is already mounted..."
            
            if verify_nas_mount; then
                log "NAS is already mounted and writable"
                return 0
            fi
            
            log "Mounting NAS at $NAS_MOUNT_POINT..."
            if ! sudo mount -t cifs "$NAS_REMOTE_PATH" "$NAS_MOUNT_POINT" -o "username=$NAS_USER,password=$NAS_PASSWORD,iocharset=utf8,file_mode=0777,dir_mode=0777"; then
                log "ERROR: Failed to mount NAS!"
                return 1
            fi
            
            if ! verify_nas_mount; then
                log "ERROR: NAS mount verification failed after mounting"
                return 1
            fi
            
            log "NAS mounted successfully"
            return 0
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
        if ! mount_nas; then
            log "ERROR: Failed to ensure NAS is mounted and writable"
            exit 1
        fi

        if ! verify_backup_paths; then
            log "ERROR: Failed to verify and create required paths"
            exit 1
        fi

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
        ;;

    --decrypt)
        if [ -z "$2" ]; then
            echo "Error: Decrypt option requires a folder path"
            show_help
        fi
        decrypt_backup "$2"
        ;;

    *)
        show_help
        ;;
esac
