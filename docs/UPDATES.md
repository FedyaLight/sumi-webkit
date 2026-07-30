# Sumi Updates

Sumi uses Sparkle 2 for update checks, archive verification, download, installation, and relaunch. Sumi does not implement its own updater, installer, quarantine remover, or app replacement mechanism.

## First Install

For `v0.0.1`:

1. Download the matching DMG from [GitHub Releases](https://github.com/FedyaLight/sumi-webkit/releases/tag/v0.0.1): `arm64` for Apple silicon or `x86_64` for Intel.
2. Open the DMG and drag `Sumi.app` to Applications.
3. Launch Sumi.

Current builds are not Apple-notarized. If macOS says the app is damaged, move it to `/Applications` and remove the quarantine flag:

```sh
sudo xattr -dr com.apple.quarantine "/Applications/Sumi.app"
open "/Applications/Sumi.app"
```

Run this only for a Sumi bundle you intentionally downloaded. Sumi itself never removes quarantine attributes.

## Update Flow

- Sumi reads the stable appcast from `https://fedyalight.github.io/sumi-webkit/appcast.xml`.
- `Sumi/Info.plist` contains the Sparkle EdDSA public key as `SUPublicEDKey`.
- Sparkle verifies update archives using the signature in the appcast enclosure.
- Users explicitly start installation from Settings > About or the sidebar notice.
- Sparkle handles download, installation, and relaunch.

The appcast for the first release is intentionally empty because no older public build exists to update. End-to-end update validation requires a later controlled build with a higher build number and an architecture-aware update artifact strategy.

## Signing Boundaries

The current release is development-signed, not Developer ID signed or notarized. A future broadly distributed build should add Developer ID Application signing, hardened runtime, notarization, and stapling without replacing Sparkle.

The Sparkle private key must remain outside git. Only the public EdDSA key belongs in `Sumi/Info.plist`.
