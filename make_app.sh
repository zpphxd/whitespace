#!/bin/bash
# Build Whitespace.app — a double-clickable, Dock-less menu-bar app bundle.
set -e
cd "$(dirname "$0")"

echo "Building release binary (clean, to avoid stale incremental builds)…"
# Remove the actual product dir, not just the .build/release symlink.
rm -rf .build/*/release .build/release
swift build -c release

APP="Whitespace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Whitespace "$APP/Contents/MacOS/Whitespace"

# Bundle Sparkle (auto-updates). Ship the universal framework and make sure the
# executable can find it at @executable_path/../Frameworks.
FWSRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$FWSRC" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$FWSRC" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Whitespace" 2>/dev/null || true
fi

# Bundled resources (hand-drawn Excalifont for exact Excalidraw text metrics).
[ -f Resources/Excalifont.ttf ] && cp Resources/Excalifont.ttf "$APP/Contents/Resources/"

# App icon: generate AppIcon.icns from AppIcon.png (all required sizes).
ICON_PLIST=""
if [ -f AppIcon.png ]; then
    ICONSET="AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
        d=$((s * 2))
        sips -z $d $d AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
    ICON_PLIST="    <key>CFBundleIconFile</key>        <string>AppIcon</string>"
fi

# Version + build number. Bump WS_BUILD on every release so Sparkle can tell a
# newer build apart (it compares CFBundleVersion).
WS_VERSION="${WS_VERSION:-0.1}"
WS_BUILD="${WS_BUILD:-1}"
# Auto-update feed + Sparkle public key (private key lives in the login Keychain).
SU_FEED="${SU_FEED:-https://raw.githubusercontent.com/zpphxd/whitespace/main/appcast.xml}"
SU_PUBKEY="NoBaHIsyf2s3IFodl6O06TMR5uyyuR6qQo3KutcVFyA="

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Whitespace</string>
    <key>CFBundleDisplayName</key>     <string>Whitespace</string>
    <key>CFBundleIdentifier</key>      <string>com.zachpowers.whitespace</string>
    <key>CFBundleVersion</key>         <string>${WS_BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${WS_VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Whitespace</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>SUFeedURL</key>               <string>${SU_FEED}</string>
    <key>SUPublicEDKey</key>          <string>${SU_PUBKEY}</string>
    <key>SUEnableAutomaticChecks</key> <true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
${ICON_PLIST}
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS will run it locally without Gatekeeper friction.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
