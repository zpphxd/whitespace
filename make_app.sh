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

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Whitespace</string>
    <key>CFBundleDisplayName</key>     <string>Whitespace</string>
    <key>CFBundleIdentifier</key>      <string>com.zachpowers.whitespace</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Whitespace</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS will run it locally without Gatekeeper friction.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
