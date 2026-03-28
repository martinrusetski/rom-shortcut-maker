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

# Launch
echo "🚀 Copying and launching SteamShortcutConverter..."
SOURCE_APP_PATH="$TEMP_BUILD_DIR/Build/Products/Release/SteamShortcutConverter.app"
LOCAL_APP_PATH="./SteamShortcutConverter.app"

if [ -d "$SOURCE_APP_PATH" ]; then
    rm -rf "$LOCAL_APP_PATH"
    cp -R "$SOURCE_APP_PATH" "$LOCAL_APP_PATH"
    open "$LOCAL_APP_PATH"
else
    echo "❌ Error: Could not find the built app at $SOURCE_APP_PATH"
    exit 1
fi

# Cleanup (removes the 27GB residue immediately)
echo "🧹 Cleaning up temporary build artifacts..."
rm -rf "$TEMP_BUILD_DIR"
