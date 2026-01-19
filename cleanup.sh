#!/bin/bash
# סקריפט למחיקת כל ההתקנות והבניות הקודמות של JoyaFix

set -e

APP_NAME="JoyaFix"
APP_BUNDLE="$APP_NAME.app"
BUNDLE_ID="com.joyafix.app"

echo "🧹 ניקוי כל ההתקנות והבניות של $APP_NAME..."
echo ""

# Step 1: עצירת כל התהליכים הרצים
echo "1️⃣  עצירת כל התהליכים הרצים..."
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 2
echo "   ✓ תהליכים נעצרו"
echo ""

# Step 2: מחיקת התקנות מהמחשב
echo "2️⃣  מחיקת התקנות מהמחשב..."

# ~/Applications
if [ -d "$HOME/Applications/$APP_BUNDLE" ]; then
    echo "   - מוחק: $HOME/Applications/$APP_BUNDLE"
    rm -rf "$HOME/Applications/$APP_BUNDLE"
    echo "   ✓ נמחק"
fi

# /Applications
if [ -d "/Applications/$APP_BUNDLE" ]; then
    echo "   - מוחק: /Applications/$APP_BUNDLE"
    sudo rm -rf "/Applications/$APP_BUNDLE" 2>/dev/null || rm -rf "/Applications/$APP_BUNDLE"
    echo "   ✓ נמחק"
fi

# Desktop (אם יש)
if [ -d "$HOME/Desktop/$APP_BUNDLE" ]; then
    echo "   - מוחק: $HOME/Desktop/$APP_BUNDLE"
    rm -rf "$HOME/Desktop/$APP_BUNDLE"
    echo "   ✓ נמחק"
fi

# Downloads (אם יש)
if [ -d "$HOME/Downloads/$APP_BUNDLE" ]; then
    echo "   - מוחק: $HOME/Downloads/$APP_BUNDLE"
    rm -rf "$HOME/Downloads/$APP_BUNDLE"
    echo "   ✓ נמחק"
fi

echo "   ✓ כל ההתקנות נמחקו"
echo ""

# Step 3: מחיקת בניות
echo "3️⃣  מחיקת בניות..."

# build/
if [ -d "build" ]; then
    echo "   - מוחק: build/"
    rm -rf "build"
    echo "   ✓ נמחק"
fi

# .build/
if [ -d ".build" ]; then
    echo "   - מוחק: .build/"
    rm -rf ".build"
    echo "   ✓ נמחק"
fi

# JoyaFix.app בפרויקט (אם יש)
if [ -d "$APP_BUNDLE" ]; then
    echo "   - מוחק: $APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
    echo "   ✓ נמחק"
fi

echo "   ✓ כל הבניות נמחקו"
echo ""

# Step 4: מחיקת LaunchAgents/LaunchDaemons (אם יש)
echo "4️⃣  בדיקת LaunchAgents/LaunchDaemons..."

# LaunchAgents
if [ -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist" ]; then
    echo "   - מוחק LaunchAgent: $HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    echo "   ✓ נמחק"
fi

# LaunchDaemons (דורש sudo)
if [ -f "/Library/LaunchDaemons/$BUNDLE_ID.plist" ]; then
    echo "   - מוחק LaunchDaemon: /Library/LaunchDaemons/$BUNDLE_ID.plist"
    sudo rm -f "/Library/LaunchDaemons/$BUNDLE_ID.plist" 2>/dev/null || true
    echo "   ✓ נמחק"
fi

echo "   ✓ LaunchAgents/Daemons נבדקו"
echo ""

# Step 5: מחיקת קובצי Preferences (אופציונלי - מוער)
echo "5️⃣  מחיקת קובצי Preferences..."
echo "   ⚠️  דילוג על מחיקת Preferences (שומרים את ההגדרות)"
echo "   (אם תרצה למחוק גם Preferences, הסר את ההערה בשורות הבאות)"
# rm -rf "$HOME/Library/Preferences/$BUNDLE_ID.plist" 2>/dev/null || true
# rm -rf "$HOME/Library/Containers/$BUNDLE_ID" 2>/dev/null || true
# rm -rf "$HOME/Library/Application Support/$APP_NAME" 2>/dev/null || true
echo ""

# Step 6: ניקוי Launch Services (אופציונלי)
echo "6️⃣  ניקוי Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true
echo "   ✓ Launch Services נוקה"
echo ""

echo "✅ ניקוי הושלם בהצלחה!"
echo ""
echo "📋 סיכום:"
echo "   ✓ כל התהליכים נעצרו"
echo "   ✓ כל ההתקנות נמחקו"
echo "   ✓ כל הבניות נמחקו"
echo "   ✓ LaunchAgents/Daemons נבדקו"
echo ""
echo "💡 כדי לבנות ולהריץ מחדש, השתמש ב:"
echo "   ./dev-run.sh  - להרצה מהירה (debug)"
echo "   ./run.sh      - להרצה עם build מלא (release)"
echo "   ./build.sh    - לבנייה בלבד"
