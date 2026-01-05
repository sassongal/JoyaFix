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
cp "$SPM_BINARY" "$MACOS_DIR/$APP_NAME"

# Copy frameworks (Sparkle, Pulse, etc.)
echo "🔗 Copying frameworks..."
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# Find and copy Sparkle framework
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d -path "*/release/*" | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "  📦 Copying Sparkle.framework..."
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
    # Fix framework permissions
    chmod -R u+w "$FRAMEWORKS_DIR/Sparkle.framework"
fi

# Find and copy Pulse framework if it exists
PULSE_FRAMEWORK=$(find .build -name "Pulse.framework" -type d -path "*/release/*" | head -1)
if [ -n "$PULSE_FRAMEWORK" ] && [ -d "$PULSE_FRAMEWORK" ]; then
    echo "  📦 Copying Pulse.framework..."
    cp -R "$PULSE_FRAMEWORK" "$FRAMEWORKS_DIR/"
    chmod -R u+w "$FRAMEWORKS_DIR/Pulse.framework"
fi

# Update binary's rpath to find frameworks
if [ -d "$FRAMEWORKS_DIR" ] && [ "$(ls -A $FRAMEWORKS_DIR)" ]; then
    echo "  🔧 Updating binary rpath..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

# Copy Info.plist
echo "📋 Copying Info.plist..."
if [ -f "Info.plist" ]; then
    cp Info.plist "$CONTENTS_DIR/"
elif [ -f "Sources/JoyaFix/Resources/Info.plist" ]; then
    cp Sources/JoyaFix/Resources/Info.plist "$CONTENTS_DIR/"
else
    echo "⚠️  Warning: Info.plist not found"
fi

# Copy resources from SPM Resources directory or root
echo "📁 Copying resources..."
if [ -d "Sources/JoyaFix/Resources" ]; then
    # Copy from SPM Resources directory
    if [ -f "Sources/JoyaFix/Resources/success.wav" ]; then
        echo "🔊 Copying sound resources..."
        cp Sources/JoyaFix/Resources/success.wav "$RESOURCES_DIR/"
    fi
    
    if [ -f "Sources/JoyaFix/Resources/FLATLOGO.png" ]; then
        echo "🖼️ Copying logo..."
        cp Sources/JoyaFix/Resources/FLATLOGO.png "$RESOURCES_DIR/"
    fi
    
    # Copy localization
    if [ -d "Sources/JoyaFix/Resources/he.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/he.lproj"
        cp Sources/JoyaFix/Resources/he.lproj/Localizable.strings "$RESOURCES_DIR/he.lproj/"
    fi
    
    if [ -d "Sources/JoyaFix/Resources/en.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/en.lproj"
        cp Sources/JoyaFix/Resources/en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
    fi
else
    # Fallback: Copy from root directory (for backward compatibility)
    if [ -f "success.wav" ]; then
        echo "🔊 Copying sound resources..."
        cp success.wav "$RESOURCES_DIR/"
    fi
    
    if [ -f "FLATLOGO.png" ]; then
        echo "🖼️ Copying logo..."
        cp FLATLOGO.png "$RESOURCES_DIR/"
    fi
    
    if [ -d "he.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/he.lproj"
        cp he.lproj/Localizable.strings "$RESOURCES_DIR/he.lproj/"
    fi
    
    if [ -d "en.lproj" ]; then
        mkdir -p "$RESOURCES_DIR/en.lproj"
        cp en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
    fi
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
