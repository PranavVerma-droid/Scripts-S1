#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.backup-env"

# Load configuration
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: Configuration file $ENV_FILE not found!"
    exit 1
fi

source "$ENV_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "ERROR") 
            if [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]]; then
                echo -e "${RED}[$timestamp] ERROR: $message${NC}" | tee -a "$TEMP_DIR/backup.log"
            fi
            ;;
        "WARN")
            if [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARN)$ ]]; then
                echo -e "${YELLOW}[$timestamp] WARN: $message${NC}" | tee -a "$TEMP_DIR/backup.log"
            fi
            ;;
        "INFO")
            if [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO)$ ]]; then
                echo -e "${GREEN}[$timestamp] INFO: $message${NC}" | tee -a "$TEMP_DIR/backup.log"
            fi
            ;;
        "DEBUG")
            if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${BLUE}[$timestamp] DEBUG: $message${NC}" | tee -a "$TEMP_DIR/backup.log"
            fi
            ;;
    esac
}

# Check if running inside tmux
check_tmux() {
    if [[ -z "$TMUX" ]]; then
        log "INFO" "Starting backup in tmux session..."
        tmux new-session -d -s "fullserver-backup" "$0 --inside-tmux"
        tmux attach-session -t "fullserver-backup"
        exit 0
    fi
}

# Setup directories
setup_directories() {
    log "INFO" "Setting up backup directories..."
    
    mkdir -p "$BACKUP_DIR" "$BACKUP_SESSION_DIR" "$TEMP_DIR"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "ERROR" "Failed to create backup directory: $BACKUP_DIR"
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_SESSION_DIR" ]]; then
        log "ERROR" "Failed to create backup session directory: $BACKUP_SESSION_DIR"
        exit 1
    fi
    
    if [[ ! -d "$TEMP_DIR" ]]; then
        log "ERROR" "Failed to create temp directory: $TEMP_DIR"
        exit 1
    fi
    
    log "INFO" "Backup directory: $BACKUP_DIR"
    log "INFO" "Backup session directory: $BACKUP_SESSION_DIR"
    log "INFO" "Temp directory: $TEMP_DIR"
}

# Check GPG key
check_gpg_key() {
    if ! gpg --list-secret-keys | grep -q "$GPG_KEY_ID"; then
        log "WARN" "GPG key $GPG_KEY_ID not found in secret keyring. Encryption may fail."
    else
        log "INFO" "GPG key $GPG_KEY_ID found and ready for encryption."
    fi
}

# Encrypt file function
encrypt_file() {
    local file_path="$1"
    local output_path="$2"
    
    log "DEBUG" "Encrypting file: $file_path -> $output_path"
    
    if gpg --trust-model always --encrypt -r "$GPG_KEY_ID" --output "$output_path" "$file_path"; then
        log "DEBUG" "Successfully encrypted: $file_path"
        return 0
    else
        log "ERROR" "Failed to encrypt: $file_path"
        return 1
    fi
}

