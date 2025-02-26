#!/bin/bash

# Usage: ./decrypt.sh <FOLDER_NAME>
# This script will scan for chunked backups / normal backups and restore them (using the GPG key)
# Before running this script, make sure you have the appropriate GPG key in your toolchain.

if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

if ! gpg --list-secret-keys | grep -q "pranav@verma.net.in"; then
    echo "Error: GPG decryption key is missing!"
    exit 1
fi

TARGET_DIR="$1"
TEMP_DIR="/tmp/decrypt_$$"

mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

echo "Starting decryption in: $TARGET_DIR"

process_chunked_archive() {
    local base_path="$1"
    local base_name="$(basename "$base_path" .chunk.aa.gpg)"
    local target_path="$TEMP_DIR/$base_name"
    local extract_dir="$(dirname "$base_path")"
    local success=true

    echo "----------------------------------------"
    echo "PROCESSING CHUNKED ARCHIVE"
    echo "Base name: $base_name"
    echo "Extract directory: $extract_dir"
    echo "This archive was split into multiple chunks"
    echo "----------------------------------------"

    # Create a temporary directory for chunks
    local chunk_dir="$TEMP_DIR/chunks_$$"
    mkdir -p "$chunk_dir"
    
    # First decrypt all chunks
    for chunk in "$TARGET_DIR/${base_name}.chunk."*".gpg"; do
        local decrypted_chunk="$chunk_dir/$(basename "$chunk" .gpg)"
        
        echo "Decrypting chunk: $chunk"
        if ! gpg --batch --yes --decrypt --output "$decrypted_chunk" "$chunk"; then
            echo "Failed to decrypt chunk: $chunk"
            rm -rf "$chunk_dir"
            return 1
        fi
    done

    # Concatenate chunks into final zip
    echo "Reassembling chunks into complete archive..."
    cat "$chunk_dir"/* > "$target_path"
    rm -rf "$chunk_dir"
    
    echo "Extracting reassembled archive to: $extract_dir"
    if unzip -q "$target_path" -d "$extract_dir"; then
        echo "Successfully extracted: $base_name"
        rm -f "$target_path"
        # Only remove encrypted chunks after successful extraction
        rm -f "$TARGET_DIR/${base_name}.chunk."*".gpg"
        return 0
    else
        echo "Failed to extract: $target_path"
        rm -f "$target_path"
        return 1
    fi
}

# Process files
find "$TARGET_DIR" -type f -name "*.gpg" | while read -r encrypted_file; do
    # Check if this is part of a chunked archive
    if [[ $encrypted_file =~ \.chunk\.[a-z]+\.gpg$ ]]; then
        # Only process the first chunk to avoid redundant operations
        if [[ $encrypted_file =~ \.chunk\.aa\.gpg$ ]]; then
            process_chunked_archive "$encrypted_file"
        fi
        continue
    fi

    # Process regular encrypted files
    decrypted_file="${encrypted_file%.gpg}"
    
    echo "----------------------------------------"
    echo "PROCESSING SINGLE ARCHIVE"
    echo "File: $(basename "$encrypted_file")"
    echo "This is a non-chunked archive"
    echo "----------------------------------------"
    
    echo "Decrypting: $encrypted_file"
    if gpg --batch --yes --decrypt --output "$decrypted_file" "$encrypted_file"; then
        echo "Decryption successful: $decrypted_file"
        
        # If it's a zip file, extract it
        if [[ $decrypted_file == *.zip ]]; then
            echo "Extracting: $decrypted_file"
            if unzip -q "$decrypted_file" -d "$(dirname "$decrypted_file")"; then
                echo "Extraction successful"
                rm -f "$decrypted_file"
            else
                echo "Extraction failed: $decrypted_file"
            fi
        fi
        
        rm -v "$encrypted_file"
    else
        echo "Failed to decrypt: $encrypted_file"
    fi
done

echo "Decryption process completed!"
