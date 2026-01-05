#!/bin/bash

# Quick Run Script - Builds and launches JoyaFix

echo "🚀 Building and launching JoyaFix..."

# Build the app
./build.sh

# Launch the app
if [ -d "build/JoyaFix.app" ]; then
    echo ""
    echo "▶️  Launching JoyaFix..."
    open build/JoyaFix.app
else
    echo "❌ Build failed - app not found"
    exit 1
fi
