#!/bin/bash

# Define the base folder to save downloads
BASE_FOLDER="/songs/All Songs"

# Predefined list of playlist URLs
PLAYLISTS=(
    "Your Youtube Playlist URL's Go Here."
)

# Specify the path to the downloader binary (update with your binary location)
DOWNLOADER_PATH="/songs/Binary/downloader"

# Check if downloader is installed
if ! command -v "$DOWNLOADER_PATH" &> /dev/null; then
    echo "downloader is not installed or not in the specified location. Please verify the binary location."
    exit 1
fi

echo "Updating the downloader..."
"$DOWNLOADER_PATH" -U
if [ $? -ne 0 ]; then
    echo "Failed to update the downloader. Please check for errors."
    exit 1
fi

# Loop through each playlist URL
for URL in "${PLAYLISTS[@]}"; do
    echo "Processing $URL..."

    # Fetch the playlist name, ensuring spaces are preserved
    PLAYLIST_NAME=$(timeout 20s "$DOWNLOADER_PATH" --print "%(playlist_title)s" "$URL" 2>/dev/null | head -n 1)

    # Check if playlist name was fetched
    if [[ -z "$PLAYLIST_NAME" ]]; then
        echo "Failed to fetch playlist title for $URL. Skipping..."
        continue
    fi

    # Define the folder for this playlist
    PLAYLIST_FOLDER="$BASE_FOLDER/$PLAYLIST_NAME"

    # Create the folder if it doesn't exist
    mkdir -p "$PLAYLIST_FOLDER"

    # Download the playlist into the designated folder
    echo "Downloading playlist '$PLAYLIST_NAME' to $PLAYLIST_FOLDER..."

    "$DOWNLOADER_PATH" -o "$PLAYLIST_FOLDER/%(playlist_index)s-%(title)s.%(ext)s" \
        --format "bestaudio[ext=m4a]/best" \
        --extract-audio \
        --audio-format mp3 \
        --audio-quality 0 \
        --embed-thumbnail \
        --add-metadata \
        --postprocessor-args "-metadata author='%(artist)s'" \
        "$URL"
done

echo "All downloads completed. Playlists saved to $BASE_FOLDER."
