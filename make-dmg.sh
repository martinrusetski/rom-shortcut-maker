#!/bin/bash
# Builds "Rom Shortcut Maker.app" from the SwiftPM package and wraps it in a
# distributable DMG — the same steps CI runs, for local testing of a release.
set -e

APP_NAME="Rom Shortcut Maker"
BINARY_NAME="RomShortcutMaker"
BUNDLE_ID="com.romshortcutmaker.app"
VOL_NAME="Rom Shortcut Maker"
DMG_FINAL="${BINARY_NAME}.dmg"
STAGING="dmg_staging"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/RomShortcutMaker"
SPARKLE_PUB_KEY="$(tr -d '[:space:]' < "${SCRIPT_DIR}/sparkle_public_key.txt" 2>/dev/null || true)"
SPARKLE_FEED_URL="https://raw.githubusercontent.com/martinrusetski/rom-shortcut-maker/main/appcast.xml"
VERSION="${1:-0.0.0-dev}"

echo "Building..."
( cd "$PKG_DIR" && swift build -c release --arch arm64 )
BIN_DIR="$(cd "$PKG_DIR" && swift build -c release --arch arm64 --show-bin-path)"

echo "Creating app bundle..."
rm -rf "${SCRIPT_DIR}/${APP_NAME}.app"
APP="${SCRIPT_DIR}/${APP_NAME}.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

BINARY="$BIN_DIR/$BINARY_NAME"
cp "$BINARY" "$APP/Contents/MacOS/${BINARY_NAME}"

# The app loads emulators.json via Bundle.module, which resolves the SwiftPM
# resource bundle relative to Bundle.main.resourceURL (Contents/Resources).
APP_RESOURCE_BUNDLE="$BIN_DIR/RomShortcutMaker_RomShortcutMaker.bundle"
if [ ! -d "$APP_RESOURCE_BUNDLE" ]; then
    echo "Error: App resource bundle was not found at $APP_RESOURCE_BUNDLE" >&2
    exit 1
fi
for RESOURCE_BUNDLE in "$BIN_DIR"/*.bundle; do
    [ -d "$RESOURCE_BUNDLE" ] || continue
    ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
done

if [ ! -f "$APP/Contents/Resources/RomShortcutMaker_RomShortcutMaker.bundle/Contents/Resources/emulators.json" ]; then
    echo "Error: Packaged app is missing emulators.json" >&2
    exit 1
fi

ASSETS="${PKG_DIR}/RomShortcutMaker/Assets.xcassets"
APP_ICON="${PKG_DIR}/RomShortcutMaker/AppIcon.icon"
if [ ! -d "$APP_ICON" ]; then
    echo "Error: Icon Composer document was not found at $APP_ICON" >&2
    exit 1
fi

echo "Compiling asset catalog and app icon..."
xcrun actool "$ASSETS" "$APP_ICON" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /dev/null > /dev/null
ICON_PLIST_ENTRIES="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>"

cat > "$APP/Contents/Info.plist" << PLIST
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

echo "Embedding Sparkle framework..."
"${SCRIPT_DIR}/embed-sparkle.sh" "$APP"

echo "Ad-hoc signing..."
codesign --sign - --force --options runtime \
    --entitlements "${SCRIPT_DIR}/RomShortcutMaker.entitlements" \
    "$APP"
codesign --verify --verbose "$APP"

echo "Assembling DMG staging..."
rm -rf "${SCRIPT_DIR}/${STAGING}"
mkdir -p "${SCRIPT_DIR}/${STAGING}"
cp -R "$APP" "${SCRIPT_DIR}/${STAGING}/"
ln -s /Applications "${SCRIPT_DIR}/${STAGING}/Applications"

cat > "${SCRIPT_DIR}/${STAGING}/README.txt" << 'TXTEOF'
Rom Shortcut Maker — Installation

1. Drag Rom Shortcut Maker.app onto the Applications folder.

2. Since this app is not notarized, macOS will block it on first launch.
   To allow it, open Terminal and run:

     xattr -cr "/Applications/Rom Shortcut Maker.app"

   Then double-click the app to launch it.
   (Or use System Settings → Privacy & Security → Open Anyway.)

3. Future updates install automatically from within the app —
   you won't need to re-download this installer or repeat step 2.
TXTEOF

echo "Creating DMG..."
rm -f "${SCRIPT_DIR}/${DMG_FINAL}"
hdiutil create -srcfolder "${SCRIPT_DIR}/${STAGING}" -volname "${VOL_NAME}" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
    -format UDZO -imagekey zlib-level=9 \
    -ov "${SCRIPT_DIR}/${DMG_FINAL}"

rm -rf "${SCRIPT_DIR}/${STAGING}"

echo "Done → ${DMG_FINAL}"
echo "Open with: open \"${SCRIPT_DIR}/${DMG_FINAL}\""
