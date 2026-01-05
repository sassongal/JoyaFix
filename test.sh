#!/bin/bash

# Test script - Builds and runs JoyaFix with console output

echo "🔨 Building JoyaFix..."
./build.sh

if [ ! -d "build/JoyaFix.app" ]; then
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "🚀 Launching JoyaFix..."
echo "📋 Console output will appear below:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Kill any existing instance
killall JoyaFix 2>/dev/null

# Run the app and show output
build/JoyaFix.app/Contents/MacOS/JoyaFix
