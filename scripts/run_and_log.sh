#!/bin/bash

# Find and run the app, capturing stdout/stderr

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SteamShortcutConverter.app" -type d 2>/dev/null | grep "Debug" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "App not found! Run ./launch.sh first to build it."
    exit 1
fi

echo "Running: $APP_PATH"
echo "=========================================="
echo ""

# Run the app directly (not via 'open') to capture output
"$APP_PATH/Contents/MacOS/SteamShortcutConverter"
