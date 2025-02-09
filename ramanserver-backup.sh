#!/bin/bash

# Variables
SOURCE_DIR="/var/lib/pufferpanel/servers/92dcd23a"
BACKUP_DIR="/backups/Raman Server"
LOG_DIR="$BACKUP_DIR/logs"
DATE=$(date +"%d.%m.%Y-%H.%M")
ZIP_NAME="ramanserver-backup-$DATE.zip"
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
echo "Starting server backup at $(date +"%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"

# Log the contents of the source directory
echo "Contents of the source directory ($SOURCE_DIR):" | tee -a "$LOG_FILE"
ls -lR "$SOURCE_DIR" | tee -a "$LOG_FILE"

# Create a zip archive of the source directory
echo "Running: zip -r \"$BACKUP_DIR/$ZIP_NAME\" \"$SOURCE_DIR\"" | tee -a "$LOG_FILE"
zip -r "$BACKUP_DIR/$ZIP_NAME" "$SOURCE_DIR" 2>>"$LOG_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to create zip archive" | tee -a "$LOG_FILE"
  exit 1
else
  echo "Zip archive created successfully: $BACKUP_DIR/$ZIP_NAME" | tee -a "$LOG_FILE"
fi

# Inform the start of the cleanup process
echo "Cleaning up old backup files older than 20 days at $(date +"%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"

# Find and delete zip files older than 20 days in the backup directory
find "$BACKUP_DIR" -type f -name "ramanserver-backup-*.zip" -mtime +20 -exec rm -v {} \; | tee -a "$LOG_FILE"

echo "Backup and cleanup completed at $(date +"%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"
