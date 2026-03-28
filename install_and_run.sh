#!/bin/bash
set -e

# Path for temporary build artifacts
TEMP_BUILD_DIR="/tmp/rom-shortcut-maker-build"
mkdir -p "$TEMP_BUILD_DIR"

# Clean and Build
echo "🧹 Building SteamShortcutConverter in temporary directory..."
XCEnableCompilationCache=NO xcodebuild -project SteamShortcutConverter/SteamShortcutConverter.xcodeproj \
           -scheme SteamShortcutConverter \
           -configuration Release \
           -derivedDataPath "$TEMP_BUILD_DIR" \
           COMPILATION_CACHE_ENABLE=NO \
           COMPILER_INDEX_STORE_ENABLE=NO \
           DEBUG_INFORMATION_FORMAT=dwarf \
           build > /dev/null

# Install to Applications folder
echo "📦 Overwriting current installation in /Applications..."
rm -rf /Applications/SteamShortcutConverter.app
cp -R "$TEMP_BUILD_DIR/Build/Products/Release/SteamShortcutConverter.app" /Applications/

# Launch from Applications folder
echo "🚀 Launching from /Applications/SteamShortcutConverter.app..."
open /Applications/SteamShortcutConverter.app

# Cleanup (removes the 27GB residue immediately)
echo "🧹 Cleaning up temporary build artifacts..."
rm -rf "$TEMP_BUILD_DIR"
rm -rf build
