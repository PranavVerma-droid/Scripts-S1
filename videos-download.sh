#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Environment Checking
if [ ! -f "$SCRIPT_DIR/.videos-env" ]; then
    echo -e "\e[31mERROR: File Not Found at $SCRIPT_DIR/.videos-env\e[0m"
    echo -e "Please Create one and Add This Content:"
    echo -e ""
    echo -e "\e[33mexport BASE_FOLDER=\"/videos/All Videos\""
    echo -e "export COOKIES_FILE=\"/scripts/cookies.txt\""
    echo -e "export DOWNLOADER_PATH=\"/videos/Binary/downloader\""
    echo -e "export RECORD_FILE_NAME=\".downloaded_videos.txt\""
    echo -e "declare -a VIDEO_SOURCES=(\nVIDEO-1-URL\nVIDEO-2-URL\nVIDEO-3-URL\n)\e[0m"
    exit 1
fi

source "$SCRIPT_DIR/.videos-env"

# Record File Checking
if [ -z "$RECORD_FILE_NAME" ]; then
    RECORD_FILE_NAME=".downloaded_videos.txt"
    echo "RECORD_FILE_NAME not defined in .videos-env, using default: $RECORD_FILE_NAME"
fi

# Tmux Check
if [ -z "$TMUX" ] && [ "$1" != "--inside-tmux" ]; then
    echo "Starting download script in a tmux session..."
    
    if ! command -v tmux &> /dev/null; then
        echo "tmux is not installed. Please install it with: apt-get install tmux"
        exit 1
    fi
    
    tmux new-session -d -s videos-download "$0 --inside-tmux"
    echo "Download process started in tmux session. To view progress, run:"
    echo "tmux attach -t videos-download"
    exit 0
fi


# Cookies File Checking
USE_COOKIES=false
if [ -f "$COOKIES_FILE" ]; then
    USE_COOKIES=true
    echo "Found cookies file. Will use authentication for age-restricted videos."
else
    echo "No cookies file found at $COOKIES_FILE. Age-restricted videos might fail to download."
    echo "To download age-restricted videos, export cookies from your browser using the 'Get cookies.txt' extension."
    echo "When using the extension, select 'Current Site' option while on youtube.com"
fi


# yt-dlp Checking & Updating
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


# Atomic Parsley Checking
if ! command -v AtomicParsley &> /dev/null; then
    echo "Warning: AtomicParsley not found. This may affect thumbnail embedding."
    echo "Consider installing it with: apt-get install atomicparsley"
fi


