# Notarizing MeetingScribe

This documents how to take the locally-built `MeetingScribe.app` and produce a
notarized, Gatekeeper-friendly build for distribution outside the Mac App Store.

## What's already in place

- **Bundle identifier** — `com.tyleryannes.MeetingScribe`, set in
  `Resources/Info.plist` (`CFBundleIdentifier`) and used by the Makefile
  (`BUNDLE_ID`).
- **Hardened Runtime** — `make app` signs every Mach-O with `--options runtime`
  (the app, the bundled `MeetingScribeMCP` / `NotionMCP` binaries, and
  `Sparkle.framework`). Notarization *requires* Hardened Runtime, so this is
  already satisfied.
- **Entitlements** — `Resources/Entitlements.plist` is applied to the app at
  sign time. It declares exactly what this app needs:
  - `com.apple.security.device.audio-input` — mic capture (AVAudioEngine)
  - `com.apple.security.personal-information.calendars` — EventKit
  - `com.apple.security.personal-information.addressbook` — contact import
  - `com.apple.security.cs.disable-library-validation` — lets the
    runtime-loaded, bundle-local `Sparkle.framework` load under Hardened Runtime

### Why this app is intentionally NOT sandboxed

App Sandbox (`com.apple.security.app-sandbox`) is **deliberately omitted**.
Notarization does not require the sandbox — only Hardened Runtime does. Enabling
the sandbox would break core functionality:

- **Screen/system-audio capture** via ScreenCaptureKit,
- **launching the bundled `MeetingScribeMCP` / `NotionMCP` helper executables**,
- **talking to a local Ollama** server and writing meeting archives to a
  user-chosen `storageDir` outside the container.

Outbound network (Ollama, Notion/Linear/Google Drive, the Sparkle feed) works
without `com.apple.security.network.client` precisely because the app is not
sandboxed — that entitlement is a no-op outside the sandbox.

## One-time setup

1. A **Developer ID Application** certificate in your login keychain (this is
   different from the self-signed "MeetingScribe Local Signer" used for local
   TCC-stable builds; notarization requires a real Developer ID).
2. An **app-specific password** for your Apple ID, stored as a notarytool
   profile:

   ```sh
   xcrun notarytool store-credentials "MeetingScribe-Notary" \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID" \
     --password "app-specific-password"
   ```

## Per-release steps

1. **Build + sign with Developer ID.** The Makefile currently signs with
   `SIGN_IDENTITY` (the local signer). For a notarized build, sign with your
   Developer ID Application identity instead — e.g. set the identity and run
   `make app`, or re-sign:

   ```sh
   codesign --force --options runtime \
     --sign "Developer ID Application: Your Name (YOURTEAMID)" \
     --identifier com.tyleryannes.MeetingScribe \
     --entitlements Resources/Entitlements.plist \
     build/MeetingScribe.app
   ```

2. **Zip the app** (notarytool takes a zip/dmg/pkg):

   ```sh
   ditto -c -k --keepParent build/MeetingScribe.app dist/MeetingScribe.zip
   ```

3. **Submit and wait:**

   ```sh
   xcrun notarytool submit dist/MeetingScribe.zip \
     --keychain-profile "MeetingScribe-Notary" --wait
   ```

4. **Staple** the ticket so the app validates offline:

   ```sh
   xcrun stapler staple build/MeetingScribe.app
   ```

5. **Verify:**

   ```sh
   spctl -a -vvv -t exec build/MeetingScribe.app   # → accepted, source=Notarized Developer ID
   ```

## CI note

The release workflow (`.github/workflows/release.yml`) currently does an ad-hoc
/ local-signer build. Wiring notarization into CI would mean adding the
Developer ID cert + notarytool credentials as encrypted secrets and inserting a
`notarytool submit --wait` + `stapler staple` step before the
`softprops/action-gh-release` publish step.
