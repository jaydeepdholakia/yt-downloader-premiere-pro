#!/bin/bash
#
# YT Downloader Uninstaller
#

echo ""
echo "=========================================="
echo "   YT Downloader Uninstaller"
echo "=========================================="
echo ""

INSTALL_DIR="$HOME/Library/Application Support/YTDownloader"
CEP_DIR="$HOME/Library/Application Support/Adobe/CEP/extensions"
EXTENSION_ID="com.ytdownloader.panel"
TARGET_LINK="$CEP_DIR/$EXTENSION_ID"

# Check if installed
if [ ! -d "$INSTALL_DIR" ] && [ ! -L "$TARGET_LINK" ]; then
    echo "YT Downloader does not appear to be installed."
    echo ""
    echo "Press Enter to close..."
    read
    exit 0
fi

echo "This will remove:"
if [ -d "$INSTALL_DIR" ]; then
    echo "  - $INSTALL_DIR"
fi
if [ -L "$TARGET_LINK" ] || [ -d "$TARGET_LINK" ]; then
    echo "  - $TARGET_LINK (CEP extension link)"
fi
echo ""
read -p "Are you sure you want to uninstall YT Downloader? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Uninstall cancelled."
    echo ""
    echo "Press Enter to close..."
    read
    exit 0
fi

echo ""

# Remove CEP symlink / directory
if [ -L "$TARGET_LINK" ]; then
    rm "$TARGET_LINK"
    echo "  Removed CEP extension link."
elif [ -d "$TARGET_LINK" ]; then
    rm -rf "$TARGET_LINK"
    echo "  Removed CEP extension directory."
fi

# Remove application files
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed application files."
fi

echo ""
echo "=========================================="
echo "   Uninstall Complete"
echo "=========================================="
echo ""
echo "Note: Python packages (fastapi, uvicorn, pytubefix)"
echo "were installed with --user and remain on your system."
echo "To remove them manually:"
echo "  pip3 uninstall fastapi uvicorn pytubefix"
echo ""
echo "Press Enter to close..."
read
