#!/bin/bash
# Cut a Whitespace release: build the signed DMG at a given version, then
# (re)generate the EdDSA-signed Sparkle appcast pointing at the GitHub Release
# asset. Publishing the GitHub Release + pushing appcast.xml is left to you.
#
#   WS_VERSION=0.2 WS_BUILD=2 ./make_release.sh
#
set -e
cd "$(dirname "$0")"

: "${WS_VERSION:?set WS_VERSION, e.g. WS_VERSION=0.2}"
: "${WS_BUILD:?set WS_BUILD (integer, must increase each release), e.g. WS_BUILD=2}"
TAG="v${WS_VERSION}"
REPO="zpphxd/whitespace"
ASSET="Whitespace-${WS_VERSION}.dmg"

# 1. Build the Developer ID-signed DMG at this version.
export WS_VERSION WS_BUILD
./make_dmg.sh

# 2. Stage it for appcast generation (Sparkle reads every DMG in ./releases).
mkdir -p releases
cp Whitespace.dmg "releases/${ASSET}"

# 3. Notarize + staple, so downloads don't hit the Gatekeeper "could not verify"
#    wall. Uses a notarytool keychain profile — create it ONCE with:
#      xcrun notarytool store-credentials whitespace-notary \
#        --apple-id <your-apple-id> --team-id 3Q5YCK6M5B --password <app-specific-pw>
#    (app-specific password: appleid.apple.com → Sign-In & Security)
#    Must happen BEFORE the appcast step: stapling changes the DMG bytes.
PROFILE="${NOTARY_PROFILE:-whitespace-notary}"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "Notarizing ${ASSET} (takes a few minutes)…"
    xcrun notarytool submit "releases/${ASSET}" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "releases/${ASSET}"
    echo "✓ notarized + stapled"
else
    echo "⚠️  SKIPPING NOTARIZATION — no '$PROFILE' keychain profile found."
    echo "   Downloads of this DMG will hit Gatekeeper's 'could not verify' dialog."
    echo "   Set it up once:  xcrun notarytool store-credentials $PROFILE \\"
    echo "     --apple-id <your-apple-id> --team-id 3Q5YCK6M5B --password <app-specific-pw>"
fi

# 4. Generate/refresh the appcast (versions, sizes, download URLs), then attach
#    each enclosure's EdDSA signature via sign_update. (generate_appcast's own
#    signing can be blocked by the Keychain ACL; sign_update is reliable.)
BIN=".build/artifacts/sparkle/Sparkle/bin"
"$BIN/generate_appcast" --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" releases
for dmg in releases/*.dmg; do
    base="$(basename "$dmg")"
    sig="$("$BIN/sign_update" "$dmg" | sed -E 's/.*edSignature="([^"]+)".*/\1/')"
    [ -n "$sig" ] && python3 - "$base" "$sig" <<'PY'
import re, sys
name, sig = sys.argv[1], sys.argv[2]
p = "releases/appcast.xml"; x = open(p).read()
# Add/refresh sparkle:edSignature on the enclosure whose URL ends with this dmg.
def fix(m):
    tag = m.group(0)
    if name not in tag: return tag
    tag = re.sub(r'\s*sparkle:edSignature="[^"]*"', '', tag)
    return tag.replace(' type=', f' sparkle:edSignature="{sig}" type=')
open(p, "w").write(re.sub(r'<enclosure[^>]*/>', fix, x))
PY
done
cp releases/appcast.xml appcast.xml

echo
echo "✓ release staged: releases/${ASSET} + appcast.xml"
echo "Publish it (both steps required for users to auto-update):"
echo "  1. gh release create ${TAG} releases/${ASSET} --repo ${REPO} --title \"Whitespace ${WS_VERSION}\" --notes \"…\""
echo "  2. git add appcast.xml && git commit -m \"release ${TAG}\" && git push"
