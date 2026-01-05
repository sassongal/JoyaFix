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
