#!/bin/bash

# Launch SteamShortcutConverter and capture console output

APP_PATH="SteamShortcutConverter/.build/Release/SteamShortcutConverter.app"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "App not found at $APP_PATH"
    echo "Looking for app in Xcode build directory..."
    APP_PATH=$(find SteamShortcutConverter -name "SteamShortcutConverter.app" -type d | grep -v "Intermediates" | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "Could not find SteamShortcutConverter.app"
        exit 1
    fi
    echo "Found app at: $APP_PATH"
fi

echo "Launching app and capturing console output..."
echo "Press Ctrl+C to stop"
echo "=========================================="

# Start log streaming in background
log stream --predicate 'process == "SteamShortcutConverter"' --level debug &
LOG_PID=$!

# Give log stream a moment to start
sleep 1

# Launch the app
open "$APP_PATH"

# Wait for user to press Ctrl+C
trap "kill $LOG_PID 2>/dev/null; exit" INT TERM

# Keep script running
wait $LOG_PID
