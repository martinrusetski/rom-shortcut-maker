#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$SCRIPT_DIR/SteamShortcutConverter"
APP_NAME="Rom Shortcut Maker"
BINARY_NAME="RomShortcutMaker"
BUNDLE_ID="com.romshortcutmaker.app"
INSTALL_APP="/Applications/$APP_NAME.app"
VERSION="${1:-0.0.0-dev}"

# SwiftPM and the app-bundle packaging steps require a full Xcode installation.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    DEVELOPER_DIR="$(xcode-select -p)"
fi
export DEVELOPER_DIR

case "$DEVELOPER_DIR" in
    */CommandLineTools)
        echo "Error: Command Line Tools are selected instead of Xcode." >&2
        echo "Run: sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer" >&2
        exit 1
        ;;
esac

if ! xcrun --find actool >/dev/null 2>&1; then
    echo "Error: Xcode tools are not available through DEVELOPER_DIR=$DEVELOPER_DIR" >&2
    exit 1
fi

case "$(uname -m)" in
    arm64|x86_64) ARCH="$(uname -m)" ;;
    *)
        echo "Error: Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

TEMP_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rom-shortcut-maker-install.XXXXXX")"
trap 'rm -rf "$TEMP_BUILD_DIR"' EXIT
APP="$TEMP_BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME for $ARCH..."
(cd "$PKG_DIR" && swift build -c release --arch "$ARCH")
BIN_DIR="$(cd "$PKG_DIR" && swift build -c release --arch "$ARCH" --show-bin-path)"
BINARY="$BIN_DIR/$BINARY_NAME"

if [ ! -x "$BINARY" ]; then
    echo "Error: SwiftPM did not produce $BINARY" >&2
    exit 1
fi

echo "Creating app bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$BINARY_NAME"

APP_RESOURCE_BUNDLE="$BIN_DIR/SteamShortcutConverter_SteamShortcutConverter.bundle"
if [ ! -d "$APP_RESOURCE_BUNDLE" ]; then
    echo "Error: App resource bundle was not found at $APP_RESOURCE_BUNDLE" >&2
    exit 1
fi
for RESOURCE_BUNDLE in "$BIN_DIR"/*.bundle; do
    [ -d "$RESOURCE_BUNDLE" ] || continue
    ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
done

if [ ! -f "$APP/Contents/Resources/SteamShortcutConverter_SteamShortcutConverter.bundle/Contents/Resources/emulators.json" ]; then
    echo "Error: Packaged app is missing emulators.json" >&2
    exit 1
fi

SPARKLE_PUB_KEY="$(tr -d '[:space:]' < "$SCRIPT_DIR/sparkle_public_key.txt" 2>/dev/null || true)"
SPARKLE_FEED_URL="https://raw.githubusercontent.com/martinrusetski/rom-shortcut-maker/main/appcast.xml"
ASSETS="$PKG_DIR/SteamShortcutConverter/Assets.xcassets"
APP_ICON="$PKG_DIR/SteamShortcutConverter/AppIcon.icon"

if [ ! -d "$APP_ICON" ]; then
    echo "Error: Icon Composer document was not found at $APP_ICON" >&2
    exit 1
fi

echo "Compiling app icon..."
xcrun actool "$ASSETS" "$APP_ICON" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /dev/null >/dev/null
ICON_PLIST_ENTRIES="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION#v}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUB_KEY}</string>
${ICON_PLIST_ENTRIES}
</dict>
</plist>
PLIST

echo "Embedding Sparkle.framework..."
"$SCRIPT_DIR/embed-sparkle.sh" "$APP"

echo "Ad-hoc signing..."
codesign --sign - --force --options runtime \
    --entitlements "$SCRIPT_DIR/RomShortcutMaker.entitlements" \
    "$APP"
codesign --verify --verbose "$APP"

echo "Installing to $INSTALL_APP..."
rm -rf "$INSTALL_APP"
ditto "$APP" "$INSTALL_APP"

echo "Launching $INSTALL_APP..."
open "$INSTALL_APP"

echo "Installation complete."
