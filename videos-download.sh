#!/bin/bash

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

# Function to download a single video and save it in creator's folder
download_video() {
    local VIDEO_URL="$1"
    
    echo "Processing video: $VIDEO_URL"
    
    # Get channel name for the video
    CREATOR_NAME=$(timeout 30s "$DOWNLOADER_PATH" --print "%(channel)s" "$VIDEO_URL" 2>/dev/null | head -n 1)
    if [[ -z "$CREATOR_NAME" ]]; then
        echo "Failed to fetch channel name for $VIDEO_URL. Using fallback name..."
        CREATOR_NAME="Unknown_Creator"
    fi
    
    # Create folder structure
    CREATOR_FOLDER="$BASE_FOLDER/$CREATOR_NAME"
    mkdir -p "$CREATOR_FOLDER"
    
    echo "Downloading to creator folder: $CREATOR_NAME"
    
    # Download video with improved format selection
    "$DOWNLOADER_PATH" -o "$CREATOR_FOLDER/%(title)s.%(ext)s" \
        --format "bestvideo[height<=1080][vcodec!*=av01][vcodec!*=vp9]+bestaudio/best[height<=1080]" \
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
        
    # If the above fails, try with a more compatible format
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
