#!/bin/bash
set -e

APP_NAME="JoyaFix"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

# Entitlements file for Hardened Runtime
ENTITLEMENTS_FILE="Sources/JoyaFix/Resources/JoyaFix.entitlements"

# Apple Developer Team ID
TEAM_ID="8CAY5RT71J"

# =========================================
# Configuration for Notarization
# =========================================
# Set these environment variables before running:
#   APPLE_ID - Your Apple ID email
#   APPLE_TEAM_ID - Your Team ID from Apple Developer
#   APPLE_APP_PASSWORD - App-specific password from appleid.apple.com
#   SIGNING_IDENTITY - Developer ID Application certificate name
#
# Example:
#   export APPLE_ID="your@email.com"
#   export APPLE_TEAM_ID="XXXXXXXXXX"
#   export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export SIGNING_IDENTITY="Developer ID Application: Your Name (XXXXXXXXXX)"
# =========================================

# Check for notarization mode
NOTARIZE=false
if [ "$1" == "--notarize" ] || [ "$1" == "-n" ]; then
    NOTARIZE=true
    echo "📜 Notarization mode enabled"
    
    # Verify required environment variables
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_APP_PASSWORD" ] || [ -z "$SIGNING_IDENTITY" ]; then
        echo "❌ Missing required environment variables for notarization:"
        echo "   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD, SIGNING_IDENTITY"
        echo ""
        echo "   Set them before running:"
        echo "   export APPLE_ID='your@email.com'"
        echo "   export APPLE_TEAM_ID='XXXXXXXXXX'"
        echo "   export APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
        echo "   export SIGNING_IDENTITY='Developer ID Application: Name (ID)'"
        exit 1
    fi
fi

# זיהוי ארכיטקטורה אוטומטי (יזהה Intel במקרה שלך)
ARCH=$(uname -m)
echo "🔨 Building $APP_NAME for architecture: $ARCH..."

# הרצת בדיקות
swift test

# ניקוי בנייה קודמת
rm -rf "$BUILD_DIR"

# בנייה (Swift PM יבחר אוטומטית את הארכיטקטורה הנכונה למחשב שלך)
swift build -c release --arch "$ARCH"

# מציאת הבינארי שנבנה (לא dSYM)
SPM_BINARY=$(find .build -name "$APP_NAME" -type f -perm +111 | grep "release" | grep -v dSYM | head -n 1)

if [ ! -f "$SPM_BINARY" ]; then
    echo "❌ Binary not found!"
    exit 1
fi

# וידוא שזה באמת בינארי הרצה (לא dSYM)
if ! file "$SPM_BINARY" | grep -q "executable"; then
    echo "❌ Found file is not an executable binary!"
    exit 1
fi

# יצירת מבנה האפליקציה
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# העתקת הבינארי
cp "$SPM_BINARY" "$MACOS_DIR/$APP_NAME"
# הוספת הרשאות הרצה (חיוני להפעלת האפליקציה)
chmod +x "$MACOS_DIR/$APP_NAME"

# העתקת משאבים (לוגו, סאונד, תרגום, אייקון)
# מעתיק גם מהתיקייה החדשה וגם מהישנה ליתר ביטחון
[ -f "Sources/JoyaFix/Resources/JoyaFix.icns" ] && cp "Sources/JoyaFix/Resources/JoyaFix.icns" "$RESOURCES_DIR/"
[ -f "Sources/JoyaFix/Resources/FLATLOGO.png" ] && cp "Sources/JoyaFix/Resources/FLATLOGO.png" "$RESOURCES_DIR/"
[ -f "FLATLOGO.png" ] && cp "FLATLOGO.png" "$RESOURCES_DIR/"
[ -f "Sources/JoyaFix/Resources/success.wav" ] && cp "Sources/JoyaFix/Resources/success.wav" "$RESOURCES_DIR/"
[ -f "success.wav" ] && cp "success.wav" "$RESOURCES_DIR/"
[ -d "Sources/JoyaFix/Resources/he.lproj" ] && cp -R "Sources/JoyaFix/Resources/he.lproj" "$RESOURCES_DIR/"
[ -d "he.lproj" ] && cp -R "he.lproj" "$RESOURCES_DIR/"
[ -d "Sources/JoyaFix/Resources/en.lproj" ] && cp -R "Sources/JoyaFix/Resources/en.lproj" "$RESOURCES_DIR/"
[ -d "en.lproj" ] && cp -R "en.lproj" "$RESOURCES_DIR/"

