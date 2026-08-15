# Sumi Release Process

Sumi releases are built on a local release Mac with the checked-in Xcode project signing settings. GitHub-hosted runners run portable guardrails, but do not produce the public DMGs because their macOS image may lag the SDK required by Sumi's WebKit runtime.

## Alpha 4 Identity

- Product version: `0.0.4`
- Build number: `8`
- Product stage: `Alpha 4`
- Update channel: `alpha`
- Tag: `v0.0.4`
- GitHub release: ordinary public Release, not draft and not GitHub prerelease
- Apple silicon DMG: `release/artifacts/0.0.4/Sumi-0.0.4-macos-arm64.dmg`
- Intel DMG: `release/artifacts/0.0.4/Sumi-0.0.4-macos-x86_64.dmg`
- Sparkle archive: `Sumi-0.0.4-build8-macos-universal.dmg`
- Alpha appcast: `https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml`

The `0.0.x` version line is Sumi's public Alpha line. GitHub's prerelease flag is not used: Alpha builds are ordinary Releases. Alpha status remains explicit in the release title, notes, application About panel, update channel, and repository documentation.

## Build the Release DMGs

Run:

```sh
scripts/release/package_alpha_release.sh
```

The command runs the repository release gates and independently builds `arm64`, `x86_64`, and Universal applications. Packaging verifies the executable architecture and code signature before and after mounting each DMG. It also refuses to package the app when `SumiReleaseChannel` does not match the requested channel.

Each DMG has a repository-owned Finder layout:

- only `Sumi.app` and the Applications link are visible;
- the two `112 pt` icons are positioned symmetrically;
- Finder toolbar and status bar are hidden;
- the volume uses Sumi's application icon;
- no script or quarantine workaround is embedded in the image.

The architecture-specific DMGs are direct downloads. The Universal DMG is copied to the immutable build-specific name used by Sparkle so a published appcast never points new bytes at an old signature.

## Generate the Alpha Appcast

After the final Universal DMG exists:

```sh
DOWNLOAD_URL_PREFIX="https://github.com/FedyaLight/sumi-webkit/releases/download/v0.0.4/" \
SPARKLE_ED_KEY_FILE="/path/to/sumi-sparkle-ed25519.key" \
scripts/release/generate_current_alpha_appcast.sh
```

Alpha 4 updates only `appcast-alpha.xml`. The legacy `appcast.xml` remains on Alpha 2 so installed `0.0.1` builds can cross the one-time bridge and then move to the Alpha channel.

## Publish Alpha 4

Do not publish until the release artifacts, signatures, appcast signature, and update path have passed the checks below:

```sh
gh release create v0.0.4 \
  release/artifacts/0.0.4/Sumi-0.0.4-macos-arm64.dmg \
  release/artifacts/0.0.4/Sumi-0.0.4-macos-x86_64.dmg \
  release/artifacts/0.0.4/Sumi-0.0.4-build8-macos-universal.dmg \
  --title "Sumi 0.0.4 Alpha 4" \
  --notes-file docs/releases/0.0.4.md \
  --latest
```

Do not pass `--prerelease`. Alpha 4 is a normal public GitHub Release.

## Verification

- Confirm version `0.0.4`, build `8`, channel `alpha`, feed URL, and executable architecture.
- Mount every DMG and verify its Finder layout and code signature.
- Confirm the Universal Sparkle artifact contains both `arm64` and `x86_64` executable slices.
- Verify the Sparkle enclosure length and EdDSA signature against the published immutable asset.
- Test the Apple-silicon artifact on Apple silicon.
- Test the Intel artifact on physical Intel hardware when available.
- Confirm release notes, asset names, SHA-256 values, and the `latest` release link.
- Confirm an installed Alpha 2 or later build offers `0.0.4 build 8` from `appcast-alpha.xml`.

## Distribution Boundary

The current public artifacts are development-signed with hardened runtime enabled, but are not Developer ID signed or notarized. A wider distribution path requires Apple Developer Program access, Developer ID Application signing, notarization, and stapling.