# Process individual folder
process_folder() {
    local folder_config="$1"
    local job_id="$2"
    
    IFS=':' read -r folder_path zip_flag encrypt_flag <<< "$folder_config"
    
    log "INFO" "Job $job_id: Processing folder $folder_path (zip:$zip_flag, encrypt:$encrypt_flag)"
    
    if [[ ! -d "$folder_path" ]]; then
        log "WARN" "Job $job_id: Folder $folder_path does not exist, skipping..."
        return 1
    fi
    
    local folder_name=$(basename "$folder_path")
    local backup_target="$BACKUP_SESSION_DIR/${folder_name}"
    
    if [[ "$zip_flag" == "true" ]]; then
        # Create zip file
        local zip_file="$TEMP_DIR/${folder_name}_$BACKUP_TIMESTAMP.zip"
        log "INFO" "Job $job_id: Creating zip file for $folder_path..."
        
        if cd "$(dirname "$folder_path")" && zip -r "$zip_file" "$(basename "$folder_path")" > "$TEMP_DIR/zip_${job_id}.log" 2>&1; then
            log "INFO" "Job $job_id: Successfully created zip: $zip_file"
            
            if [[ "$encrypt_flag" == "true" ]]; then
                # Encrypt the zip file
                local encrypted_zip="${backup_target}.zip.gpg"
                if encrypt_file "$zip_file" "$encrypted_zip"; then
                    log "INFO" "Job $job_id: Successfully encrypted zip to: $encrypted_zip"
                    rm -f "$zip_file"
                else
                    log "ERROR" "Job $job_id: Failed to encrypt zip file"
                    return 1
                fi
            else
                # Move unencrypted zip to backup directory
                mv "$zip_file" "${backup_target}.zip"
                log "INFO" "Job $job_id: Moved zip to: ${backup_target}.zip"
            fi
        else
            log "ERROR" "Job $job_id: Failed to create zip for $folder_path"
            return 1
        fi
    else
        # Copy folder without zipping
        mkdir -p "$backup_target"
        
        if [[ "$encrypt_flag" == "true" ]]; then
            # Copy and encrypt individual files
            log "INFO" "Job $job_id: Copying and encrypting files from $folder_path..."
            
            find "$folder_path" -type f | while read -r file; do
                local relative_path="${file#$folder_path/}"
                local target_dir="$backup_target/$(dirname "$relative_path")"
                local target_file="$backup_target/$relative_path.gpg"
                
                mkdir -p "$target_dir"
                
                if encrypt_file "$file" "$target_file"; then
                    log "DEBUG" "Job $job_id: Encrypted: $relative_path"
                else
                    log "ERROR" "Job $job_id: Failed to encrypt: $relative_path"
                fi
            done
        else
            # Simple copy without encryption
            log "INFO" "Job $job_id: Copying folder $folder_path to $backup_target..."
            if cp -r "$folder_path"/* "$backup_target/" 2> "$TEMP_DIR/copy_${job_id}.log"; then
                log "INFO" "Job $job_id: Successfully copied folder to: $backup_target"
            else
                log "ERROR" "Job $job_id: Failed to copy folder $folder_path"
                return 1
            fi
        fi
    fi
    
    log "INFO" "Job $job_id: Completed processing folder $folder_path"
}

# Process individual file
process_file() {
    local file_config="$1"
    local job_id="$2"
    
    IFS=':' read -r file_path encrypt_flag <<< "$file_config"
    
    log "INFO" "Job $job_id: Processing file $file_path (encrypt:$encrypt_flag)"
    
    if [[ ! -f "$file_path" ]]; then
        log "WARN" "Job $job_id: File $file_path does not exist, skipping..."
        return 1
    fi
    
    local file_name=$(basename "$file_path")
    local backup_target="$BACKUP_SESSION_DIR/${file_name}"
    
    if [[ "$encrypt_flag" == "true" ]]; then
        # Encrypt the file
        local encrypted_file="${backup_target}.gpg"
        if encrypt_file "$file_path" "$encrypted_file"; then
            log "INFO" "Job $job_id: Successfully encrypted file to: $encrypted_file"
        else
            log "ERROR" "Job $job_id: Failed to encrypt file $file_path"
            return 1
        fi
    else
        # Simple copy without encryption
        if cp "$file_path" "$backup_target"; then
            log "INFO" "Job $job_id: Successfully copied file to: $backup_target"
        else
            log "ERROR" "Job $job_id: Failed to copy file $file_path"
            return 1
        fi
    fi
    
    log "INFO" "Job $job_id: Completed processing file $file_path"
}

# Cleanup old backups
cleanup_old_backups() {
    log "INFO" "Checking for old backups to clean up (keeping $MAX_BACKUPS newest)..."
    
    # Get all backup files and directories with timestamps
    local backup_items=()
    
    # Find all items in backup directory that match our naming pattern
    while IFS= read -r -d '' item; do
        if [[ -f "$item" ]] || [[ -d "$item" ]]; then
            backup_items+=("$item")
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 \( -name "backup_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]*" \) -print0 2>/dev/null)
    
    local total_items=${#backup_items[@]}
    log "INFO" "Found $total_items backup items in directory"
    
    if [[ $total_items -le $MAX_BACKUPS ]]; then
        log "INFO" "No cleanup needed. Current backups ($total_items) within limit ($MAX_BACKUPS)"
        return 0
    fi
    
    # Sort by modification time (oldest first)
    IFS=$'\n' backup_items=($(printf "%s\n" "${backup_items[@]}" | xargs -I {} stat -c "%Y %n" {} | sort -n | cut -d' ' -f2-))
    
    local items_to_delete=$((total_items - MAX_BACKUPS))
    log "INFO" "Need to delete $items_to_delete old backup items"
    
    for ((i=0; i<items_to_delete; i++)); do
        local item_to_delete="${backup_items[i]}"
        log "INFO" "Deleting old backup: $(basename "$item_to_delete")"
        
        if [[ -d "$item_to_delete" ]]; then
            rm -rf "$item_to_delete"
        else
            rm -f "$item_to_delete"
        fi
        
        if [[ $? -eq 0 ]]; then
            log "INFO" "Successfully deleted: $(basename "$item_to_delete")"
        else
            log "ERROR" "Failed to delete: $(basename "$item_to_delete")"
        fi
    done
    
    log "INFO" "Backup cleanup completed"
}

# Parallel job manager
run_parallel_jobs() {
    local jobs=()
    local job_count=0
    local active_jobs=0
    
    # Add folder jobs
    for folder_config in "${BACKUP_FOLDERS[@]}"; do
        jobs+=("folder:$folder_config")
    done
    
    # Add file jobs
    for file_config in "${BACKUP_FILES[@]}"; do
        jobs+=("file:$file_config")
    done
    
    log "INFO" "Starting parallel processing with max $MAX_PARALLEL_JOBS jobs"
    log "INFO" "Total items to process: ${#jobs[@]}"
    
    for job in "${jobs[@]}"; do
        # Wait if we've reached max parallel jobs
        while [[ $active_jobs -ge $MAX_PARALLEL_JOBS ]]; do
            wait -n  # Wait for any job to complete
            active_jobs=$((active_jobs - 1))
        done
        
        job_count=$((job_count + 1))
        active_jobs=$((active_jobs + 1))
        
        IFS=':' read -r job_type job_config <<< "$job"
        
        if [[ "$job_type" == "folder" ]]; then
            process_folder "$job_config" "$job_count" &
        elif [[ "$job_type" == "file" ]]; then
            process_file "$job_config" "$job_count" &
        fi
        
        log "DEBUG" "Started job $job_count ($job_type): $job_config"
    done
    
    # Wait for all remaining jobs to complete
    wait
    log "INFO" "All backup jobs completed"
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "INFO" "Temporary directory removed: $TEMP_DIR"
    fi
}

# Main backup function
main_backup() {
    log "INFO" "Starting full server backup..."
    log "INFO" "Backup timestamp: $BACKUP_TIMESTAMP"
    
    setup_directories
    check_gpg_key
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    run_parallel_jobs
    cleanup_old_backups
    
    log "INFO" "Backup completed successfully!"
    log "INFO" "Backup location: $BACKUP_DIR"
    log "INFO" "Log file: $TEMP_DIR/backup.log"
    
    # Copy log to backup directory
    cp "$TEMP_DIR/backup.log" "$BACKUP_DIR/backup_$BACKUP_TIMESTAMP.log"
}

# Script entry point
case "${1:-}" in
    "--inside-tmux")
        log "INFO" "Running inside tmux session"
        main_backup
        ;;
    *)
        check_tmux
        ;;
esac