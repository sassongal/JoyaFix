#!/bin/bash

# JoyaFix Build Script
# This script uses Swift Package Manager to build the app and create a proper macOS app bundle

set -e  # Exit on error

APP_NAME="JoyaFix"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SPM_BUILD_DIR=".build/release"
SPM_BINARY="$SPM_BUILD_DIR/$APP_NAME"

echo "🔨 Building $APP_NAME with Swift Package Manager..."

# Run tests first
echo "🧪 Running tests..."
swift test
if [ $? -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "❌ Tests failed. Aborting build."
    exit 1
fi

# Clean previous build
rm -rf "$BUILD_DIR"

# Build with SPM
echo "📦 Building with Swift Package Manager..."
swift build -c release

# Verify binary exists
if [ ! -f "$SPM_BINARY" ]; then
    echo "❌ Build failed: Binary not found at $SPM_BINARY"
    exit 1
fi

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary from SPM build
echo "📦 Copying binary..."
cp -X "$SPM_BINARY" "$MACOS_DIR/$APP_NAME"

# Copy frameworks (Sparkle, Pulse, etc.)
echo "🔗 Copying frameworks..."
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# Find and copy Sparkle framework
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d -path "*/release/*" | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "  📦 Copying Sparkle.framework..."
    cp -RX "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
fi

# Find and copy Pulse framework if it exists
PULSE_FRAMEWORK=$(find .build -name "Pulse.framework" -type d -path "*/release/*" | head -1)
if [ -n "$PULSE_FRAMEWORK" ] && [ -d "$PULSE_FRAMEWORK" ]; then
    echo "  📦 Copying Pulse.framework..."
    cp -RX "$PULSE_FRAMEWORK" "$FRAMEWORKS_DIR/"
fi

# Update binary's rpath to find frameworks
if [ -d "$FRAMEWORKS_DIR" ] && [ "$(ls -A $FRAMEWORKS_DIR)" ]; then
    echo "  🔧 Updating binary rpath..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

# Copy Info.plist
echo "📋 Copying Info.plist..."
if [ -f "Info.plist" ]; then
    cp -X Info.plist "$CONTENTS_DIR/"
elif [ -f "Sources/JoyaFix/Resources/Info.plist" ]; then
    cp -X Sources/JoyaFix/Resources/Info.plist "$CONTENTS_DIR/"
else
    echo "⚠️  Warning: Info.plist not found"
fi

# Copy resources from SPM Resources directory or root
echo "📁 Copying resources..."
if [ -d "Sources/JoyaFix/Resources" ]; then
    # Copy from SPM Resources directory
    if [ -f "Sources/JoyaFix/Resources/success.wav" ]; then
        echo "🔊 Copying sound resources..."
        cp -X Sources/JoyaFix/Resources/success.wav "$RESOURCES_DIR/"
    fi
    
    if [ -f "Sources/JoyaFix/Resources/FLATLOGO.png" ]; then
        echo "🖼️ Copying logo..."
        cp -X Sources/JoyaFix/Resources/FLATLOGO.png "$RESOURCES_DIR/"
    fi
    
    # Copy localization
    if [ -d "Sources/JoyaFix/Resources/he.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/he.lproj"
        cp -X Sources/JoyaFix/Resources/he.lproj/Localizable.strings "$RESOURCES_DIR/he.lproj/"
    fi
    
    if [ -d "Sources/JoyaFix/Resources/en.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/en.lproj"
        cp -X Sources/JoyaFix/Resources/en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
    fi
else
    # Fallback: Copy from root directory (for backward compatibility)
    if [ -f "success.wav" ]; then
        echo "🔊 Copying sound resources..."
        cp -X success.wav "$RESOURCES_DIR/"
    fi
    
    if [ -f "FLATLOGO.png" ]; then
        echo "🖼️ Copying logo..."
        cp -X FLATLOGO.png "$RESOURCES_DIR/"
    fi
    
    if [ -d "he.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/he.lproj"
        cp -X he.lproj/Localizable.strings "$RESOURCES_DIR/he.lproj/"
    fi
    
    if [ -d "en.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/en.lproj"
        cp -X en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
    fi
fi

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# ---------------------------------------------------------
# SIGNING SECTION (Replace from here to end of file)
# ---------------------------------------------------------

echo "🧹 Preparing for signing..."
# Ensure we have write permissions to clean files
chmod -R u+w "$APP_BUNDLE"

# 1. Clean and Sign Frameworks First (Inside-Out)
if [ -d "$FRAMEWORKS_DIR" ]; then
    echo "🔗 Signing frameworks..."
    find "$FRAMEWORKS_DIR" -name "*.framework" -depth | while read framework; do
        # Clean specific framework before signing
        xattr -cr "$framework"
        # Sign with --deep for the framework itself to handle its internal versioning
        codesign --force --deep --sign - "$framework"
    done
fi

# 2. Clean Main App Bundle
echo "🧹 Final cleanup of app bundle..."
# Delete metadata files
find "$APP_BUNDLE" -name ".DS_Store" -delete
find "$APP_BUNDLE" -name "._*" -delete
# Strip attributes from the entire bundle one last time
xattr -cr "$APP_BUNDLE"

# 3. Sign Main App Bundle (WITHOUT --deep)
echo "🔏 Signing app bundle..."
# Note: We do NOT use --deep here because we manually signed frameworks above.
# Using --deep on the main bundle often causes the "detritus" error.
codesign --force --sign - "$APP_BUNDLE"

# Verify signature
echo "🔍 Verifying signature..."
if codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"; then
    echo "✅ Build complete and signed!"
    echo "📂 App bundle created at: $APP_BUNDLE"
    echo ""
    echo "To run the app:"
    echo "  open $APP_BUNDLE"
else
    echo "❌ Signature verification failed."
    exit 1
fi
