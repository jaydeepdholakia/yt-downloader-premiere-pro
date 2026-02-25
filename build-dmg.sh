#!/bin/bash
#
# build-dmg.sh — Build the YT Downloader macOS DMG installer
#
# Usage: ./build-dmg.sh [path-to-icon.png]
#
# Requires: sips, iconutil, hdiutil (all built into macOS)
#

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_NAME="YT-Downloader-Installer"
APP_NAME="Install YT Downloader"
UNINSTALL_NAME="Uninstall YT Downloader"
VOLUME_NAME="YT Downloader"

# Icon source — argument or default
ICON_SRC="${1:-$PROJECT_DIR/assets/icon.png}"

echo ""
echo "=========================================="
echo "   YT Downloader DMG Builder"
echo "=========================================="
echo ""

# ── Validate prerequisites ───────────────────────────────────────────────────
if [ ! -f "$ICON_SRC" ]; then
    echo "ERROR: Icon not found at $ICON_SRC"
    echo ""
    echo "Usage: ./build-dmg.sh [path-to-icon.png]"
    echo "The icon should be at least 1024x1024 PNG."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/main.py" ]; then
    echo "ERROR: main.py not found. Run this script from the project root."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/bin/ffmpeg" ]; then
    echo "ERROR: bin/ffmpeg not found."
    exit 1
fi

# ── Clean previous build ────────────────────────────────────────────────────
echo "[1/7] Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
echo "  Done."

# ── Generate .icns from PNG ──────────────────────────────────────────────────
echo "[2/7] Generating app icon (.icns)..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

for SIZE in 16 32 128 256 512; do
    sips -z $SIZE $SIZE "$ICON_SRC" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null 2>&1
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE "$ICON_SRC" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null 2>&1
done

iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"
echo "  Created AppIcon.icns"

# ── Build installer .app bundle ──────────────────────────────────────────────
echo "[3/7] Building installer .app bundle..."
APP_DIR="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/payload"

# Copy Info.plist
cp "$PROJECT_DIR/installer/Info.plist" "$APP_DIR/Contents/"

# Copy icon
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"

# Copy installer script
cp "$PROJECT_DIR/installer/install.sh" "$APP_DIR/Contents/MacOS/install"
chmod +x "$APP_DIR/Contents/MacOS/install"

# Copy payload (the project files that get installed)
echo "  Copying payload files..."
cp "$PROJECT_DIR/main.py"          "$APP_DIR/Contents/Resources/payload/"
cp "$PROJECT_DIR/requirements.txt" "$APP_DIR/Contents/Resources/payload/"

mkdir -p "$APP_DIR/Contents/Resources/payload/bin"
cp "$PROJECT_DIR/bin/ffmpeg"       "$APP_DIR/Contents/Resources/payload/bin/"

mkdir -p "$APP_DIR/Contents/Resources/payload/static"
cp "$PROJECT_DIR/static/index.html" "$APP_DIR/Contents/Resources/payload/static/"

# Copy entire cep/ directory
cp -R "$PROJECT_DIR/cep" "$APP_DIR/Contents/Resources/payload/cep"

# Clean up unwanted files from payload
find "$APP_DIR/Contents/Resources/payload" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_DIR/Contents/Resources/payload" -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

echo "  Built: $APP_NAME.app"

# ── Build uninstaller .app bundle ────────────────────────────────────────────
echo "[4/7] Building uninstaller .app bundle..."
UNINSTALL_APP_DIR="$BUILD_DIR/$UNINSTALL_NAME.app"
mkdir -p "$UNINSTALL_APP_DIR/Contents/MacOS"
mkdir -p "$UNINSTALL_APP_DIR/Contents/Resources"

# Create a minimal Info.plist for uninstaller
cat > "$UNINSTALL_APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>uninstall</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.ytdownloader.uninstaller</string>
    <key>CFBundleName</key>
    <string>Uninstall YT Downloader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>
PLIST

# Copy icon
cp "$BUILD_DIR/AppIcon.icns" "$UNINSTALL_APP_DIR/Contents/Resources/"

# Create uninstaller executable (wraps the .command script)
cat > "$UNINSTALL_APP_DIR/Contents/MacOS/uninstall" <<'WRAPPER'
#!/bin/bash
# If not running inside a terminal, relaunch inside Terminal.app
if [ ! -t 1 ]; then
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    open -a Terminal.app "$SCRIPT_PATH"
    exit 0
fi
WRAPPER
cat "$PROJECT_DIR/installer/uninstall.command" >> "$UNINSTALL_APP_DIR/Contents/MacOS/uninstall"
chmod +x "$UNINSTALL_APP_DIR/Contents/MacOS/uninstall"

echo "  Built: $UNINSTALL_NAME.app"

# ── Create DMG ───────────────────────────────────────────────────────────────
echo "[5/7] Creating DMG..."
STAGING_DIR="$BUILD_DIR/dmg-staging"
mkdir -p "$STAGING_DIR"

# Move the .app bundles into staging
cp -R "$APP_DIR" "$STAGING_DIR/"
cp -R "$UNINSTALL_APP_DIR" "$STAGING_DIR/"

# Create a read-write DMG first
TEMP_DMG="$BUILD_DIR/temp.dmg"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    "$TEMP_DMG" >/dev/null 2>&1

echo "  Temporary DMG created."

# ── Set volume icon and layout ───────────────────────────────────────────────
echo "[6/7] Setting volume icon and layout..."
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# Unmount if already mounted
if [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
    sleep 1
fi

hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse >/dev/null 2>&1

# Copy icon to volume root
cp "$BUILD_DIR/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"

# Set custom icon flag on volume
SetFile -a C "$MOUNT_POINT" 2>/dev/null || true

# Use AppleScript to arrange the DMG window layout
osascript <<APPLESCRIPT 2>/dev/null || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 900, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set position of item "$APP_NAME.app" of container window to {120, 120}
        set position of item "$UNINSTALL_NAME.app" of container window to {380, 120}
        close
    end tell
end tell
APPLESCRIPT

sleep 2

hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1
echo "  Done."

# ── Convert to compressed read-only DMG ──────────────────────────────────────
echo "[7/7] Compressing final DMG..."
FINAL_DMG="$BUILD_DIR/$DMG_NAME.dmg"
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG" >/dev/null 2>&1

# Clean up
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"
rm -f "$BUILD_DIR/AppIcon.icns"

FINAL_SIZE=$(du -h "$FINAL_DMG" | cut -f1)

echo ""
echo "=========================================="
echo "   BUILD COMPLETE"
echo "=========================================="
echo ""
echo "  Output: $FINAL_DMG"
echo "  Size:   $FINAL_SIZE"
echo ""
echo "  To test: open \"$FINAL_DMG\""
echo ""
