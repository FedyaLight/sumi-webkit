# Sumi Release Process

Sumi releases are built on a local release Mac with the checked-in Xcode project signing settings. GitHub-hosted runners run portable guardrails, but do not produce the public DMG because their macOS image may lag the SDK required by Sumi's WebKit runtime.

## Current Alpha Identity

- Product version: `0.0.8`
- Build number: `13`
- Product stage: `Alpha`
- Update channel: `alpha`
- Tag: `v0.0.8`
- GitHub release title: `Sumi 0.0.8`
- GitHub release state: ordinary public Release, not draft and not GitHub prerelease
- Release DMG: `release/artifacts/0.0.8/Sumi-0.0.8-build13-macos-arm64.dmg`
- Alpha appcast: [`https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml`](https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml)
- Alpha 1 migration appcast: [`https://fedyalight.github.io/sumi-webkit/appcast.xml`](https://fedyalight.github.io/sumi-webkit/appcast.xml)

The `0.0.x` version line is Sumi's public Alpha line. GitHub's prerelease flag is not used: Alpha builds are ordinary Releases. The GitHub title contains only the product name and version. Alpha status remains explicit in the application, update channel, site badge, and repository documentation.

## Architecture and Migration Boundary

The current Alpha ships one immutable Apple-silicon (`arm64`) DMG. The release scripts reject `x86_64` and Universal packaging, and verify the architecture and code signature before and after mounting the DMG.

Both Sparkle feeds publish the same signed Arm64 item. Sparkle records its `arm64` hardware requirement in the appcast, so an Apple-silicon Mac can update directly even when its current Sumi bundle is an older Intel build running under Rosetta. A native Intel Mac is not eligible for that item. Alpha 4 (`0.0.4`) is the final Intel-compatible build for installations that already have it; it must never be offered an Arm-only archive.

## Build the Release DMG

Run:

```sh
scripts/release/package_alpha_release.sh
```

The command runs the repository release gates, builds only `arm64`, signs the app with the project's configured Apple development account, and creates this immutable asset:

```text
release/artifacts/0.0.8/Sumi-0.0.8-build13-macos-arm64.dmg
```

The DMG has a repository-owned Finder layout:

- only `Sumi.app` and the Applications link are visible;
- the two `112 pt` icons are positioned symmetrically;
- Finder toolbar and status bar are hidden;
- the volume uses Sumi's application icon;
- no script or quarantine workaround is embedded in the image.

## Generate the Appcasts

After the final Arm64 DMG exists, run:

```sh
SPARKLE_ED_KEY_FILE="/path/to/sumi-sparkle-ed25519.key" \
scripts/release/generate_current_alpha_appcast.sh
```

The script signs and validates both appcasts, uses the immutable release-asset URL by default, and refuses success unless both feeds reference the Arm64 archive and declare the `arm64` hardware requirement.

## Publish the Current Alpha

Do not publish until the release artifacts, signatures, appcast signatures, and update path have passed the checks below:

```sh
gh release create v0.0.8 \
  release/artifacts/0.0.8/Sumi-0.0.8-build13-macos-arm64.dmg \
  --title "Sumi 0.0.8" \
  --notes-file docs/releases/0.0.8.md \
  --latest
```

Do not pass `--draft` or `--prerelease`. This is a normal public GitHub Release. Publish the signed appcast changes only after that immutable GitHub asset exists, then deploy the matching website changes.

## Retire Historic Intel and Universal Assets

After both public appcasts contain only the new Arm64 item, inspect the planned cleanup:

```sh
scripts/release/retire_legacy_architecture_assets.sh
```

Only after reviewing that output, run:

```sh
scripts/release/retire_legacy_architecture_assets.sh --apply
```

The script refuses deletion if a release would have no Arm64 DMG left, or if either live appcast still references a candidate Intel or Universal URL. It only targets assets whose names end in `-macos-x86_64.dmg` or `-macos-universal.dmg`; it never deletes Arm64 assets.

## Verification

- Confirm version `0.0.8`, build `13`, channel `alpha`, feed URLs, and Apple development signing identity.
- Run the release gates and mount the Arm64 DMG to verify its Finder layout and code signature.
- Confirm `lipo -archs` returns only `arm64` for the packaged executable.
- Verify the Sparkle enclosure length and EdDSA signature against the immutable GitHub asset.
- Confirm both public feeds offer the same `0.0.8 build 13` Arm64 item after publication.
- Test an installed Apple-silicon Alpha build, including an older x86 bundle running under Rosetta, receiving the Arm64 update.
- Confirm a native Intel build sees no Arm-only offer.
- Confirm release notes, website copy, asset name, SHA-256 value, and the `latest` release link.

## Distribution Boundary

The current release is development-signed with hardened runtime enabled, but is not Developer ID signed or notarized. A wider distribution path requires Apple Developer Program access, Developer ID Application signing, notarization, and stapling.
