#!/bin/bash
#
# YT Downloader Installer
# Installs the YT Downloader app and Premiere Pro CEP extension.
#

# If not running inside a terminal, relaunch inside Terminal.app
if [ ! -t 1 ]; then
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    open -a Terminal.app "$SCRIPT_PATH"
    exit 0
fi

set -e

# ── Paths ────────────────────────────────────────────────────────────────────
APP_BUNDLE="$(cd "$(dirname "$0")/../.." && pwd)"
PAYLOAD_DIR="$APP_BUNDLE/Contents/Resources/payload"
INSTALL_DIR="$HOME/Library/Application Support/YTDownloader"
CEP_DIR="$HOME/Library/Application Support/Adobe/CEP/extensions"
EXTENSION_ID="com.ytdownloader.panel"
TARGET_LINK="$CEP_DIR/$EXTENSION_ID"

echo ""
echo "=========================================="
echo "   YT Downloader Installer"
echo "=========================================="
echo ""

# ── Check payload exists ────────────────────────────────────────────────────
if [ ! -d "$PAYLOAD_DIR" ]; then
    echo "ERROR: Installer payload not found."
    echo "  Expected at: $PAYLOAD_DIR"
    echo ""
    echo "Make sure you are running this from the DMG."
    echo ""
    echo "Press Enter to exit..."
    read
    exit 1
fi

# ── Check Python 3 ──────────────────────────────────────────────────────────
echo "[1/6] Checking Python 3..."
if ! command -v /usr/bin/python3 &>/dev/null; then
    echo ""
    echo "ERROR: Python 3 is required but /usr/bin/python3 was not found."
    echo ""
    echo "Install it by running:"
    echo "  xcode-select --install"
    echo ""
    echo "Or download from: https://www.python.org/downloads/"
    echo ""
    echo "Press Enter to exit..."
    read
    exit 1
fi
PYTHON_VERSION=$(/usr/bin/python3 --version 2>&1)
echo "  Found: $PYTHON_VERSION"

# ── Check pip3 ───────────────────────────────────────────────────────────────
echo "[2/6] Checking pip3..."
if ! /usr/bin/python3 -m pip --version &>/dev/null; then
    echo ""
    echo "WARNING: pip3 is not available. Attempting to install..."
    /usr/bin/python3 -m ensurepip --user 2>/dev/null || true
    if ! /usr/bin/python3 -m pip --version &>/dev/null; then
        echo ""
        echo "ERROR: Could not set up pip3."
        echo "Try running: /usr/bin/python3 -m ensurepip --user"
        echo ""
        echo "Press Enter to exit..."
        read
        exit 1
    fi
fi
echo "  pip3 is available."

# ── Copy files ───────────────────────────────────────────────────────────────
echo "[3/6] Installing files to:"
echo "  $INSTALL_DIR"
if [ -d "$INSTALL_DIR" ]; then
    echo "  Existing installation found. Updating..."
    rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
cp -R "$PAYLOAD_DIR/" "$INSTALL_DIR/"
echo "  Files copied."

# ── Set permissions ──────────────────────────────────────────────────────────
echo "[4/6] Setting permissions..."
chmod +x "$INSTALL_DIR/bin/ffmpeg"

# Remove macOS quarantine attribute (critical for ffmpeg from DMG)
xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
echo "  Done."

# ── Install Python dependencies ─────────────────────────────────────────────
echo "[5/6] Installing Python dependencies..."
/usr/bin/python3 -m pip install --user -r "$INSTALL_DIR/requirements.txt" 2>&1 | tail -5
echo "  Dependencies installed."

# ── CEP Extension Setup ─────────────────────────────────────────────────────
echo "[6/6] Setting up Premiere Pro extension..."

# Create extensions directory
mkdir -p "$CEP_DIR"

# Remove existing symlink or directory
if [ -L "$TARGET_LINK" ]; then
    rm "$TARGET_LINK"
elif [ -d "$TARGET_LINK" ]; then
    echo "  Backing up existing extension..."
    mv "$TARGET_LINK" "${TARGET_LINK}.bak.$(date +%s)"
fi

# Create symlink: CEP extensions dir -> installed cep/ folder
ln -s "$INSTALL_DIR/cep" "$TARGET_LINK"
echo "  Linked extension to: $TARGET_LINK"

# Enable CEP debug mode for CSXS 9-12 (required for unsigned extensions)
for V in 9 10 11 12; do
    defaults write com.adobe.CSXS.${V} PlayerDebugMode 1 2>/dev/null || true
done
echo "  CEP debug mode enabled (CSXS 9-12)."

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "   Installation Complete!"
echo "=========================================="
echo ""
echo "  Next steps:"
echo "    1. Restart Premiere Pro (if it's running)"
echo "    2. Go to: Window > Extensions > YT Downloader"
echo "    3. Click 'Start the App' inside the panel"
echo ""
echo "  Supports: Premiere Pro 2020 and newer"
echo ""
echo "Press Enter to close this window..."
read
