# Releasing Glance

This repository now expects Sparkle-based updates for direct-download releases.

## Required release inputs

- A signed, notarized `Glance.app`
- A Sparkle appcast hosted over HTTPS
- A Sparkle public EdDSA key embedded in `Packaging/macOS/Info.plist` as `SUPublicEDKey`
- A valid appcast URL embedded in `Packaging/macOS/Info.plist` as `SUFeedURL`
- A Developer ID Application certificate name for `scripts/codesign.sh`
- A configured `notarytool` keychain profile for `scripts/notarize.sh`
- A Sparkle private EdDSA key file for `scripts/generate-appcast.sh`

## Local rehearsal without signing credentials

You can verify that the app bundle assembles correctly before you have signing/notarization credentials:

```sh
VERSION=1.0.0 \
BUILD_NUMBER=1 \
APPCAST_URL=https://updates.example.org/appcast.xml \
SPARKLE_PUBLIC_ED_KEY=dummy-public-key \
./scripts/build-app.sh
```

This should produce `dist/Glance.app` with:

- `Contents/MacOS/Glance`
- `Contents/Frameworks/Sparkle.framework`
- `Contents/Resources/Glance_GlanceApp.bundle`

At that point you can validate structure, but `scripts/verify-release.sh` will still fail until the app is properly codesigned, notarized, and configured with non-placeholder production values.

## Release scripts

- `scripts/build-app.sh` — builds `dist/Glance.app` from the SwiftPM release binary and injects bundle metadata.
- `scripts/codesign.sh` — code signs embedded frameworks first, then the app bundle.
- `scripts/package-update-zip.sh` — creates a Sparkle-compatible zip (`dist/Glance.zip`).
- `scripts/notarize.sh` — submits the archive for notarization and staples the app.
- `scripts/generate-appcast.sh` — generates `dist/appcast.xml` using Sparkle’s `generate_appcast` tool.
- `scripts/verify-release.sh` — verifies bundle metadata, placeholder removal, code signing, and optional zip/appcast outputs.

## Minimal release flow

1. Build the app bundle:

   ```sh
   VERSION=1.0.0 BUILD_NUMBER=1 APPCAST_URL=https://downloads.example.com/appcast.xml SPARKLE_PUBLIC_ED_KEY=... ./scripts/build-app.sh
   ```

2. Code sign the app bundle:

   ```sh
   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/codesign.sh
   ```

3. Package the Sparkle update archive:

   ```sh
   ./scripts/package-update-zip.sh
   ```

4. Notarize, staple, and rebuild the zip from the stapled app:

   ```sh
   NOTARY_PROFILE=glance-notary ./scripts/notarize.sh
   ```

5. Generate the appcast:

   ```sh
   DOWNLOAD_BASE_URL=https://downloads.example.com/releases/1.0.0 SPARKLE_PRIVATE_KEY_FILE="$HOME/.config/sparkle/ed25519.pem" ./scripts/generate-appcast.sh
   ```

6. Verify the release bundle and published artifacts:

   ```sh
   ./scripts/verify-release.sh
   ```

7. Upload `dist/Glance.zip` and `dist/appcast.xml` to your HTTPS host.

The notarization step intentionally rebuilds `dist/Glance.zip` *after* stapling so the shipped archive contains the stapled `.app` bundle.

## External inputs still required to complete a real release

The repository now contains the Sparkle wiring and release script skeleton, but a real publish still requires these externally managed inputs:

- `CODESIGN_IDENTITY`
- `NOTARY_PROFILE`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_KEY_FILE`
- a real HTTPS `APPCAST_URL`
- a real HTTPS `DOWNLOAD_BASE_URL`

Until those values are supplied, the project is release-prepared but not release-complete.

## Feed overrides for staging

You can override the feed URL at runtime for local/staging builds with:

`GLANCE_SPARKLE_FEED_URL=https://staging.example.com/appcast.xml`

The app still requires a valid `SUPublicEDKey` in bundle metadata before the updater will enable itself.

If `GLANCE_SPARKLE_FEED_URL` is invalid, the app falls back to the bundle’s `SUFeedURL`.