# העתקת Info.plist
if [ -f "Sources/JoyaFix/Resources/Info.plist" ]; then
    cp "Sources/JoyaFix/Resources/Info.plist" "$CONTENTS_DIR/"
elif [ -f "Info.plist" ]; then
    cp "Info.plist" "$CONTENTS_DIR/"
fi

# העתקת Frameworks (כמו Sparkle ו-Pulse)
find .build -name "*.framework" -type d | grep "release" | while read fw; do
    cp -R "$fw" "$FRAMEWORKS_DIR/"
done

# תיקון נתיבי RPATH
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

# יצירת PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# --- שלב החתימה הקריטי ---
echo "🔏 Signing process..."

# Verify Bundle ID is correct before signing
if [ -f "$CONTENTS_DIR/Info.plist" ]; then
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$CONTENTS_DIR/Info.plist" 2>/dev/null || echo "")
    if [ "$BUNDLE_ID" != "com.joyafix.app" ]; then
        echo "⚠️  Fixing Bundle ID from '$BUNDLE_ID' to 'com.joyafix.app'..."
        /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier com.joyafix.app" "$CONTENTS_DIR/Info.plist"
        echo "✓ Bundle ID fixed"
    else
        echo "✓ Bundle ID verified: com.joyafix.app"
    fi
fi

# ניקוי אגרסיבי של metadata לפני חתימה
xattr -cr "$APP_BUNDLE"

# Copy entitlements file to bundle
if [ -f "$ENTITLEMENTS_FILE" ]; then
    cp "$ENTITLEMENTS_FILE" "$RESOURCES_DIR/"
    echo "✓ Entitlements file copied"
fi

if [ "$NOTARIZE" = true ]; then
    # =========================================
    # Production Signing with Hardened Runtime
    # =========================================
    # IMPORTANT: The --options runtime flag enables Hardened Runtime,
    # which is REQUIRED for notarization by Apple.
    #
    # Required entitlements for JoyaFix (in JoyaFix.entitlements):
    # - com.apple.security.cs.allow-jit (Required for llama.cpp / Local LLM)
    # - com.apple.security.cs.disable-library-validation (Required for loading local models)
    # - com.apple.security.cs.allow-unsigned-executable-memory (Required for Metal compute)
    # =========================================
    echo "🔐 Signing with Developer ID for notarization..."
    echo "   Using Hardened Runtime (--options runtime)"
    echo "   Entitlements: $ENTITLEMENTS_FILE"
    
    # Verify entitlements file exists
    if [ ! -f "$ENTITLEMENTS_FILE" ]; then
        echo "❌ Entitlements file not found: $ENTITLEMENTS_FILE"
        exit 1
    fi
    
    # Sign Frameworks first (inside-out signing)
    if [ -d "$FRAMEWORKS_DIR" ]; then
        echo "   Signing frameworks..."
        find "$FRAMEWORKS_DIR" -name "*.framework" -depth | while read fw; do
            xattr -cr "$fw"
            codesign --force --options runtime --timestamp \
                --entitlements "$ENTITLEMENTS_FILE" \
                --sign "$SIGNING_IDENTITY" "$fw"
            echo "   ✓ Signed: $(basename "$fw")"
        done
        
        # Sign dylibs
        find "$FRAMEWORKS_DIR" -name "*.dylib" | while read dylib; do
            xattr -cr "$dylib"
            codesign --force --options runtime --timestamp \
                --sign "$SIGNING_IDENTITY" "$dylib"
            echo "   ✓ Signed: $(basename "$dylib")"
        done
    fi
    
    # Sign the main executable
    echo "   Signing main executable..."
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS_FILE" \
        --sign "$SIGNING_IDENTITY" "$MACOS_DIR/$APP_NAME"
    
    # Sign the entire app bundle
    echo "   Signing app bundle..."
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS_FILE" \
        --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    
    # Verify code signature
    echo "🔍 Verifying code signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    spctl --assess --type execute --verbose "$APP_BUNDLE" || echo "⚠️  Gatekeeper check will pass after notarization"
    
    # =========================================
    # Create ZIP for notarization
    # =========================================
    echo "📦 Creating ZIP for notarization..."
    ZIP_FILE="$BUILD_DIR/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"
    echo "✓ Created: $ZIP_FILE"
    
    # =========================================
    # Submit for notarization
    # =========================================
    echo "📤 Submitting to Apple for notarization..."
    echo "   This may take several minutes..."
    
    xcrun notarytool submit "$ZIP_FILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait \
        --timeout 30m
    
    NOTARIZATION_RESULT=$?
    
    if [ $NOTARIZATION_RESULT -eq 0 ]; then
        echo "✅ Notarization successful!"
        
        # Staple the notarization ticket to the app
        echo "📎 Stapling notarization ticket..."
        xcrun stapler staple "$APP_BUNDLE"
        
        # Verify stapling
        xcrun stapler validate "$APP_BUNDLE"
        echo "✓ Notarization ticket stapled"
        
        # Create final distributable ZIP
        echo "📦 Creating distributable ZIP..."
        DIST_ZIP="$BUILD_DIR/${APP_NAME}-${ARCH}-notarized.zip"
        rm -f "$ZIP_FILE"
        ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"
        echo "✅ Distributable created: $DIST_ZIP"
        
        # Create DMG for distribution (optional)
        echo "💿 Creating DMG..."
        DMG_FILE="$BUILD_DIR/${APP_NAME}-${ARCH}.dmg"
        hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_FILE"
        
        # Notarize DMG
        xcrun notarytool submit "$DMG_FILE" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --wait
        
        xcrun stapler staple "$DMG_FILE"
        echo "✅ DMG created and notarized: $DMG_FILE"
    else
        echo "❌ Notarization failed! Check the log above for details."
        echo "   You can check status with: xcrun notarytool history --apple-id $APPLE_ID --team-id $APPLE_TEAM_ID"
        exit 1
    fi
