#!/bin/bash

# Define the base folder to save downloads
BASE_FOLDER="/songs/All Songs"

# Predefined list of playlist URLs
PLAYLISTS=(
    "https://music.youtube.com/browse/VLPLByuInhy-5qFhoPhBi9KFAXrANjd7U7Fa"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qHgB9mLwW91Hikuh3-8XWBz"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qEF-HF4vcn8jBD0egXH7aOT"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qH-HSpaU6qzypbXSVevFyXc"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qFelgfXF-pVt7fR-vFhv25e"
    "https://music.youtube.com/playlist?list=RDCLAK5uy_k2QP2SyBfHTEXknOLST7P1v1v4JzGWcxM1"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qESS62PXgUJDMTycK7AIvYw"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qGDUFiB0b8ONKHtKGJFIoMz"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qGz0f9vNoIJejnIbIrWC9gQ"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qETxmgDfQEKIeeOhyHoTIG1"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qHAWBqCehP4mUB9tiCryIAH"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qHp5kc1f8nOmWwBa693Qazv"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qEoTEPejnEQcy9cXIXPD3iT"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qGc7Su12fWk52GURGjMBfTf"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qGBLThASYDEJ5zeXyA9bj0m"
    "https://music.youtube.com/playlist?list=RDCLAK5uy_kCO40RkB9MzrBJF8p6uDcMP7tq2SUmrOE"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qEOxIBqJCZS7I0Ki9_-TG-p"
    "https://music.youtube.com/playlist?list=OLAK5uy_kxuB2pIzWZWC3TT04MDq_HC-t5EIp4Rn8"
    "https://music.youtube.com/playlist?list=OLAK5uy_ksMcoC36wmr-fyFQfcpM_TjVqo3pBA1H4"
    "https://music.youtube.com/playlist?list=OLAK5uy_kmOkMBRTqsEVhlWDGC27PjX8fMpt5BO18"
    "https://music.youtube.com/playlist?list=OLAK5uy_n2YwQKcKTO6otw0P58WN5s9boW87J_avE"
    "https://music.youtube.com/playlist?list=PLByuInhy-5qHvtnAXU23MJGkK1O4-fQXv"
    "https://music.youtube.com/playlist?list=RDTMAK5uy_nzfwl2UYv7htL7wDoxbX8Pp6UAFBd92cQ"
    "https://music.youtube.com/playlist?list=PLmOldskd2VbL7_t-NE9p6rEboq_v0AHko"
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

# Function to clean title for file searching
clean_title() {
    # Remove special characters that might interfere with file matching
    echo "$1" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]' | tr -s ' '
}

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
    
    # Get the list of songs in the playlist with their video IDs
    echo "Retrieving song list for '$PLAYLIST_NAME'..."
    SONG_LIST=$(timeout 60s "$DOWNLOADER_PATH" --flat-playlist --print "%(playlist_index)s:%(title)s:%(id)s" "$URL" 2>/dev/null)
    
    # Process each song in the playlist
    echo "$SONG_LIST" | while IFS=: read -r INDEX TITLE VIDEO_ID; do
        if [[ -z "$INDEX" || -z "$TITLE" || -z "$VIDEO_ID" ]]; then
            continue
        fi
        
        # Format the index to have leading zeros (001, 002, etc.)
        # Force decimal interpretation with 10# to prevent octal issues with 08, 09
        FORMATTED_INDEX=$(printf "%03d" "$((10#$INDEX))")
        
        # Clean the title for matching
        CLEAN_TITLE=$(clean_title "$TITLE")
        
        # Check if a file with this title (ignoring index) already exists
        FOUND=0
        for EXISTING_FILE in "$PLAYLIST_FOLDER"/*; do
            if [[ -f "$EXISTING_FILE" && "$EXISTING_FILE" == *.mp3 ]]; then
                # Extract the title part (remove index prefix and extension)
                EXISTING_BASENAME=$(basename "$EXISTING_FILE")
                EXISTING_TITLE=${EXISTING_BASENAME#[0-9]*-}
                EXISTING_TITLE=${EXISTING_TITLE%.mp3}
                
                # Compare cleaned titles
                if [[ "$(clean_title "$EXISTING_TITLE")" == "$CLEAN_TITLE" ]]; then
                    # Found matching song, rename it
                    NEW_NAME="$PLAYLIST_FOLDER/${FORMATTED_INDEX}-${TITLE}.mp3"
                    echo "Song '$TITLE' already exists. Renaming to match new index."
                    mv "$EXISTING_FILE" "$NEW_NAME"
                    FOUND=1
                    break
                fi
            fi
        done
        
        # If song wasn't found, download it
        if [[ $FOUND -eq 0 ]]; then
            echo "Downloading song: $TITLE"
            # Create a video URL from the ID and download directly
            VIDEO_URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
            "$DOWNLOADER_PATH" -o "$PLAYLIST_FOLDER/${FORMATTED_INDEX}-%(title)s.%(ext)s" \
                --format "bestaudio[ext=m4a]/best" \
                --extract-audio \
                --audio-format mp3 \
                --audio-quality 0 \
                --embed-thumbnail \
                --add-metadata \
                --postprocessor-args "-metadata author='%(artist)s'" \
                "$VIDEO_URL"
        fi
    done
done

echo "All downloads completed. Playlists saved to $BASE_FOLDER."
