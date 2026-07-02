#!/bin/bash
# Build a distributable, Developer ID-signed Whitespace.dmg with a hand-drawn
# drag-to-Applications installer window.
set -e
cd "$(dirname "$0")"

APP="Whitespace.app"
DMG="Whitespace.dmg"
VOL="Whitespace"
# Code-signing identity — override with your own cert to build a distributable
# DMG (e.g. DEVID="Developer ID Application: Your Name (TEAMID)" ./make_dmg.sh).
DEVID="${DEVID:-Developer ID Application: ZACHARY PHILIP POWERS (3Q5YCK6M5B)}"

# 1. Build the app bundle (release).
./make_app.sh

# 2. Render the hand-drawn installer background via the app's own renderer
#    (multi-resolution TIFF: correct point sizing + crisp on Retina).
.build/release/Whitespace --render-dmg-bg dmg-background.tiff

# 3. Developer ID sign with a hardened runtime (required for notarization and
#    for Sparkle updates to pass Gatekeeper). Sign nested code first, then the app.
find "$APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" -o -name "*.xpc" \) 2>/dev/null | while read -r f; do
    codesign --force --options runtime --timestamp --sign "$DEVID" "$f" || true
done
codesign --force --deep --options runtime --timestamp --sign "$DEVID" "$APP"
codesign --verify --deep --strict "$APP" && echo "✓ app signed with Developer ID"

# 4. Stage the app alone, then build the DMG with the installer layout.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
rm -f "$DMG"
create-dmg \
    --volname "$VOL" \
    --window-pos 200 120 \
    --window-size 640 420 \
    --icon-size 128 \
    --background dmg-background.tiff \
    --icon "Whitespace.app" 170 210 \
    --app-drop-link 470 210 \
    --hide-extension "Whitespace.app" \
    --no-internet-enable \
    "$DMG" "$STAGE" || true          # create-dmg exits non-zero if it can't set the
                                     # Finder view via automation; the DMG is still valid.
rm -rf "$STAGE"

# 5. Sign the DMG itself.
codesign --force --sign "$DEVID" "$DMG"
echo "✓ built $DMG"
echo "  To distribute cleanly (no Gatekeeper warning), notarize:"
echo "    xcrun notarytool submit $DMG --apple-id <id> --team-id 3Q5YCK6M5B --password <app-pw> --wait"
echo "    xcrun stapler staple $DMG"
