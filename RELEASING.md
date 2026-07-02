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

## Notarization (required for clean downloads)

Developer ID signing alone is NOT enough for downloads: Gatekeeper shows
“Apple could not verify Whitespace is free of malware” for any unnotarized
app that came from the internet. `make_release.sh` notarizes + staples the DMG
automatically **if** a notarytool keychain profile exists.

Set it up once (needs an app-specific password from
appleid.apple.com → Sign-In & Security → App-Specific Passwords):

```sh
xcrun notarytool store-credentials whitespace-notary \
  --apple-id you@example.com --team-id 3Q5YCK6M5B --password <app-specific-pw>
```

After that every `./make_release.sh` run notarizes before generating the
appcast (ordering matters — stapling changes the DMG, so the Sparkle signature
is computed on the final stapled file). If the profile is missing, the script
warns loudly and produces an unnotarized DMG.

## Notes

- The build is currently **arm64-only** (the appcast advertises
  `arm64`). To support Intel Macs, produce a universal binary
  (`swift build --arch arm64 --arch x86_64`) before packaging.
- `appcast.xml` is the only distribution file committed to the repo; DMGs and
  the generated background are git-ignored and live on GitHub Releases.
