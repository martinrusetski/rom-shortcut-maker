#!/bin/bash

set -e  # Exit on error

echo "🔨 Building SteamShortcutConverter for installation..."
echo ""

# Change to project directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_ROOT/SteamShortcutConverter"

# Build Release version with explicit derivedDataPath
BUILD_DIR="$PROJECT_ROOT/build"
xcodebuild -project SteamShortcutConverter.xcodeproj \
           -scheme SteamShortcutConverter \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           clean build

echo ""
echo "✅ Build successful!"
echo ""

# The app should be in the build directory
APP_PATH="$BUILD_DIR/Build/Products/Release/SteamShortcutConverter.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Could not find built app at: $APP_PATH"
    echo ""
    echo "Searching for app in DerivedData..."
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SteamShortcutConverter.app" -type d 2>/dev/null | grep "Release" | head -1)
    
    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find built app!"
        exit 1
    fi
    echo "Found app at: $APP_PATH"
fi

echo "📦 Installing to /Applications..."

# Remove old version if it exists
if [ -d "/Applications/SteamShortcutConverter.app" ]; then
    echo "Removing old version..."
    rm -rf "/Applications/SteamShortcutConverter.app"
fi

# Copy to Applications
cp -R "$APP_PATH" /Applications/

echo ""
echo "✅ Installation complete!"
echo ""
echo "SteamShortcutConverter is now installed in /Applications"
echo "You can launch it from:"
echo "  • Spotlight (⌘+Space, then type 'SteamShortcutConverter')"
echo "  • Finder → Applications"
echo "  • Launchpad"
echo ""
