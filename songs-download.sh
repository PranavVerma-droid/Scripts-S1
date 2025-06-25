#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Environment Checking
if [ ! -f "$SCRIPT_DIR/.songs-env" ]; then
    echo -e "\e[31mERROR: File Not Found at $SCRIPT_DIR/.songs-env\e[0m"
    echo -e "Please Create one and Add This Content:"
    echo -e ""
    echo -e "\e[33mexport BASE_FOLDER=\"/songs/All Songs\""
    echo -e "export DOWNLOADER_PATH=\"/songs/Binary/downloader\""
    echo -e "export RECORD_FILE_NAME=\".downloaded_videos.txt\""
    echo -e "declare -a PLAYLISTS=(\nPLAYLIST-1-URL\nPLAYLIST-2-URL\nPLAYLIST-3-URL\n)\e[0m"
    exit 1
fi

source "$SCRIPT_DIR/.songs-env"

# Add global variable to track matched files
MATCHED_FILE=""

# Record Filename Check
if [ -z "$RECORD_FILE_NAME" ]; then
    RECORD_FILE_NAME=".downloaded_videos.txt"
    echo "RECORD_FILE_NAME not defined in .songs-env, using default: $RECORD_FILE_NAME"
fi

# Parallel Limit Check
if [ -z "$PARALLEL_LIMIT" ]; then
    PARALLEL_LIMIT=4
    echo "PARALLEL_LIMIT not defined in .songs-env, using default: $PARALLEL_LIMIT"
fi

# Tmux Check
if [ -z "$TMUX" ] && [ "$1" != "--inside-tmux" ]; then
    echo "Starting download script in a tmux session..."

    if ! command -v tmux &> /dev/null; then
        echo "tmux is not installed. Please install it with: apt-get install tmux"
        exit 1
    fi
    
    tmux new-session -d -s songs-download "$0 --inside-tmux"
    echo "Download process started in tmux session. To view progress, run:"
    echo "tmux attach -t songs-download"
    exit 0
fi

# Downloader Check
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

# Metadata Editor Check
if command -v eyeD3 &> /dev/null; then
    METADATA_TOOL="eyeD3"
    METADATA_TOOL_AVAILABLE=true
else
    echo "No MP3 tag editor found. Metadata updates will be skipped."
    echo "Please install eyeD3."
    echo "sudo apt install eyed3"
    METADATA_TOOL_AVAILABLE=false
fi

update_mp3_metadata() {
    local MP3_FILE="$1"
    
    if [[ "$METADATA_TOOL_AVAILABLE" == true && -f "$MP3_FILE" ]]; then
        local FILENAME=$(basename "$MP3_FILE")
        local TITLE="${FILENAME%.mp3}"
        
        echo "Updating filename metadata for: $FILENAME"
        
        case "$METADATA_TOOL" in
            "eyeD3")
                eyeD3 --title="$TITLE" "$MP3_FILE" >/dev/null 2>&1
                ;;
        esac
    fi
}


get_video_id() {
    local URL="$1"
    local VIDEO_ID=""
    
    if [[ "$URL" == *"youtu.be/"* ]]; then
        VIDEO_ID=$(echo "$URL" | sed -E 's|.*youtu\.be/([^?&]+).*|\1|')
    elif [[ "$URL" == *"youtube.com/watch"* ]]; then
        VIDEO_ID=$(echo "$URL" | sed -E 's|.*[?&]v=([^&]+).*|\1|')
    fi
    
    echo "$VIDEO_ID"
}

