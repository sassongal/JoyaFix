#!/bin/bash
set -e

APP_NAME="JoyaFix"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

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

# ניקוי אגרסיבי של metadata לפני חתימה
xattr -cr "$APP_BUNDLE"

# חתימת Frameworks בנפרד
if [ -d "$FRAMEWORKS_DIR" ]; then
    find "$FRAMEWORKS_DIR" -name "*.framework" -depth -exec xattr -cr {} \;
    find "$FRAMEWORKS_DIR" -name "*.framework" -depth -exec codesign --force --deep --sign - {} \;
fi

# חתימת האפליקציה הראשית (בלי --deep כדי למנוע שגיאות כפולות)
codesign --force --sign - "$APP_BUNDLE"

echo "✅ Build Complete for $ARCH!"