else
    # =========================================
    # Development Signing (with Team ID)
    # =========================================
    echo "🔧 Development signing with Team ID: $TEAM_ID..."
    
    # Try to find an "Apple Development" certificate for this Team ID
    # For free accounts, the certificate name format is: "Apple Development: Name (TEAM_ID)"
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "$TEAM_ID" | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
    
    if [ -z "$SIGNING_IDENTITY" ]; then
        echo "⚠️  No 'Apple Development' certificate found for Team ID $TEAM_ID"
        echo "   Falling back to ad-hoc signing..."
        SIGNING_IDENTITY="-"
    else
        echo "✓ Found signing identity: $SIGNING_IDENTITY"
    fi
    
    # Clean metadata recursively before signing (critical for macOS builds)
    xattr -cr "$APP_BUNDLE"
    
    # Sign Frameworks first (inside-out signing)
    if [ -d "$FRAMEWORKS_DIR" ]; then
        echo "   Signing frameworks..."
        find "$FRAMEWORKS_DIR" -name "*.framework" -depth | while read fw; do
            xattr -cr "$fw"
            codesign --force --sign "$SIGNING_IDENTITY" "$fw"
            echo "   ✓ Signed: $(basename "$fw")"
        done
        
        # Sign dylibs
        find "$FRAMEWORKS_DIR" -name "*.dylib" | while read dylib; do
            xattr -cr "$dylib"
            codesign --force --sign "$SIGNING_IDENTITY" "$dylib"
            echo "   ✓ Signed: $(basename "$dylib")"
        done
    fi
    
    # Sign the main executable
    echo "   Signing main executable..."
    codesign --force --sign "$SIGNING_IDENTITY" "$MACOS_DIR/$APP_NAME"
    
    # Sign the entire app bundle
    echo "   Signing app bundle..."
    codesign --force --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    
    echo "✓ Development signing complete"
fi

# Verify signing
codesign -dv "$APP_BUNDLE" 2>&1 | grep -q "com.joyafix.app" && echo "✓ App signed with correct Bundle ID" || echo "⚠️  Warning: Bundle ID verification failed"

echo ""
echo "==========================================="
echo "✅ Build Complete for $ARCH!"
echo "==========================================="
echo "   App: $APP_BUNDLE"
if [ "$NOTARIZE" = true ]; then
    echo "   Mode: Production (Notarized)"
    echo "   ZIP: $BUILD_DIR/${APP_NAME}-${ARCH}-notarized.zip"
    echo "   DMG: $BUILD_DIR/${APP_NAME}-${ARCH}.dmg"
else
    echo "   Mode: Development (ad-hoc signed)"
    echo ""
    echo "   For production build with notarization, run:"
    echo "   ./build.sh --notarize"
fi
echo "==========================================="