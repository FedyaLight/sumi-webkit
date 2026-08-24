# Sumi Updates

Sumi uses Sparkle 2 for update checks, archive verification, download, installation, and relaunch. Sumi does not implement its own updater, installer, quarantine remover, or app replacement mechanism.

## First Install

For the current Alpha (`v0.0.6`):

1. Download the Apple-silicon DMG from [GitHub Releases](https://github.com/FedyaLight/sumi-webkit/releases/tag/v0.0.6).
2. Open the DMG and drag `Sumi.app` to Applications.
3. Launch Sumi.

Current builds are not Apple-notarized. If macOS says the app is damaged, move it to `/Applications` and remove the quarantine flag:

```sh
sudo xattr -dr com.apple.quarantine "/Applications/Sumi.app"
open "/Applications/Sumi.app"
```

Run this only for a Sumi bundle you intentionally downloaded. Sumi itself never removes quarantine attributes.

## Update Flow

- Alpha 1 reads `https://fedyalight.github.io/sumi-webkit/appcast.xml`; Alpha 2 and later Alpha builds read `https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml`.
- Version `0.0.6 build 10` is published to both feeds, so eligible installed builds move directly to the current Alpha channel without a staged bridge.
- The current appcast item requires `arm64` hardware. Sparkle therefore offers it to Apple-silicon Macs, including an older Intel build running under Rosetta, but not to native Intel Macs.
- Native Intel Macs receive no Arm-only offer. Version `0.0.4` is the final Intel-compatible build for installations that already have it; historic Intel and Universal assets remain published.
- `Sumi/Info.plist` contains the Sparkle EdDSA public key as `SUPublicEDKey`.
- Sparkle verifies update archives using the signature in the appcast enclosure.
- Users explicitly start installation from Settings > About or the sidebar notice.
- Sparkle handles download, installation, and relaunch.
- After relaunch, the completed sidebar notice links to `https://sumi-browser.netlify.app/changelog/#<display-version>`; each public release entry must use its display version as the Changelog anchor.

The original `appcast.xml` was initially empty. Version `0.0.2` established the first bridge and the Alpha channel. Both feeds now carry the same direct signed Arm64 update item; no Universal update archive is used for the current release.

## Signing Boundaries

The current release is development-signed, not Developer ID signed or notarized. A future broadly distributed build should add Developer ID Application signing, hardened runtime, notarization, and stapling without replacing Sparkle.

The Sparkle private key must remain outside git. Only the public EdDSA key belongs in `Sumi/Info.plist`.
