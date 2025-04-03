#!/bin/bash

# Variables
SOURCE_DIR="/var/lib/pufferpanel/servers/fa651d01"
BACKUP_DIR="/backups/CraftingRealm Server"
LOG_DIR="$BACKUP_DIR/logs"
DATE=$(date +"%d.%m.%Y-%H.%M")
ZIP_NAME="craftingrealm-backup-$DATE.zip"
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

# Create a zip archive of the source directory and log all files being zipped
echo "Running: zip -r \"$BACKUP_DIR/$ZIP_NAME\" \"$SOURCE_DIR\"" | tee -a "$LOG_FILE"
zip -r "$BACKUP_DIR/$ZIP_NAME" "$SOURCE_DIR" | tee -a "$LOG_FILE" 2>>"$LOG_FILE"
if [ $? -ne 0 ]; then
  echo "Failed to create zip archive" | tee -a "$LOG_FILE"
  exit 1
else
  echo "Zip archive created successfully: $BACKUP_DIR/$ZIP_NAME" | tee -a "$LOG_FILE"
fi

# Inform the start of the cleanup process
echo "Checking if more than 5 backups exist..." | tee -a "$LOG_FILE"

# Find and delete oldest backups, keeping only the last 5
BACKUP_COUNT=$(ls -t "$BACKUP_DIR"/craftingrealm-backup-*.zip 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt 5 ]; then
  echo "More than 5 backups found. Deleting oldest..." | tee -a "$LOG_FILE"
  ls -t "$BACKUP_DIR"/craftingrealm-backup-*.zip | tail -n +6 | xargs rm -v | tee -a "$LOG_FILE"
else
  echo "Only $BACKUP_COUNT backups found. No deletion needed." | tee -a "$LOG_FILE"
fi

echo "Backup and cleanup completed at $(date +"%Y-%m-%d %H:%M:%S")" | tee -a "$LOG_FILE"
