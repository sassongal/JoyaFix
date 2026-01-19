#!/bin/bash
# Script to fix permissions issues by ensuring consistent Bundle ID and proper signing

set -e

APP_NAME="JoyaFix"
BUNDLE_ID="com.joyafix.app"

echo "🔧 Fixing JoyaFix Permissions..."
echo ""

# Step 1: Kill all running instances
echo "1️⃣  Closing all running instances..."
pkill -f JoyaFix 2>/dev/null || true
sleep 1

# Step 2: Remove old permission entries (they might be pointing to wrong bundle)
echo "2️⃣  Cleaning old permission entries..."
# Note: We can't directly remove TCC entries, but we can ensure the app is properly signed

# Step 3: Check and fix Bundle ID in all builds
echo "3️⃣  Verifying Bundle ID consistency..."

# Fix build/JoyaFix.app
if [ -d "build/JoyaFix.app" ]; then
    echo "   - Checking build/JoyaFix.app..."
    if [ -f "build/JoyaFix.app/Contents/Info.plist" ]; then
        CURRENT_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" build/JoyaFix.app/Contents/Info.plist 2>/dev/null || echo "")
        if [ "$CURRENT_ID" != "$BUNDLE_ID" ]; then
            echo "     ⚠️  Wrong Bundle ID: $CURRENT_ID (should be $BUNDLE_ID)"
            /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $BUNDLE_ID" build/JoyaFix.app/Contents/Info.plist
            echo "     ✓ Fixed Bundle ID"
        else
            echo "     ✓ Bundle ID correct: $BUNDLE_ID"
        fi
    fi
fi

# Fix dev build
if [ -d ".build/debug/JoyaFix.app" ]; then
    echo "   - Checking .build/debug/JoyaFix.app..."
    if [ -f ".build/debug/JoyaFix.app/Contents/Info.plist" ]; then
        CURRENT_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" .build/debug/JoyaFix.app/Contents/Info.plist 2>/dev/null || echo "")
        if [ "$CURRENT_ID" != "$BUNDLE_ID" ]; then
            echo "     ⚠️  Wrong Bundle ID: $CURRENT_ID (should be $BUNDLE_ID)"
            /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $BUNDLE_ID" .build/debug/JoyaFix.app/Contents/Info.plist
            echo "     ✓ Fixed Bundle ID"
        else
            echo "     ✓ Bundle ID correct: $BUNDLE_ID"
        fi
    fi
fi

# Step 4: Re-sign the apps (critical for permissions)
echo "4️⃣  Re-signing applications..."

if [ -d "build/JoyaFix.app" ]; then
    echo "   - Signing build/JoyaFix.app..."
    xattr -cr build/JoyaFix.app 2>/dev/null || true
    codesign --force --deep --sign - build/JoyaFix.app 2>/dev/null || codesign --force --sign - build/JoyaFix.app
    echo "     ✓ Signed"
fi

if [ -d ".build/debug/JoyaFix.app" ]; then
    echo "   - Signing .build/debug/JoyaFix.app..."
    xattr -cr .build/debug/JoyaFix.app 2>/dev/null || true
    codesign --force --deep --sign - .build/debug/JoyaFix.app 2>/dev/null || codesign --force --sign - .build/debug/JoyaFix.app
    echo "     ✓ Signed"
fi

echo ""
echo "✅ Permissions fix complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Run the app: ./run.sh or ./dev-run.sh"
echo "   2. When prompted, grant Accessibility permission"
echo "   3. If permission was already granted, you may need to:"
echo "      - Remove JoyaFix from System Settings → Privacy & Security → Accessibility"
echo "      - Re-run the app and grant permission again"
echo ""
echo "💡 Tip: The Bundle ID must match exactly: $BUNDLE_ID"
