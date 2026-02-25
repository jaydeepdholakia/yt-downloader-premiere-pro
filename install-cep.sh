#!/bin/bash
# install-cep.sh - Deploy YT Downloader CEP extension for Premiere Pro

set -e

EXTENSION_ID="com.ytdownloader.panel"
CEP_DIR="$HOME/Library/Application Support/Adobe/CEP/extensions"
TARGET_DIR="$CEP_DIR/$EXTENSION_ID"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== YT Downloader CEP Extension Installer ==="
echo ""

# Step 1: Enable CEP debug mode for unsigned extensions
echo "[1/3] Enabling CEP debug mode..."
defaults write com.adobe.CSXS.9 PlayerDebugMode 1
defaults write com.adobe.CSXS.10 PlayerDebugMode 1
defaults write com.adobe.CSXS.11 PlayerDebugMode 1
defaults write com.adobe.CSXS.12 PlayerDebugMode 1
echo "  Done (CSXS 9-12)."

# Step 2: Create extensions directory
echo "[2/3] Creating extension directory..."
mkdir -p "$CEP_DIR"

# Step 3: Symlink extension
echo "[3/3] Linking extension to CEP directory..."
if [ -L "$TARGET_DIR" ]; then
    rm "$TARGET_DIR"
elif [ -d "$TARGET_DIR" ]; then
    echo "  WARNING: Existing directory found. Backing up to ${TARGET_DIR}.bak"
    mv "$TARGET_DIR" "${TARGET_DIR}.bak"
fi

ln -s "$SCRIPT_DIR/cep" "$TARGET_DIR"
echo "  Linked: $TARGET_DIR -> $SCRIPT_DIR/cep"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Start the backend server:"
echo "     cd \"$SCRIPT_DIR\""
echo "     python3 -m uvicorn main:app --host 0.0.0.0 --port 8000"
echo ""
echo "  2. Restart Premiere Pro (or close and reopen it)"
echo ""
echo "  3. Go to: Window > Extensions > YT Downloader"
echo ""
