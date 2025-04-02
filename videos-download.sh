#!/bin/bash

# Check if script is running inside tmux or being called directly
if [ -z "$TMUX" ] && [ "$1" != "--inside-tmux" ]; then
    echo "Starting download script in a tmux session..."
    
    # Check if tmux is installed
    if ! command -v tmux &> /dev/null; then
        echo "tmux is not installed. Please install it with: apt-get install tmux"
        exit 1
    fi
    
    # Create a new tmux session named "video-download" and start script
    tmux new-session -d -s videos-download "$0 --inside-tmux"
    echo "Download process started in tmux session. To view progress, run:"
    echo "tmux attach -t videos-download"
    exit 0
fi

# Define the base folder to save video downloads
BASE_FOLDER="/videos/All Videos"

# Predefined list of video channel/playlist URLs
VIDEO_SOURCES=(
    https://www.youtube.com/playlist?list=PLAhTBeRe8IhMmRve_rSfAgL_dtEXkKh8Z
    https://youtu.be/c3LVwbEgxik?si=m0E_xzfUOChDSSDs
    https://youtu.be/GYjThNYeokk?si=ZLSm3ckwXPqiANLW
    https://youtu.be/duuTDCQ0wW0?si=9tkSSmfA5sUV6B7B
    https://www.youtube.com/playlist?list=PLflqtq8EOGAJSUMtN0WShMybTC7fmRVuj
    https://www.youtube.com/playlist?list=PLCQhb62iYscCMw0E_pWmlG0NCGYnKC2Tz
    https://youtu.be/h6OKgREcHFM?si=l0zG0XzjgUWqfHHo
    https://youtu.be/H0FHMYvCzUg?si=1V7pm1vX5NfYWhbp
    https://youtu.be/3IN_PwQ-3qw?si=xyBFTmKpQyllntxN
    https://youtu.be/l7og5k_M9EY?si=iaBMZ3TmeaELaXXL
    https://www.youtube.com/playlist?list=PLVHVLN5L-O1XQdw5sVsGbV3C-W4AQzVMI
    https://youtu.be/bLVC9fk6JME?si=ynKnKUjRc322lhzr
    https://youtu.be/-1-ldW4kpLM?si=5j1gvBAGZFnKWREf
    https://youtu.be/UXA-Af-JeCE?si=rvjnA_YA_aU6px3e
    https://youtu.be/RgBYohJ7mIk?si=UIw1bARQXHDm_9lY
    https://youtu.be/8fADp43wJwU?si=8bYINkTEb5bv0lsm
    https://youtu.be/zgBTwtg7H8E?si=owsP-ZnBOWGI_6qb
    https://youtu.be/qJZ1Ez28C-A?si=yqXaoDtWbTXyOjNU
    https://youtu.be/OxGsU8oIWjY?si=4R_MihYjIKYhX46L
    https://www.youtube.com/playlist?list=PLkahZjV5wKe8w9GC_n2yyhx6Wj-NKzzeE
    # Add your video channels/playlists here
)

# Specify the path to the downloader binary (update with your binary location)
DOWNLOADER_PATH="/videos/Binary/downloader"

# Check if downloader is installed
if ! command -v "$DOWNLOADER_PATH" &> /dev/null; then
    echo "downloader is not installed or not in the specified location. Please verify the binary location."
    exit 1
fi

# Display information about AV1 codecs
echo "---------------------------------------------------------------------"
echo "INFO: If you encounter AV1 codec issues when playing videos, install:"
echo "  - For Ubuntu/Debian: apt install libdav1d-dev ffmpeg"
echo "  - For Fedora: dnf install dav1d ffmpeg"
echo "  - For Arch: pacman -S dav1d ffmpeg"
echo "  - For Windows: Use VLC or a media player with AV1 support"
echo "---------------------------------------------------------------------"

# Check for AtomicParsley (needed for thumbnail embedding)
if ! command -v AtomicParsley &> /dev/null; then
    echo "Warning: AtomicParsley not found. This may affect thumbnail embedding."
    echo "Consider installing it with: apt-get install atomicparsley"
fi

echo "Updating the downloader..."
"$DOWNLOADER_PATH" -U
if [ $? -ne 0 ]; then
    echo "Failed to update the downloader. Please check for errors."
    exit 1
