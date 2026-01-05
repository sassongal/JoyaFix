#!/bin/bash

# JoyaFix Build Script
# This script compiles the app and creates a proper macOS app bundle

set -e  # Exit on error

APP_NAME="JoyaFix"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile Swift files
echo "📦 Compiling Swift sources..."
swiftc -framework Cocoa -framework Carbon -framework ApplicationServices \
    *.swift \
    -o "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
echo "📋 Copying Info.plist..."
cp Info.plist "$CONTENTS_DIR/"

# Copy sound files if they exist
if [ -f "success.wav" ]; then
    echo "🔊 Copying sound resources..."
    cp success.wav "$RESOURCES_DIR/"
fi

# Copy Logo
if [ -f "FLATLOGO.png" ]; then
    echo "🖼️ Copying logo..."
    cp FLATLOGO.png "$RESOURCES_DIR/"
fi

# Copy Localization
echo "🌍 Copying localization files..."
if [ -d "he.lproj" ]; then
    mkdir -p "$RESOURCES_DIR/he.lproj"
    cp he.lproj/Localizable.strings "$RESOURCES_DIR/he.lproj/"
fi

if [ -d "en.lproj" ]; then
    mkdir -p "$RESOURCES_DIR/en.lproj"
    cp en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
fi

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✅ Build complete!"
echo "📂 App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install to Applications:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Creating DMG for Distribution (optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To create a DMG installer, install create-dmg first:"
echo "  brew install create-dmg"
echo ""
echo "Then run:"
echo "  create-dmg --volname \"JoyaFix Installer\" \\"
echo "             --volicon \"FLATLOGO.png\" \\"
echo "             --window-pos 200 120 \\"
echo "             --window-size 800 400 \\"
echo "             --icon-size 100 \\"
echo "             --app-drop-link 600 185 \\"
echo "             \"JoyaFix.dmg\" \\"
echo "             \"$APP_BUNDLE\""
echo ""
echo "This will create a DMG file ready for distribution."
