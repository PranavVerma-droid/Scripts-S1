#!/bin/bash

# Define the base folder to save video downloads
BASE_FOLDER="/videos/All Videos"

# Predefined list of video channel/playlist URLs
VIDEO_SOURCES=(
    https://youtu.be/jVpsLMCIB0Y?si=6ebgRVuZ8PePYhY3
    https://youtu.be/c3LVwbEgxik?si=m0E_xzfUOChDSSDs
    https://youtu.be/GYjThNYeokk?si=ZLSm3ckwXPqiANLW
    https://youtu.be/duuTDCQ0wW0?si=9tkSSmfA5sUV6B7B
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

# Process each channel/playlist URL
for URL in "${VIDEO_SOURCES[@]}"; do
    echo "Processing $URL..."

    # Check if the URL is a channel or a playlist
    if [[ "$URL" == *"/playlist"* ]]; then
        # Get playlist name
        CHANNEL_NAME=$(timeout 30s "$DOWNLOADER_PATH" --print "%(playlist_title)s" "$URL" 2>/dev/null | head -n 1)
        if [[ -z "$CHANNEL_NAME" ]]; then
            echo "Failed to fetch playlist title for $URL. Using fallback name..."
            CHANNEL_NAME="Playlist_$(date +%s)"
        fi
        
        # Create folder structure
        CHANNEL_FOLDER="$BASE_FOLDER/$CHANNEL_NAME"
        mkdir -p "$CHANNEL_FOLDER"
        
        echo "Downloading videos from playlist: $CHANNEL_NAME"
        
        # Download all videos in the playlist with improved format selection
        "$DOWNLOADER_PATH" -o "$CHANNEL_FOLDER/%(title)s.%(ext)s" \
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
            "$URL"
    else
        # For individual videos or channels
        if [[ "$URL" == *"youtu.be"* || "$URL" == *"youtube.com/watch"* ]]; then
            # Single video
            echo "Downloading single video: $URL"
            
            # Get channel name for the video
            CHANNEL_NAME=$(timeout 30s "$DOWNLOADER_PATH" --print "%(channel)s" "$URL" 2>/dev/null | head -n 1)
            if [[ -z "$CHANNEL_NAME" ]]; then
                echo "Failed to fetch channel name for $URL. Using fallback name..."
                CHANNEL_NAME="Single_Videos"
            fi
            
            # Create folder structure
            CHANNEL_FOLDER="$BASE_FOLDER/$CHANNEL_NAME"
            mkdir -p "$CHANNEL_FOLDER"
            
            # Download single video with improved format selection
            "$DOWNLOADER_PATH" -o "$CHANNEL_FOLDER/%(title)s.%(ext)s" \
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
                "$URL"
                
            # If the above fails, try with a more compatible format
            if [ $? -ne 0 ]; then
                echo "First attempt failed. Trying with more compatible format..."
                "$DOWNLOADER_PATH" -o "$CHANNEL_FOLDER/%(title)s.%(ext)s" \
                    --format "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
                    --merge-output-format mp4 \
                    --prefer-ffmpeg \
                    --embed-thumbnail \
                    --embed-metadata \
                    --add-metadata \
                    --continue \
                    --ignore-errors \
                    "$URL"
            fi
        else
            # Channel
            CHANNEL_NAME=$(timeout 30s "$DOWNLOADER_PATH" --print "%(channel)s" "$URL/videos" 2>/dev/null | head -n 1)
            if [[ -z "$CHANNEL_NAME" ]]; then
                echo "Failed to fetch channel name for $URL. Using fallback name..."
                CHANNEL_NAME="Channel_$(date +%s)"
            fi
            
            # Create folder structure
            CHANNEL_FOLDER="$BASE_FOLDER/$CHANNEL_NAME"
            mkdir -p "$CHANNEL_FOLDER"
            
            echo "Downloading videos from channel: $CHANNEL_NAME"
            
            # Download channel videos with improved format selection
            "$DOWNLOADER_PATH" -o "$CHANNEL_FOLDER/%(title)s.%(ext)s" \
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
                "$URL/videos"
        fi
    fi
    
    # Clean up any leftover thumbnail files
    echo "Cleaning up any leftover thumbnail files in $CHANNEL_FOLDER..."
    find "$CHANNEL_FOLDER" -name "*.jpg" -type f -delete
done

echo "All video downloads completed. Videos saved to $BASE_FOLDER."
