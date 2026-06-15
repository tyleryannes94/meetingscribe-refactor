# Releasing & auto-updates

MeetingScribe ships updates with [Sparkle](https://sparkle-project.org). Installed
copies check `SUFeedURL` (in `Resources/Info.plist`) — which points at
`https://github.com/tyleryannes94/meetingscribe-refactor/releases/latest/download/appcast.xml`
— and update themselves when you publish a new release. Updates are verified
with an EdDSA signature, so only builds you signed with your private key are
accepted.

> **Two things must be true for in-app updates to work:**
>
> 1. **The repository (its Releases) must be publicly reachable.** Sparkle
>    fetches `appcast.xml` and the build zip over plain HTTPS with no auth, so
>    a *private* repo returns 404 and updates silently never appear. Keep the
>    repo public, or host the appcast + zip on a public mirror / GitHub Pages.
> 2. **Each release must include `appcast.xml`.** Cut releases by pushing a
>    tag (or running the Release workflow) — never by hand. A manually-uploaded
>    zip has no appcast, so the feed 404s and "Check for Updates" can't find
>    anything. The workflow attaches both `MeetingScribe.zip` and `appcast.xml`.

## One-time setup (do this once)

You need a Sparkle EdDSA key pair. The **private** key signs releases (kept in
a GitHub secret); the **public** key ships in the app to verify them.

The easy path is the helper script — it locates `generate_keys`, generates the
keypair, patches `Resources/Info.plist`, exports the private key for the
GitHub secret, and cleans up after itself:

```sh
swift build -c release            # one-time: lets SwiftPM fetch Sparkle
./scripts/setup-sparkle-key.sh
```

The script is idempotent — re-running on an already-configured repo is a no-op
(it refuses to clobber a real public key without `--force`). It prints a
verification checklist at the end; the only manual step is pasting the printed
private key into the GitHub `SPARKLE_PRIVATE_KEY` secret at
<https://github.com/tyleryannes94/meetingscribe-refactor/settings/secrets/actions>.

Then commit the patched `Resources/Info.plist` — the **public** key is safe to
commit; only the private key is sensitive.

<details>
<summary>Manual setup (if the script can't find Sparkle's tools)</summary>

1. Download the latest `Sparkle-*.tar.xz` from
   <https://github.com/sparkle-project/Sparkle/releases> and extract it.
   Then point the script at its `bin/`:
   `SPARKLE_BIN=~/Downloads/Sparkle-2.6.4/bin ./scripts/setup-sparkle-key.sh`

2. Or fully by hand: run `./bin/generate_keys` to mint the keypair (private
   key goes to your login keychain, public key is printed). Paste the public
   key into `Resources/Info.plist :SUPublicEDKey`. Export the private key with
   `./bin/generate_keys -x private_key.pem`, paste it into the
   `SPARKLE_PRIVATE_KEY` GitHub secret, then `rm private_key.pem`. Never
   commit the private key.
</details>

## Cutting a release

Releases are tag-driven, so a normal merge to `main` does **not** ship anything
until you tag it:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The `Release` workflow (`.github/workflows/release.yml`) then:

1. stamps the version into `Info.plist`,
2. builds `MeetingScribe.app` (embedding + signing Sparkle),
3. zips it,
4. EdDSA-signs the zip and generates `appcast.xml`,
5. publishes a GitHub Release with `MeetingScribe.zip` + `appcast.xml`.

Within ~24h (or on the next manual "Check for Updates…") installed copies see
the new version and offer to update. You can also trigger the workflow manually
from the Actions tab (provide the version number).

## How friends install

1. Download `MeetingScribe.zip` from the latest release and unzip into
   `/Applications`.
2. Because the app isn't notarized by Apple, the first launch needs a
   right-click → **Open** (or `xattr -dr com.apple.quarantine /Applications/MeetingScribe.app`).
3. After that, auto-updates are silent/prompted — no more manual downloads.

> If you later enroll in the Apple Developer Program, add Developer ID signing +
> notarization to the workflow and the quarantine step goes away.

## Versioning notes

- `CFBundleShortVersionString` and `CFBundleVersion` are set from the tag during
  CI, so you don't have to bump them by hand — just tag.
- Sparkle compares `CFBundleVersion`; keep tags monotonically increasing
  (`v0.2.0` → `v0.2.1` → `v0.3.0`).
