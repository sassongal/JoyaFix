#!/bin/bash
# Development run script - creates app bundle for swift run compatibility

set -e

APP_NAME="JoyaFix"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "🔨 Building for development..."

# Build with Swift PM
swift build

# Find the binary - try multiple locations
SPM_BINARY=""
if [ -f "$BUILD_DIR/$APP_NAME" ]; then
    SPM_BINARY="$BUILD_DIR/$APP_NAME"
elif [ -f ".build/x86_64-apple-macosx/debug/$APP_NAME" ]; then
    SPM_BINARY=".build/x86_64-apple-macosx/debug/$APP_NAME"
elif [ -f ".build/arm64-apple-macosx/debug/$APP_NAME" ]; then
    SPM_BINARY=".build/arm64-apple-macosx/debug/$APP_NAME"
else
    # Try to find it
    SPM_BINARY=$(find .build -name "$APP_NAME" -type f -perm +111 2>/dev/null | grep -E "(debug|release)" | head -n 1)
fi

if [ -z "$SPM_BINARY" ] || [ ! -f "$SPM_BINARY" ]; then
    echo "❌ Binary not found! Searched in:"
    echo "   - $BUILD_DIR/$APP_NAME"
    echo "   - .build/x86_64-apple-macosx/debug/$APP_NAME"
    echo "   - .build/arm64-apple-macosx/debug/$APP_NAME"
    echo "   - Any .build/*/debug or release directory"
    exit 1
fi

echo "✓ Found binary at: $SPM_BINARY"

# Create app bundle structure (if not exists)
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# Copy binary
cp "$SPM_BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy Info.plist (critical for permissions)
if [ -f "Sources/JoyaFix/Resources/Info.plist" ]; then
    cp "Sources/JoyaFix/Resources/Info.plist" "$CONTENTS_DIR/"
    echo "✓ Info.plist copied"
fi

# Copy resources
[ -f "Sources/JoyaFix/Resources/FLATLOGO.png" ] && cp "Sources/JoyaFix/Resources/FLATLOGO.png" "$RESOURCES_DIR/" && echo "✓ FLATLOGO.png copied"
[ -f "Sources/JoyaFix/Resources/success.wav" ] && cp "Sources/JoyaFix/Resources/success.wav" "$RESOURCES_DIR/" && echo "✓ success.wav copied"
[ -f "Sources/JoyaFix/Resources/JoyaFix.icns" ] && cp "Sources/JoyaFix/Resources/JoyaFix.icns" "$RESOURCES_DIR/" && echo "✓ JoyaFix.icns copied"
[ -d "Sources/JoyaFix/Resources/he.lproj" ] && cp -R "Sources/JoyaFix/Resources/he.lproj" "$RESOURCES_DIR/" 2>/dev/null && echo "✓ Hebrew localization copied" || true
[ -d "Sources/JoyaFix/Resources/en.lproj" ] && cp -R "Sources/JoyaFix/Resources/en.lproj" "$RESOURCES_DIR/" 2>/dev/null && echo "✓ English localization copied" || true

# Copy Frameworks (like Sparkle)
find .build -name "*.framework" -type d | grep "debug" | while read fw; do
    cp -R "$fw" "$FRAMEWORKS_DIR/"
    echo "✓ Copied framework: $(basename "$fw")"
done

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Fix RPATH to point to Frameworks directory
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

# Verify Bundle ID is correct
if [ -f "$CONTENTS_DIR/Info.plist" ]; then
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$CONTENTS_DIR/Info.plist" 2>/dev/null || echo "")
    if [ "$BUNDLE_ID" != "com.joyafix.app" ]; then
        echo "⚠️  Fixing Bundle ID..."
        /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier com.joyafix.app" "$CONTENTS_DIR/Info.plist"
        echo "✓ Bundle ID fixed"
    fi
fi

# Sign the app (critical for permissions)
echo "🔏 Signing app..."

# Sign Frameworks separately first
if [ -d "$FRAMEWORKS_DIR" ] && [ "$(ls -A "$FRAMEWORKS_DIR" 2>/dev/null)" ]; then
    echo "🔏 Signing frameworks..."
    find "$FRAMEWORKS_DIR" -name "*.framework" -depth -exec xattr -cr {} \; 2>/dev/null || true
    find "$FRAMEWORKS_DIR" -name "*.framework" -depth -exec codesign --force --deep --sign - {} \; 2>/dev/null || {
        echo "⚠️  Framework signing failed, but continuing..."
    }
fi

# Clean metadata and sign main app
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "⚠️  Code signing failed, but continuing..."
}

echo "✅ Development build complete!"
echo "▶️  Launching $APP_NAME..."
open "$APP_BUNDLE"
