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

# Clean bundle before signing (THIS FIXES THE ERROR)
echo "🧹 Cleaning bundle metadata..."
# Remove all extended attributes
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
# Remove .DS_Store files
find "$APP_BUNDLE" -name ".DS_Store" -delete 2>/dev/null || true
# Remove AppleDouble files (._*)
find "$APP_BUNDLE" -name "._*" -delete 2>/dev/null || true
# Use dot_clean to remove resource forks and Finder metadata (macOS specific)
if command -v dot_clean &> /dev/null; then
    dot_clean -m "$APP_BUNDLE" 2>/dev/null || true
fi

# Add Ad-Hoc Code Signature (CRITICAL FOR RUNNING)
echo "🔏 Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Build complete!"
echo "📂 App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
