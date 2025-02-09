#!/bin/bash

# Check if the directory argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

if ! gpg --list-secret-keys | grep -q "pranav@verma.net.in"; then
    echo "Error: GPG decryption key is missing!"
    exit 1
fi

TARGET_DIR="$1"

# Check if the directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

echo "Starting decryption in: $TARGET_DIR"

find "$TARGET_DIR" -type f -name "*.gpg" | while read -r encrypted_file; do
    decrypted_file="${encrypted_file%.gpg}"
    
    echo "Decrypting: $encrypted_file"
    gpg --batch --yes --decrypt --output "$decrypted_file" "$encrypted_file"

    if [ $? -eq 0 ]; then
        echo "Decryption successful: $decrypted_file"
        rm -v "$encrypted_file"
    else
        echo "Failed to decrypt: $encrypted_file"
    fi
done

echo "Decryption process completed!"
