#!/bin/bash

# Migration script to restructure JoyaFix for Swift Package Manager
# This script moves all Swift source files to Sources/JoyaFix and resources to the appropriate location

set -e  # Exit on error

echo "🔄 Migrating JoyaFix project structure for SPM..."

# Create directory structure
mkdir -p Sources/JoyaFix
mkdir -p Tests/JoyaFixTests
mkdir -p Sources/JoyaFix/Resources

# Move all Swift files to Sources/JoyaFix
echo "📦 Moving Swift source files..."
mv *.swift Sources/JoyaFix/ 2>/dev/null || true

# Move resources
echo "📁 Moving resources..."
if [ -f "FLATLOGO.png" ]; then
    cp FLATLOGO.png Sources/JoyaFix/Resources/
fi

if [ -f "success.wav" ]; then
    cp success.wav Sources/JoyaFix/Resources/
fi

# Copy localization files
if [ -d "he.lproj" ]; then
    mkdir -p Sources/JoyaFix/Resources/he.lproj
    cp he.lproj/Localizable.strings Sources/JoyaFix/Resources/he.lproj/
fi

if [ -d "en.lproj" ]; then
    mkdir -p Sources/JoyaFix/Resources/en.lproj
    cp en.lproj/Localizable.strings Sources/JoyaFix/Resources/en.lproj/
fi

# Copy Info.plist to Resources (needed for app bundle)
if [ -f "Info.plist" ]; then
    cp Info.plist Sources/JoyaFix/Resources/
fi

echo "✅ Migration complete!"
echo ""
echo "📂 New structure:"
echo "   Sources/JoyaFix/     - All Swift source files"
echo "   Sources/JoyaFix/Resources/ - Resources (images, sounds, localization)"
echo "   Tests/JoyaFixTests/  - Test files"
echo ""
echo "⚠️  Note: Original files are still in the root directory."
echo "   You can remove them after verifying the build works."