get_channel_name() {
    local VIDEO_URL="$1"
    local CHANNEL_NAME=""
    
    # Method 1: Direct channel access with increased timeout
    if $USE_COOKIES; then
        CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --cookies "$COOKIES_FILE" --print "%(channel)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    else
        CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(channel)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    fi
    
    # Method 2: Try with uploader instead of channel
    if [[ -z "$CHANNEL_NAME" ]]; then
        if $USE_COOKIES; then
            CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --cookies "$COOKIES_FILE" --print "%(uploader)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
        else
            CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(uploader)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
        fi
    fi
    
    # Method 3: For YouTube URLs, try to extract ID and use it directly
    if [[ -z "$CHANNEL_NAME" && ("$VIDEO_URL" == *"youtu.be"* || "$VIDEO_URL" == *"youtube.com"*) ]]; then
        local VIDEO_ID=""
        if [[ "$VIDEO_URL" == *"youtu.be"* ]]; then
            VIDEO_ID=$(echo "$VIDEO_URL" | sed -E 's/.*youtu\.be\/([^?]+).*/\1/')
        elif [[ "$VIDEO_URL" == *"youtube.com/watch"* ]]; then
            VIDEO_ID=$(echo "$VIDEO_URL" | sed -E 's/.*[?&]v=([^&]+).*/\1/')
        fi
        
        if [[ -n "$VIDEO_ID" ]]; then
            CLEAN_URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
            if $USE_COOKIES; then
                CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --cookies "$COOKIES_FILE" --print "%(channel)s" "$CLEAN_URL" 2>/dev/null | head -n 1)
                
                if [[ -z "$CHANNEL_NAME" ]]; then
                    CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --cookies "$COOKIES_FILE" --print "%(uploader)s" "$CLEAN_URL" 2>/dev/null | head -n 1)
                fi
            else
                CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(channel)s" "$CLEAN_URL" 2>/dev/null | head -n 1)
                
                if [[ -z "$CHANNEL_NAME" ]]; then
                    CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(uploader)s" "$CLEAN_URL" 2>/dev/null | head -n 1)
                fi
            fi
        fi
    fi
    
    if [[ -z "$CHANNEL_NAME" ]]; then
        local VIDEO_TITLE
        if $USE_COOKIES; then
            VIDEO_TITLE=$(timeout 30s "$DOWNLOADER_PATH" --cookies "$COOKIES_FILE" --print "%(title)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
        else
            VIDEO_TITLE=$(timeout 30s "$DOWNLOADER_PATH" --print "%(title)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
        fi
        
        if [[ -n "$VIDEO_TITLE" ]]; then
            echo "Single_Video_${VIDEO_TITLE:0:20}"
        else
            echo "YouTube_Creator_$(date +%Y%m%d_%H%M%S)"
        fi
    else
        echo "$CHANNEL_NAME"
    fi
}

get_video_id() {
    local URL="$1"
    local VIDEO_ID=""
    
    if [[ "$URL" == *"youtu.be/"* ]]; then
        # https://youtu.be/VIDEO_ID
        VIDEO_ID=$(echo "$URL" | sed -E 's|.*youtu\.be/([^?&]+).*|\1|')
    elif [[ "$URL" == *"youtube.com/watch"* ]]; then
        # https://www.youtube.com/watch?v=VIDEO_ID
        VIDEO_ID=$(echo "$URL" | sed -E 's|.*[?&]v=([^&]+).*|\1|')
    fi
    
    echo "$VIDEO_ID"
}

video_exists() {
    local VIDEO_URL="$1"
    local CREATOR_FOLDER="$2"
    local VIDEO_ID=$(get_video_id "$VIDEO_URL")
    local VIDEO_TITLE=""
    
    if [[ -n "$VIDEO_ID" ]]; then
        local RECORD_FILE="$CREATOR_FOLDER/$RECORD_FILE_NAME"
        if [[ -f "$RECORD_FILE" && $(grep -c "$VIDEO_ID" "$RECORD_FILE") -gt 0 ]]; then
            echo "Found video ID match in record file: $VIDEO_ID"
            return 0
        fi
        
        if [[ -d "$CREATOR_FOLDER" ]]; then
            for existing_file in "$CREATOR_FOLDER"/*.mp4; do
                if [[ -f "$existing_file" && "$existing_file" == *"$VIDEO_ID"* ]]; then
                    echo "Found video ID in filename: $existing_file"
                    mkdir -p "$CREATOR_FOLDER"
                    echo "$VIDEO_ID" >> "$RECORD_FILE"
                    return 0 
                fi
            done
        fi
    fi
    
    if $USE_COOKIES; then
        VIDEO_TITLE=$(timeout 30s "$DOWNLOADER_PATH" --cookies "$COOKIES_FILE" --print "%(title)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    else
        VIDEO_TITLE=$(timeout 30s "$DOWNLOADER_PATH" --print "%(title)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    fi
    
    if [[ -z "$VIDEO_TITLE" ]]; then
        echo "Could not retrieve video title for $VIDEO_URL"
        return 1 
    fi
    
    VIDEO_TITLE=$(echo "$VIDEO_TITLE" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
    echo "Checking for existing video with title: $VIDEO_TITLE"
    
    local found=0
    if [[ -d "$CREATOR_FOLDER" ]]; then
        for existing_file in "$CREATOR_FOLDER"/*.mp4; do
            if [[ -f "$existing_file" ]]; then
                local base_name=$(basename "$existing_file" .mp4)
                local normalized_name=$(echo "$base_name" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
                
                # Calculate similarity between titles
                local similarity=0
                local match_threshold=70 # percentage
                
                # Simple but effective similarity check - count common words
                local title_words=($VIDEO_TITLE)
                local name_words=($normalized_name)
                local common_words=0
                local total_words=${#title_words[@]}
                
                for word in "${title_words[@]}"; do
                    # Skip very short words (a, an, the, etc.)
                    if [[ ${#word} -lt 3 ]]; then continue; fi
                    
                    # Check if this word appears in the existing filename
                    if [[ "$normalized_name" == *"$word"* ]]; then
                        ((common_words++))
                    fi
                done
                
                # Calculate similarity percentage if we have words to compare
                if [[ $total_words -gt 0 ]]; then
                    similarity=$((common_words * 100 / total_words))
                fi
                
                # If high similarity or one title contains the other completely
                if [[ $similarity -ge $match_threshold || "$normalized_name" == *"$VIDEO_TITLE"* || "$VIDEO_TITLE" == *"$normalized_name"* ]]; then
                    found=1
                    echo "Found existing video by title match: $existing_file (Similarity: $similarity%)"
                    
                    # Save the video ID in our record file for future lookups
                    if [[ -n "$VIDEO_ID" ]]; then
                        mkdir -p "$CREATOR_FOLDER"
                        echo "$VIDEO_ID" >> "$RECORD_FILE"
                    fi
                    break
                fi
            fi
        done
    fi
    
    return $((1 - found))
}

# Function to record downloaded video
record_downloaded_video() {
    local VIDEO_URL="$1"
    local CREATOR_FOLDER="$2"
    local VIDEO_ID=$(get_video_id "$VIDEO_URL")
    
    if [[ -n "$VIDEO_ID" ]]; then
        local RECORD_FILE="$CREATOR_FOLDER/$RECORD_FILE_NAME"
        mkdir -p "$CREATOR_FOLDER"
        echo "$VIDEO_ID" >> "$RECORD_FILE"
        echo "Recorded downloaded video ID: $VIDEO_ID"
    fi
}

# Function to download a single video and save it in creator's folder
download_video() {
    local VIDEO_URL="$1"
    
    echo "Processing video: $VIDEO_URL"
    
    # Get channel name with improved detection
    CREATOR_NAME=$(get_channel_name "$VIDEO_URL")
    
    # Create folder structure
    CREATOR_FOLDER="$BASE_FOLDER/$CREATOR_NAME"
    mkdir -p "$CREATOR_FOLDER"
    
    # Check if video already exists
    if video_exists "$VIDEO_URL" "$CREATOR_FOLDER"; then
        echo "Video already exists in $CREATOR_FOLDER, skipping download."
        return 0
    fi
    
    echo "Downloading to creator folder: $CREATOR_NAME"
    
    # Set up base command
    local DOWNLOAD_OPTS=(
        "-o" "$CREATOR_FOLDER/%(title)s.%(ext)s"
        "--format" "bestvideo[height<=1080][vcodec!*=av01][vcodec!*=vp9]+bestaudio/best[height<=1080][vcodec!*=av01]"
        "--merge-output-format" "mp4"
        "--prefer-ffmpeg"
        "--embed-thumbnail"
        "--embed-metadata"
        "--add-metadata"
        "--convert-thumbnails" "jpg"
        "--remux-video" "mp4"
        "--no-keep-video"
        "--no-mtime"
        "--continue"
        "--ignore-errors"
    )
    
    # Add cookies if available
    if $USE_COOKIES; then
        DOWNLOAD_OPTS+=("--cookies" "$COOKIES_FILE")
    fi
    
    # Try first with more compatible formats, avoiding AV1
    "$DOWNLOADER_PATH" "${DOWNLOAD_OPTS[@]}" "$VIDEO_URL"
    local download_status=$?
        
    # If the above fails, try with more compatible format
    if [ $download_status -ne 0 ]; then
        echo "First attempt failed. Trying with more compatible format..."
        
        # Reset options for second attempt
        DOWNLOAD_OPTS=(
            "-o" "$CREATOR_FOLDER/%(title)s.%(ext)s"
            "--format" "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best"
            "--merge-output-format" "mp4"
            "--prefer-ffmpeg"
            "--embed-thumbnail"
            "--embed-metadata"
            "--add-metadata"
            "--continue"
            "--ignore-errors"
        )
        
        # Add cookies if available
        if $USE_COOKIES; then
            DOWNLOAD_OPTS+=("--cookies" "$COOKIES_FILE")
        fi
        
        "$DOWNLOADER_PATH" "${DOWNLOAD_OPTS[@]}" "$VIDEO_URL"
        download_status=$?
            
        # If that also fails, try with simpler format
        if [ $download_status -ne 0 ]; then
            echo "Second attempt failed. Trying with simple format..."
            
            # Reset options for third attempt
            DOWNLOAD_OPTS=(
                "-o" "$CREATOR_FOLDER/%(title)s.%(ext)s"
                "--format" "18/22/best"
                "--prefer-ffmpeg"
                "--embed-thumbnail"
                "--embed-metadata"
                "--continue"
                "--ignore-errors"
            )
            
            # Add cookies if available
            if $USE_COOKIES; then
                DOWNLOAD_OPTS+=("--cookies" "$COOKIES_FILE")
            fi
            
            "$DOWNLOADER_PATH" "${DOWNLOAD_OPTS[@]}" "$VIDEO_URL"
            download_status=$?
        fi
    fi
    
    # Record the video as downloaded if any download attempt succeeded
    if [ $download_status -eq 0 ]; then
        record_downloaded_video "$VIDEO_URL" "$CREATOR_FOLDER"
    fi
    
    # Clean up any leftover thumbnail files
    echo "Cleaning up any leftover thumbnail files in $CREATOR_FOLDER..."
    find "$CREATOR_FOLDER" -name "*.jpg" -type f -delete
}

# Process each source URL
for URL in "${VIDEO_SOURCES[@]}"; do
    echo "Processing source: $URL..."

    # Check if the URL is a playlist
    if [[ "$URL" == *"/playlist"* ]]; then
        echo "Handling playlist: $URL"
        
        # First extract all video IDs from the playlist
        echo "Extracting videos from playlist..."
        
        # Set up extract command
        EXTRACT_OPTS=(
            "--flat-playlist"
            "--print" "%(id)s"
        )
        
        # Add cookies if available
        if $USE_COOKIES; then
            EXTRACT_OPTS+=("--cookies" "$COOKIES_FILE")
        fi
        
        VIDEO_IDS=$(timeout 60s "$DOWNLOADER_PATH" "${EXTRACT_OPTS[@]}" "$URL" 2>/dev/null)
        
        # Check if we got any video IDs
        if [[ -z "$VIDEO_IDS" ]]; then
            echo "Failed to extract videos from playlist $URL. Skipping..."
            continue
        fi
        
        # Process each video in the playlist
        echo "Processing individual videos from playlist..."
        while IFS= read -r VIDEO_ID; do
            if [[ -n "$VIDEO_ID" ]]; then
                VIDEO_URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
                download_video "$VIDEO_URL"
            fi
        done <<< "$VIDEO_IDS"
        
    else
        if [[ "$URL" == *"youtu.be"* || "$URL" == *"youtube.com/watch"* ]]; then
            # Single video
            download_video "$URL"
        else
            # Channel - extract all video IDs first
            echo "Handling channel: $URL"
            
            # Get channel videos
            CHANNEL_VIDEOS=$(timeout 60s "$DOWNLOADER_PATH" --flat-playlist --print "%(id)s" "$URL/videos" 2>/dev/null)
            
            # Check if we got any video IDs
            if [[ -z "$CHANNEL_VIDEOS" ]]; then
                echo "Failed to extract videos from channel $URL. Skipping..."
                continue
            fi

            while IFS= read -r VIDEO_ID; do
                if [[ -n "$VIDEO_ID" ]]; then
                    VIDEO_URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
                    download_video "$VIDEO_URL"
                fi
            done <<< "$CHANNEL_VIDEOS"
        fi
    fi
done

echo "All video downloads completed. Videos saved to $BASE_FOLDER."

if [ -n "$TMUX" ] && [ "$1" == "--inside-tmux" ]; then
    echo "Downloads complete. Automatically terminating tmux session in 3 seconds..."
    sleep 3
    tmux kill-session -t videos-download
fi
