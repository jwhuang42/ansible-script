#!/bin/bash

# URL of the file to download
URL="$1"

# Destination directory where the file will be saved
DESTINATION_DIR="$2"

# Extract the file name from the URL
FILENAME=$(basename "$URL")

# Full path for the destination file
FULL_DESTINATION_PATH="$DESTINATION_DIR/$FILENAME"

# Create the destination directory if it doesn't exist
mkdir -p "$DESTINATION_DIR"

# Check if the file already exists
if [ ! -f "$FULL_DESTINATION_PATH" ]; then
    # Download the file with wget
    wget -q -O "$FULL_DESTINATION_PATH" "$URL"
else
    echo "File '$FULL_DESTINATION_PATH' already exists. Download skipped."
fi