fi

# Function to get channel name with multiple fallbacks
get_channel_name() {
    local VIDEO_URL="$1"
    local CHANNEL_NAME=""
    
    # Try multiple methods to get the channel name
    # Method 1: Direct channel access with increased timeout
    CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(channel)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    
    # Method 2: Try with uploader instead of channel
    if [[ -z "$CHANNEL_NAME" ]]; then
        CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(uploader)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    fi
    
    # Method 3: For YouTube URLs, try to extract ID and use it directly
    if [[ -z "$CHANNEL_NAME" && ("$VIDEO_URL" == *"youtu.be"* || "$VIDEO_URL" == *"youtube.com"*) ]]; then
        # Extract video ID
        local VIDEO_ID=""
        if [[ "$VIDEO_URL" == *"youtu.be"* ]]; then
            VIDEO_ID=$(echo "$VIDEO_URL" | sed -E 's/.*youtu\.be\/([^?]+).*/\1/')
        elif [[ "$VIDEO_URL" == *"youtube.com/watch"* ]]; then
            VIDEO_ID=$(echo "$VIDEO_URL" | sed -E 's/.*[?&]v=([^&]+).*/\1/')
        fi
        
        if [[ -n "$VIDEO_ID" ]]; then
            # Try clean URL with just video ID
            CLEAN_URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
            CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(channel)s" "$CLEAN_URL" 2>/dev/null | head -n 1)
            
            if [[ -z "$CHANNEL_NAME" ]]; then
                CHANNEL_NAME=$(timeout 45s "$DOWNLOADER_PATH" --print "%(uploader)s" "$CLEAN_URL" 2>/dev/null | head -n 1)
            fi
        fi
    fi
    
    # Provide a descriptive fallback if all methods fail
    if [[ -z "$CHANNEL_NAME" ]]; then
        # Try to get video title for more descriptive fallback
        local VIDEO_TITLE=$(timeout 30s "$DOWNLOADER_PATH" --print "%(title)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
        if [[ -n "$VIDEO_TITLE" ]]; then
            echo "Single_Video_${VIDEO_TITLE:0:20}"
        else
            # Final fallback with timestamp
            echo "YouTube_Creator_$(date +%Y%m%d_%H%M%S)"
        fi
    else
        echo "$CHANNEL_NAME"
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
    
    echo "Downloading to creator folder: $CREATOR_NAME"
    
    # Try first with more compatible formats, avoiding AV1
    "$DOWNLOADER_PATH" -o "$CREATOR_FOLDER/%(title)s.%(ext)s" \
        --format "bestvideo[height<=1080][vcodec!*=av01][vcodec!*=vp9]+bestaudio/best[height<=1080][vcodec!*=av01]" \
        --merge-output-format mp4 \
        --prefer-ffmpeg \
        --embed-thumbnail \
        --embed-metadata \
        --add-metadata \
        --convert-thumbnails jpg \
        --remux-video mp4 \
        --no-keep-video \
        --no-mtime \
        --continue \
        --ignore-errors \
        "$VIDEO_URL"
        
    # If the above fails, try with more compatible format
    if [ $? -ne 0 ]; then
        echo "First attempt failed. Trying with more compatible format..."
        "$DOWNLOADER_PATH" -o "$CREATOR_FOLDER/%(title)s.%(ext)s" \
            --format "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
            --merge-output-format mp4 \
            --prefer-ffmpeg \
            --embed-thumbnail \
            --embed-metadata \
            --add-metadata \
            --continue \
            --ignore-errors \
            "$VIDEO_URL"
            
        # If that also fails, try with simpler format
        if [ $? -ne 0 ]; then
            echo "Second attempt failed. Trying with simple format..."
            "$DOWNLOADER_PATH" -o "$CREATOR_FOLDER/%(title)s.%(ext)s" \
                --format "18/22/best" \
                --prefer-ffmpeg \
                --embed-thumbnail \
                --embed-metadata \
                --continue \
                --ignore-errors \
                "$VIDEO_URL"
        fi
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
        VIDEO_IDS=$(timeout 60s "$DOWNLOADER_PATH" --flat-playlist --print "%(id)s" "$URL" 2>/dev/null)
        
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
        # For individual videos or channels
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
            
            # Process each video in the channel
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
