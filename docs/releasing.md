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

## Release configuration file

Copy `Packaging/macOS/release.env.example` to `Packaging/macOS/release.env` and fill in real values.

All release scripts automatically source `Packaging/macOS/release.env` if it exists. You can override that path with:

```sh
RELEASE_ENV_FILE=/path/to/custom-release.env ./scripts/build-app.sh
```

The shared loader now validates common failure cases early:

- required variables are present when a script needs them
- release feed/download URLs use `https`
- required file paths (for example `SPARKLE_PRIVATE_KEY_FILE`) exist before the script continues
- placeholder values like `REPLACE_WITH_SPARKLE_PUBLIC_KEY` are rejected before build packaging proceeds

## Local rehearsal without signing credentials

You can verify that the app bundle assembles correctly before you have signing/notarization credentials:

```sh
cp Packaging/macOS/release.env.example Packaging/macOS/release.env
# edit Packaging/macOS/release.env with rehearsal-safe values
./scripts/build-app.sh
```

This should produce `dist/Glance.app` with:

- `Contents/MacOS/Glance`
- `Contents/Frameworks/Sparkle.framework`
- `Contents/Resources/Glance_GlanceApp.bundle`

The executable includes an `@executable_path/../Frameworks` runpath and resolves its
SwiftPM resources from `Contents/Resources`. Check both without opening the menu
or loading local source data:

```sh
dist/Glance.app/Contents/MacOS/Glance --check-bundle
```

Repeat this check after copying the app outside the checkout. It must print
`Glance bundle loaded successfully` without relying on build products.
`scripts/verify-release.sh` includes this check, but will still fail until the app
is properly codesigned, notarized, and configured with production values.

## Release scripts

- `scripts/build-app.sh` — builds `dist/Glance.app` from the SwiftPM release binary and injects bundle metadata.
- `scripts/codesign.sh` — code signs embedded frameworks first, then the app bundle.
- `scripts/package-update-zip.sh` — creates a Sparkle-compatible zip (`dist/Glance.zip`).
- `scripts/notarize.sh` — submits the archive for notarization and staples the app.
- `scripts/generate-appcast.sh` — generates `dist/appcast.xml` using Sparkle’s `generate_appcast` tool. Sparkle scans the directory containing `ARTIFACT_PATH`; keep only intended update archives in that directory. `APPCAST_OUTPUT` is passed with Sparkle's `-o` option. The download directory URL is normalized to end with `/` so its last path component is preserved.
- `scripts/verify-release.sh` — verifies bundle metadata, placeholder removal, code signing, and optional zip/appcast outputs.

## Minimal release flow

1. Build the app bundle:

   ```sh
   ./scripts/build-app.sh
   ```

2. Code sign the app bundle:

   ```sh
   ./scripts/codesign.sh
   ```

3. Package the Sparkle update archive:

   ```sh
   ./scripts/package-update-zip.sh
   ```

4. Notarize, staple, and rebuild the zip from the stapled app:

   ```sh
   ./scripts/notarize.sh
   ```

5. Generate the appcast:

   ```sh
   ./scripts/generate-appcast.sh
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

Do not commit `Packaging/macOS/release.env`; keep it local or inject those values via CI secrets.

## Feed overrides for staging

You can override the feed URL at runtime for local/staging builds with:

`GLANCE_SPARKLE_FEED_URL=https://staging.example.com/appcast.xml`

The app still requires a valid `SUPublicEDKey` in bundle metadata before the updater will enable itself.

If `GLANCE_SPARKLE_FEED_URL` is invalid, the app falls back to the bundle’s `SUFeedURL`.

## Support reports

Glance can export a JSON support report from Settings.

- Use **Copy Support Report** to put the current report on the clipboard.
- Use **Export Support Report…** to save a timestamped JSON file.

The exported report is intended for troubleshooting local source issues and includes current source diagnostics, policy settings, and a small allowlisted subset of environment configuration. It does not include transcript contents or full environment dumps.
