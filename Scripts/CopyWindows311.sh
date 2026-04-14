#!/bin/bash
# CopyWindows311.sh
# Copies Windows 3.11 base files to the app bundle Resources folder

set -e

SOURCE_DIR="${SRCROOT}/Resources/Windows311"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Windows311"

if [ -d "$SOURCE_DIR" ]; then
    echo "Copying Windows 3.11 files to app bundle..."
    mkdir -p "$DEST_DIR"
    cp -R "$SOURCE_DIR"/"*" "$DEST_DIR"/ 2>/dev/null || true
    echo "Windows 3.11 files copied successfully"
else
    echo "Warning: Windows311 folder not found at $SOURCE_DIR"
fi
