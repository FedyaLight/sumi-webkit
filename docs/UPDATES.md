# Sumi Updates

Sumi uses Sparkle 2 for update checks, archive verification, download, installation, and relaunch. Sumi does not implement its own updater, installer, quarantine remover, or app replacement mechanism.

## First Install

For Alpha 5 (`v0.0.5`):

1. Download the Apple-silicon DMG from [GitHub Releases](https://github.com/FedyaLight/sumi-webkit/releases/tag/v0.0.5).
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
- Alpha 5 is published to both feeds as `0.0.5 build 9`, so eligible installed builds move directly to the current Alpha channel without a staged bridge.
- The Alpha 5 appcast item requires `arm64` hardware. Sparkle therefore offers it to Apple-silicon Macs, including an older Intel build running under Rosetta, but not to native Intel Macs.
- Native Intel Macs receive no Alpha 5 offer. Alpha 4 (`0.0.4`) is the final Intel-compatible build for installations that already have it; no further Intel archive is distributed.
- `Sumi/Info.plist` contains the Sparkle EdDSA public key as `SUPublicEDKey`.
- Sparkle verifies update archives using the signature in the appcast enclosure.
- Users explicitly start installation from Settings > About or the sidebar notice.
- Sparkle handles download, installation, and relaunch.
- After relaunch, the completed sidebar notice links to `https://sumi-browser.netlify.app/changelog/#<display-version>`; each public release entry must use its display version as the Changelog anchor.

Alpha 1's `appcast.xml` was initially empty. Alpha 2 established the first bridge and the Alpha channel. Alpha 5 replaces that bridge with a direct signed Arm64 update item in both feeds; no Universal update archive is used.

## Signing Boundaries

The current release is development-signed, not Developer ID signed or notarized. A future broadly distributed build should add Developer ID Application signing, hardened runtime, notarization, and stapling without replacing Sparkle.

The Sparkle private key must remain outside git. Only the public EdDSA key belongs in `Sumi/Info.plist`.
