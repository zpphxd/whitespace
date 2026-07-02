# Releasing Whitespace

Whitespace ships as a Developer ID–signed `.dmg` with a drag-to-Applications
installer, and updates itself in the background via [Sparkle](https://sparkle-project.org).

## One-time setup (already done)

- **Signing** — the app is signed with `Developer ID Application: ZACHARY PHILIP
  POWERS (3Q5YCK6M5B)` and a hardened runtime (`make_dmg.sh`).
- **Sparkle keys** — an EdDSA key pair lives in the login Keychain. The public
  key is baked into `Info.plist` (`SUPublicEDKey`), set by `make_app.sh`.
- **Update feed** — `SUFeedURL` points at
  `https://raw.githubusercontent.com/zpphxd/whitespace/main/appcast.xml`, so the
  committed `appcast.xml` in this repo *is* the live feed.

## Cutting a release

Bump the build number every time (Sparkle compares `CFBundleVersion`):

```sh
WS_VERSION=0.2 WS_BUILD=2 ./make_release.sh
```

This builds a signed `releases/Whitespace-0.2.dmg` and updates `appcast.xml`
(EdDSA-signed enclosure, download URL pointing at the GitHub Release asset).

Then publish — **both** steps, or clients won't see the update:

```sh
gh release create v0.2 releases/Whitespace-0.2.dmg \
  --repo zpphxd/whitespace --title "Whitespace 0.2" --notes "What changed…"

git add appcast.xml && git commit -m "release v0.2" && git push
```

Users on an older build get a Sparkle prompt within a day (or via **Check for
Updates…** in the menu), download the new DMG, and it installs in place.

## Notarization (recommended)

Developer ID signing lets Sparkle install updates, but a *first* download from
the web still trips Gatekeeper until the DMG is notarized. Once, create an
app-specific password at appleid.apple.com, then per release:

```sh
xcrun notarytool submit releases/Whitespace-0.2.dmg \
  --apple-id you@example.com --team-id 3Q5YCK6M5B --password <app-specific-pw> --wait
xcrun stapler staple releases/Whitespace-0.2.dmg
# re-run the appcast step so the signature matches the stapled DMG, then push
```

## Notes

- The build is currently **arm64-only** (the appcast advertises
  `arm64`). To support Intel Macs, produce a universal binary
  (`swift build --arch arm64 --arch x86_64`) before packaging.
- `appcast.xml` is the only distribution file committed to the repo; DMGs and
  the generated background are git-ignored and live on GitHub Releases.
