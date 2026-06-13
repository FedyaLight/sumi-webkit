# Sumi Alpha Updates

Sumi Alpha builds use Sparkle 2 for update checks, archive verification, download, installation, and relaunch. Sumi does not implement its own updater, downloader, installer, app replacer, quarantine remover, or relaunch mechanism.

The current Alpha channel is distributed outside the Mac App Store. Developer ID signing and notarization are not required for the current Alpha process, but the updater architecture is compatible with adding them later.

## First Install

1. Download the latest Alpha archive from [GitHub Releases](https://github.com/FedyaLight/sumi-webkit/releases).
2. Unzip the archive.
3. Move `Sumi.app` to `/Applications`.
4. Launch Sumi.

If macOS blocks the first launch, use System Settings > Privacy & Security > Open Anyway for Sumi.

Unsigned Alpha builds may also require a user-run quarantine workaround:

```sh
xattr -dr com.apple.quarantine /Applications/Sumi.app
```

Run that command only if you understand what it does and only for a Sumi app bundle you intentionally downloaded. Sumi itself must not run `xattr` or remove quarantine attributes.

## Update Flow

After Sumi launches, updates are handled by Sparkle:

- Sumi reads the Alpha appcast from `https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml`.
- `Sumi/Info.plist` contains the Sparkle EdDSA public key as `SUPublicEDKey`.
- Sparkle verifies update archives with the EdDSA signature in the appcast enclosure.
- Sparkle downloads, extracts, installs, and relaunches the update.
- Sumi shows the update state in Settings > About and in the compact sidebar notice.
- Manual checks are available from Sumi > Check for Updates... and Settings > About.

Sumi Alpha does not automatically install updates. Users explicitly start installation from the sidebar notice or Settings > About, while Sparkle handles the signed appcast, archive verification, download, install, and relaunch.

## Sparkle Keys

`Sumi/Info.plist` contains only the public Sparkle EdDSA key. The matching private key must stay outside git, preferably in the maintainer's login Keychain, a password manager, or another release-only secret store.

Anyone with the private key can sign Sumi updates that existing Sumi builds will trust. Do not commit it, paste it into GitHub Actions logs, add it to appcasts, or include it in release notes.

If the public key in the app does not match the private key used to generate appcast signatures, Sparkle rejects the update. If the private key is compromised, ship a Sumi build with a new `SUPublicEDKey` before publishing archives signed with the new private key.

## Local Testing Status

The earlier localhost appcast workflow was development-only infrastructure and is no longer a supported Sumi runtime path. The app runtime must not contain local feed overrides, loopback appcast arguments, or hidden Debug-only appcast replacement.

Release validation should use the hosted Alpha flow: a GitHub Release archive, a signed `appcast-alpha.xml`, and a real installed older Alpha build.

## Future Signed Builds

Developer ID signing and notarization can be added later without replacing Sparkle:

- Keep Sparkle 2 and the Alpha appcast structure.
- Sign the app with Developer ID Application.
- Enable hardened runtime as required by the release configuration.
- Notarize and staple the app or disk image as part of release packaging.
- Publish the signed and notarized archive in GitHub Releases.
- Regenerate and publish the signed appcast after the archive URL is final.