song_exists() {
    local VIDEO_URL="$1"
    local VIDEO_ID="$2"
    local SONG_TITLE="$3"
    local PLAYLIST_FOLDER="$4"
    
    # Reset the global matched file
    MATCHED_FILE=""
    
    local RECORD_FILE="$PLAYLIST_FOLDER/$RECORD_FILE_NAME"
    if [[ -f "$RECORD_FILE" && $(grep -c "^$VIDEO_ID$" "$RECORD_FILE") -gt 0 ]]; then
        echo "Found video ID in record file: $VIDEO_ID"
        
        # Find the corresponding file for renaming purposes
        for existing_file in "$PLAYLIST_FOLDER"/*.mp3; do
            if [[ -f "$existing_file" ]]; then
                MATCHED_FILE="$existing_file"
                break
            fi
        done
        
        return 0
    fi
    
    return 1
}

record_downloaded_song() {
    local VIDEO_ID="$1"
    local PLAYLIST_FOLDER="$2"
    
    if [[ -n "$VIDEO_ID" ]]; then
        local RECORD_FILE="$PLAYLIST_FOLDER/$RECORD_FILE_NAME"
        mkdir -p "$PLAYLIST_FOLDER"
        echo "$VIDEO_ID" >> "$RECORD_FILE"
        echo "Recorded downloaded song ID: $VIDEO_ID"
    fi
}

clean_title() {
    echo "$1" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]' | tr -s ' '
}

# Function to process a single playlist
process_playlist() {
    local URL="$1"
    local PLAYLIST_NUM="$2"
    
    # Create a unique prefix for this playlist's output
    local PREFIX="[Playlist $PLAYLIST_NUM]"
    
    echo "$PREFIX Processing $URL..."

    # Try to get playlist name with longer timeout and better error handling
    echo "$PREFIX Attempting to fetch playlist title..."
    PLAYLIST_NAME=$(timeout 60s "$DOWNLOADER_PATH" --print "%(playlist_title)s" "$URL" 2>&1 | head -n 1)
    
    # Check if the command failed or returned empty
    if [[ -z "$PLAYLIST_NAME" || "$PLAYLIST_NAME" == *"ERROR"* || "$PLAYLIST_NAME" == *"WARNING"* ]]; then
        echo "$PREFIX Failed to fetch playlist title, trying alternative method..."
        
        # Try with different approach - extract playlist info
        PLAYLIST_NAME=$(timeout 60s "$DOWNLOADER_PATH" --flat-playlist --print "%(playlist_title)s" "$URL" 2>/dev/null | head -n 1)
        
        # If still empty, create a fallback name from URL
        if [[ -z "$PLAYLIST_NAME" || "$PLAYLIST_NAME" == *"ERROR"* ]]; then
            # Extract playlist ID from URL and use it as name
            if [[ "$URL" =~ list=([^&]+) ]]; then
                PLAYLIST_ID="${BASH_REMATCH[1]}"
                PLAYLIST_NAME="Playlist_${PLAYLIST_ID}"
                echo "$PREFIX Using fallback playlist name: $PLAYLIST_NAME"
            else
                echo "$PREFIX Failed to extract playlist ID from URL. Skipping..."
                return
            fi
        else
            echo "$PREFIX Successfully fetched playlist title with alternative method: $PLAYLIST_NAME"
        fi
    else
        echo "$PREFIX Successfully fetched playlist title: $PLAYLIST_NAME"
    fi

    PLAYLIST_FOLDER="$BASE_FOLDER/$PLAYLIST_NAME"

    mkdir -p "$PLAYLIST_FOLDER"
    
    echo "$PREFIX Retrieving song list for '$PLAYLIST_NAME'..."
    SONG_LIST=$(timeout 60s "$DOWNLOADER_PATH" --flat-playlist --print "%(playlist_index)s|||%(title)s|||%(id)s" "$URL" 2>/dev/null)
    
    echo "$SONG_LIST" | while IFS='|||' read -r INDEX TITLE VIDEO_ID; do
        if [[ -z "$INDEX" || -z "$TITLE" || -z "$VIDEO_ID" ]]; then
            continue
        fi
        
        # Clean up video ID - remove any URL encoding or extra characters
        VIDEO_ID=$(echo "$VIDEO_ID" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/[^a-zA-Z0-9_-].*//')
        
        # Validate video ID format (YouTube video IDs are 11 characters of alphanumeric, underscore, hyphen)
        if [[ ! "$VIDEO_ID" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
            echo "$PREFIX Warning: Invalid video ID format '$VIDEO_ID', skipping..."
            continue
        fi
        
        # Fix parsing of INDEX - ensure it's treated as a number
        INDEX=$(echo "$INDEX" | sed 's/^0*//')
        if [[ -z "$INDEX" ]]; then
            INDEX=1
        fi
        
        # Format the index with leading zeros
        FORMATTED_INDEX=$(printf "%03d" "$INDEX")
        
        echo "$PREFIX Processing song: $TITLE (Position: $INDEX, Formatted: $FORMATTED_INDEX)"
        
        VIDEO_URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
        
        if song_exists "$VIDEO_URL" "$VIDEO_ID" "$TITLE" "$PLAYLIST_FOLDER"; then
            echo "$PREFIX Song '$TITLE' already exists in record, checking for index updates..."
            
            # Find the file that corresponds to this video ID by checking all mp3 files
            MATCHED_FILE=""
            for existing_file in "$PLAYLIST_FOLDER"/*.mp3; do
                if [[ -f "$existing_file" ]]; then
                    MATCHED_FILE="$existing_file"
                    break
                fi
            done
            
            if [[ -n "$MATCHED_FILE" && -f "$MATCHED_FILE" ]]; then
                EXISTING_BASENAME=$(basename "$MATCHED_FILE")
                
                # Improved extraction of current index from filename
                if [[ "$EXISTING_BASENAME" =~ ^([0-9]{3})\ -\ (.*)\.mp3$ ]]; then
                    EXISTING_INDEX="${BASH_REMATCH[1]}"
                    EXISTING_TITLE="${BASH_REMATCH[2]}"
                else
                    echo "$PREFIX Warning: Cannot parse index from filename: $EXISTING_BASENAME"
                    continue
                fi
                
                echo "$PREFIX Current file index: $EXISTING_INDEX, New index: $FORMATTED_INDEX"
                
                if [[ "$EXISTING_INDEX" != "$FORMATTED_INDEX" ]]; then
                    NEW_NAME="$PLAYLIST_FOLDER/${FORMATTED_INDEX} - ${TITLE}.mp3"
                    echo "$PREFIX Updating song index from $EXISTING_INDEX to $FORMATTED_INDEX"
                    echo "$PREFIX Renaming: $MATCHED_FILE -> $NEW_NAME"
                    mv "$MATCHED_FILE" "$NEW_NAME"
                    update_mp3_metadata "$NEW_NAME"
                else
                    echo "$PREFIX Index unchanged, no need to rename"
                fi
            else
                echo "$PREFIX No mp3 files found in folder for renaming"
            fi
        else
            echo "$PREFIX Downloading song: $TITLE (ID: $VIDEO_ID)"
            "$DOWNLOADER_PATH" -o "$PLAYLIST_FOLDER/${FORMATTED_INDEX} - %(title)s.%(ext)s" \
                --format "bestaudio[ext=m4a]/best" \
                --extract-audio \
                --audio-format mp3 \
                --audio-quality 0 \
                --embed-thumbnail \
                --add-metadata \
                --postprocessor-args "-metadata author='%(artist)s'" \
                "$VIDEO_URL"
            
            if [ $? -eq 0 ]; then
                record_downloaded_song "$VIDEO_ID" "$PLAYLIST_FOLDER"
                DOWNLOADED_FILE="$PLAYLIST_FOLDER/${FORMATTED_INDEX} - ${TITLE}.mp3"
                update_mp3_metadata "$DOWNLOADED_FILE"
                echo "$PREFIX Successfully downloaded: $TITLE"
            else
                echo "$PREFIX Failed to download: $TITLE"
            fi
        fi
    done
    
    echo "$PREFIX Completed processing playlist: $PLAYLIST_NAME"
}

# Process all playlists with parallel limit
echo "Starting processing of ${#PLAYLISTS[@]} playlists with parallel limit of $PARALLEL_LIMIT..."
pids=()
playlist_count=0

for URL in "${PLAYLISTS[@]}"; do
    # Wait if we've reached the parallel limit
    while [ ${#pids[@]} -ge $PARALLEL_LIMIT ]; do
        # Check for completed processes
        new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 $pid 2>/dev/null; then
                new_pids+=($pid)
            else
                wait $pid
                echo "Playlist process $pid completed"
            fi
        done
        pids=("${new_pids[@]}")
        
        # Small delay to avoid busy waiting
        if [ ${#pids[@]} -ge $PARALLEL_LIMIT ]; then
            sleep 1
        fi
    done
    
    # Start new playlist process
    ((playlist_count++))
    process_playlist "$URL" "$playlist_count" &
    pids+=($!)
    echo "Started processing playlist $playlist_count: $URL (PID: $!)"
done

# Wait for all remaining background processes to complete
echo "Waiting for remaining playlist downloads to complete..."
for pid in "${pids[@]}"; do
    wait $pid
    echo "Playlist process $pid completed"
done

echo "All playlist downloads completed!"

if [[ "$METADATA_TOOL_AVAILABLE" == true ]]; then
    echo "Checking and updating metadata for all existing songs..."
    for PLAYLIST_DIR in "$BASE_FOLDER"/*; do
        if [[ -d "$PLAYLIST_DIR" ]]; then
            PLAYLIST_NAME=$(basename "$PLAYLIST_DIR")
            echo "Processing playlist folder: $PLAYLIST_NAME"
            
            for MP3_FILE in "$PLAYLIST_DIR"/*.mp3; do
                if [[ -f "$MP3_FILE" ]]; then
                    update_mp3_metadata "$MP3_FILE"
                fi
            done
        fi
    done
    echo "Metadata update completed."
fi

echo "All downloads completed. Playlists saved to $BASE_FOLDER."

if [ -n "$TMUX" ] && [ "$1" == "--inside-tmux" ]; then
    echo "Downloads complete. Automatically terminating tmux session in 3 seconds..."
    sleep 3
    tmux kill-session -t songs-download
fi
