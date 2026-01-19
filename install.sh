#!/bin/bash
# Installation script for JoyaFix
# Removes old version and installs new one

set -e

APP_NAME="JoyaFix"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR="build"
INSTALL_DIR="$HOME/Applications"
SOURCE_APP="$BUILD_DIR/$APP_BUNDLE"

echo "🔧 JoyaFix Installation Script"
echo ""

# Step 1: Close all running instances
echo "1️⃣  Closing all running instances..."
pkill -f JoyaFix 2>/dev/null || true
sleep 2

# Step 2: Remove old installation
echo "2️⃣  Removing old installation..."
if [ -d "$INSTALL_DIR/$APP_BUNDLE" ]; then
    echo "   - Found existing installation at $INSTALL_DIR/$APP_BUNDLE"
    rm -rf "$INSTALL_DIR/$APP_BUNDLE"
    echo "   ✓ Removed old installation"
else
    echo "   - No existing installation found"
fi

# Also check /Applications
if [ -d "/Applications/$APP_BUNDLE" ]; then
    echo "   - Found existing installation at /Applications/$APP_BUNDLE"
    sudo rm -rf "/Applications/$APP_BUNDLE" 2>/dev/null || rm -rf "/Applications/$APP_BUNDLE"
    echo "   ✓ Removed old installation from /Applications"
fi

# Step 3: Build the app
echo "3️⃣  Building the application..."
if [ ! -f "./build.sh" ]; then
    echo "❌ build.sh not found!"
    exit 1
fi

./build.sh

# Step 4: Verify build
if [ ! -d "$SOURCE_APP" ]; then
    echo "❌ Build failed - $SOURCE_APP not found!"
    exit 1
fi

echo "   ✓ Build successful"

# Step 5: Create Applications directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo "4️⃣  Creating Applications directory..."
    mkdir -p "$INSTALL_DIR"
    echo "   ✓ Created $INSTALL_DIR"
else
    echo "4️⃣  Applications directory exists"
fi

# Step 6: Copy app to Applications
echo "5️⃣  Installing to $INSTALL_DIR..."
cp -R "$SOURCE_APP" "$INSTALL_DIR/"
echo "   ✓ Installed to $INSTALL_DIR/$APP_BUNDLE"

# Step 7: Verify Bundle ID and sign
echo "6️⃣  Verifying and signing installation..."
if [ -f "$INSTALL_DIR/$APP_BUNDLE/Contents/Info.plist" ]; then
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$INSTALL_DIR/$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "")
    if [ "$BUNDLE_ID" != "com.joyafix.app" ]; then
        echo "   ⚠️  Fixing Bundle ID..."
        /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier com.joyafix.app" "$INSTALL_DIR/$APP_BUNDLE/Contents/Info.plist"
        echo "   ✓ Bundle ID fixed"
    else
        echo "   ✓ Bundle ID verified: com.joyafix.app"
    fi
fi

# Sign the installed app
xattr -cr "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || {
    echo "   ⚠️  Code signing failed, but continuing..."
}

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Installed location: $INSTALL_DIR/$APP_BUNDLE"
echo ""
echo "▶️  Launching JoyaFix..."
open "$INSTALL_DIR/$APP_BUNDLE"

echo ""
echo "💡 Note: You may need to grant Accessibility permission in:"
echo "   System Settings → Privacy & Security → Accessibility"
echo ""
