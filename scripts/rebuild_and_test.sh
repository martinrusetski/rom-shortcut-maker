#!/bin/bash

echo "==================================================================="
echo "Aggressive rebuild and test script"
echo "==================================================================="

# Kill any running instances
echo "1. Killing any running instances..."
killall SteamShortcutConverter 2>/dev/null
sleep 1

# Clean derived data
echo "2. Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/SteamShortcutConverter-*

# Clean build folder
echo "3. Cleaning build folder..."
cd SteamShortcutConverter
xcodebuild -project SteamShortcutConverter.xcodeproj -scheme SteamShortcutConverter -configuration Debug clean > /dev/null 2>&1

# Build fresh
echo "4. Building fresh..."
xcodebuild -project SteamShortcutConverter.xcodeproj -scheme SteamShortcutConverter -configuration Debug build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Find the app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SteamShortcutConverter.app" -type d 2>/dev/null | grep "Debug" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Could not find built app!"
    exit 1
fi

echo ""
echo "5. App built at: $APP_PATH"
echo ""
echo "6. Starting log stream..."
echo "   (You should see 'MainViewModel:' and 'ShortcutFilter:' messages)"
echo ""

# Start log stream and launch app
log stream --predicate 'process == "SteamShortcutConverter"' --style compact 2>&1 | grep -E "(MainViewModel|ShortcutFilter|ERROR)" &
LOG_PID=$!

sleep 2

echo "7. Launching app..."
open "$APP_PATH"

echo ""
echo "==================================================================="
echo "Watch for debug messages above. Press Ctrl+C to stop."
echo "==================================================================="

# Wait for Ctrl+C
trap "kill $LOG_PID 2>/dev/null; exit" INT TERM
wait $LOG_PID
