#!/bin/bash
# Quick launch script for SteamShortcutConverter with console logging

# Kill any running instances
echo "Killing any running instances..."
killall SteamShortcutConverter 2>/dev/null

echo "Building SteamShortcutConverter..."
cd SteamShortcutConverter
xcodebuild -scheme SteamShortcutConverter -configuration Debug clean build > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Build successful! Launching app..."
    echo ""
    echo "==================================================================="
    echo "IMPORTANT: To see debug logs, open a NEW terminal and run:"
    echo "  log stream --predicate 'process == \"SteamShortcutConverter\"' --level debug"
    echo "==================================================================="
    echo ""
    echo "Press Enter to launch the app..."
    read
    
    open ~/Library/Developer/Xcode/DerivedData/SteamShortcutConverter-*/Build/Products/Debug/SteamShortcutConverter.app
else
    echo "Build failed. Check errors above."
    exit 1
fi
