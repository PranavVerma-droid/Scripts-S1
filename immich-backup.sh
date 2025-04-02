#!/bin/bash

if [ -z "$TMUX" ] && [ "$1" != "--inside-tmux" ]; then
    echo "Starting backup script in a tmux session..."
    
    # Check if tmux is installed
    if ! command -v tmux &> /dev/null; then
        echo "tmux is not installed. Please install it with: apt-get install tmux"
        exit 1
    fi
    
    tmux new-session -d -s immich-backup "$0 --inside-tmux"
    echo "Backup process started in tmux session. To view progress, run:"
    echo "tmux attach -t immich-backup"
    exit 0
fi

# Variables
BACKUP_DIR="/backups/Immich Panel"
LOG_DIR="$BACKUP_DIR/logs"
DATE=$(date +"%m.%d.%Y-%H.%M")
BACKUP_FILE="dump-$DATE.sql.gz"
LOG_FILE="$LOG_DIR/log-$DATE.log"

# Ensure the log file is created before any output
touch "$LOG_FILE"

# Ensure the backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup directory does not exist, creating: $BACKUP_DIR" | tee -a "$LOG_FILE"
  mkdir -pv "$BACKUP_DIR" | tee -a "$LOG_FILE"
else
  echo "Backup directory exists: $BACKUP_DIR" | tee -a "$LOG_FILE"
fi

# Ensure the log directory exists
if [ ! -d "$LOG_DIR" ]; then
  echo "Log directory does not exist, creating: $LOG_DIR" | tee -a "$LOG_FILE"
  mkdir -pv "$LOG_DIR" | tee -a "$LOG_FILE"
else
  echo "Log directory exists: $LOG_DIR" | tee -a "$LOG_FILE"
fi

# Inform the start of the backup process
echo "Starting database backup at $(date +"%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"

# Run the Docker pg_dumpall command and gzip the output
echo "Running: docker exec -t immich_postgres pg_dumpall -c -U postgres | gzip > $BACKUP_DIR/$BACKUP_FILE" | tee -a "$LOG_FILE"
docker exec -t immich_postgres pg_dumpall -c -U postgres | gzip > "$BACKUP_DIR/$BACKUP_FILE" 2>>"$LOG_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to create database backup" | tee -a "$LOG_FILE"
  exit 1
else
  echo "Database backup created successfully: $BACKUP_DIR/$BACKUP_FILE" | tee -a "$LOG_FILE"
fi

# Inform the start of the cleanup process
echo "Checking if more than 5 backups exist..." | tee -a "$LOG_FILE"

# Find and delete oldest backups, keeping only the last 5
BACKUP_COUNT=$(ls -t "$BACKUP_DIR"/dump-*.sql.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt 5 ]; then
  echo "More than 5 backups found. Deleting oldest..." | tee -a "$LOG_FILE"
  ls -t "$BACKUP_DIR"/dump-*.sql.gz | tail -n +6 | xargs -d '\n' rm -v | tee -a "$LOG_FILE"
else
  echo "Only $BACKUP_COUNT backups found. No deletion needed." | tee -a "$LOG_FILE"
fi

echo "Backup and cleanup completed at $(date +"%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"

if [ -n "$TMUX" ] && [ "$1" == "--inside-tmux" ]; then
    echo "Backup complete. Automatically terminating tmux session in 3 seconds..."
    sleep 3
    tmux kill-session -t immich-backup
fi