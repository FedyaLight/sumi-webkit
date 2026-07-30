# Sumi Alpha Release Process

Sumi Alpha releases are built on a local release Mac with the checked-in Xcode project signing settings. GitHub-hosted runners only run portable guardrails; they do not build alpha artifacts because the hosted macOS image can lag the SDK required by Sumi's WebKit runtime.

## First Alpha Identity

- Product version: `0.1.0`
- Build number: `1`
- Prerelease tag: `v0.1.0-alpha.1`
- Apple silicon DMG: `Sumi-0.1.0-1-alpha-macos-arm64.dmg`
- Intel DMG: `Sumi-0.1.0-1-alpha-macos-x86_64.dmg`

The app bundle uses the semantic product version and build number. The Git tag carries the alpha sequence. Do not put `-alpha.1` into `MARKETING_VERSION`; Sparkle ordering uses the bundle version/build and release metadata.

## Channel

- Alpha appcast: `https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml`
- Reserved stable appcast: `https://fedyalight.github.io/sumi-webkit/appcast.xml`
- Alpha DMG naming: `Sumi-<version>-<build>-alpha-macos-<architecture>.dmg`

`Sumi/Info.plist` points the app at the Alpha appcast. Do not add alternate localhost or debug feed overrides to the runtime.

## Sparkle Keys

Generate the EdDSA key pair with Sparkle's `generate_keys` tool:

```sh
xcodebuild -resolvePackageDependencies -project Sumi.xcodeproj -scheme Sumi
scripts/release/generate_sparkle_keys.sh
```

Rules:

- Commit only the public key as `SUPublicEDKey` in `Sumi/Info.plist`.
- Store the private key in the macOS Keychain, a password manager, or a secure release machine.
- Do not commit the private key.
- Do not paste private key material into GitHub Actions logs, release notes, appcasts, docs, or issue comments.
- Rotate the key by shipping a Sumi build with the new public key before publishing archives signed with the new private key.

For local release machines, prefer Sparkle's Keychain-backed key storage. If a file key is needed, keep it outside the repository and pass it with `SPARKLE_ED_KEY_FILE`.

## Build the Alpha DMGs

Run the release gates, then build and package both architectures:

```sh
scripts/release/package_alpha_release.sh
```

Before packaging, confirm `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`, and the release scope in `CHANGELOG.md`. A later alpha must increment at least the build number and use a new prerelease tag.

The package script first runs the local release gates:

```sh
scripts/release/run_alpha_release_gates.sh
```

Those gates require Xcode 27 or newer, run the architecture guardrails, and run the full `Sumi` and `SumiSmoke` Xcode test schemes with the project's normal signing configuration.

The script independently builds each architecture and creates:

```text
release/artifacts/Sumi-<version>-<build>-alpha-macos-arm64.dmg
release/artifacts/Sumi-<version>-<build>-alpha-macos-x86_64.dmg
```

Each DMG contains `Sumi.app` and an Applications link. Packaging verifies the app's exact executable architecture before and after mounting the DMG, verifies the disk image can be read, and verifies the app's code signature. The app is produced by the project signing settings on the release Mac; do not override release signing to ad hoc in the package command.

## Upload the Release Assets

Create or update a GitHub prerelease and upload both DMGs:

```sh
gh release create v0.1.0-alpha.1 \
  release/artifacts/Sumi-0.1.0-1-alpha-macos-arm64.dmg \
  release/artifacts/Sumi-0.1.0-1-alpha-macos-x86_64.dmg \
  --prerelease \
  --title "Sumi 0.1.0 Alpha 1" \
  --notes-file docs/releases/0.1.0-alpha.1.md
```

Use the `0.1.0-alpha.1` section of `CHANGELOG.md` as the basis for release notes, adding the exact macOS/Xcode build, signing/notarization state, and known limitations of the packaged artifact.

## Generate the Alpha Appcast for a Later Build

The first alpha's appcast intentionally remains empty: there is no older public build to update. Before publishing a later alpha, choose and test an architecture-aware update strategy. The two same-version, single-architecture DMGs must not be passed together to `generate_appcast` without proving Sparkle selects the correct payload on both architectures.

Once the update payload strategy is established, generate the signed appcast from a directory containing only the intended update payload set:

```sh
DOWNLOAD_URL_PREFIX="https://github.com/FedyaLight/sumi-webkit/releases/download/v0.1.0-alpha.1" \
SPARKLE_ED_KEY_FILE="/absolute/path/outside-the-repository/sparkle_ed_private_key" \
scripts/release/generate_alpha_appcast.sh /absolute/path/to/update-payloads
```

The script writes `docs/appcast-alpha.xml` and validates that update enclosures contain `sparkle:edSignature` and `length`. If the private key is stored in the Keychain format Sparkle expects, omit `SPARKLE_ED_KEY_FILE` and let Sparkle read from supported local storage.

## Publish the Appcast

The appcast is a static file. GitHub Pages should serve:

```text
https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml
```

Manual repository setup:

1. Open repository Settings > Pages.
2. Set Build and deployment Source to GitHub Actions.
3. Ensure Actions are enabled for the repository.
4. Push `docs/appcast-alpha.xml` or run the `Publish Appcasts to GitHub Pages` workflow.

The Pages workflow publishes `docs/appcast-alpha.xml` and the reserved `docs/appcast.xml`.

## Legacy URL Migration

Some development builds may have pointed at the old `appcast-preview.xml` URL. New Sumi builds must use `appcast-alpha.xml`.

If those older builds need to update in place, handle the migration at the hosting layer with a temporary static copy or redirect from the old URL to the Alpha appcast. Do not reintroduce Preview naming, channel selection, or local feed override code in Sumi.

## Test a Published Alpha Update

1. Build and install an older Alpha version in `/Applications/Sumi.app`.
2. Confirm that older build has the same `SUPublicEDKey` as the appcast signatures.
3. Publish a GitHub Release containing the newer Alpha artifacts.
4. Generate and publish `docs/appcast-alpha.xml` with the tested architecture-aware update payload URL.
5. Launch the older installed app.
6. Use Sumi > Check for Updates..., or open Settings > About.
7. Confirm Settings > About reports the Alpha channel and the newer version.
8. Confirm the sidebar notice appears for the update.
9. Dismiss the sidebar notice and confirm it stays dismissed for that version/build.
10. Publish a still newer version/build and confirm the notice reappears.
11. Click Update and confirm Sparkle performs the install and relaunch flow.
12. Confirm the sidebar success notice appears after relaunching into the newer version/build.

## What Remains Manual Today

- Protecting and backing up the Sparkle private key outside git.
- Creating release notes.
- Choosing and validating architecture-aware Sparkle payload selection before the second alpha.
- Generating the signed appcast after the update artifact URL is known.
- Enabling GitHub Pages with GitHub Actions as the Pages source.
- Manual first-install user steps for unsigned Alpha builds if macOS blocks launch.

## Future Developer ID and Notarization

Stable releases should add:

- Developer ID Application signing.
- Hardened runtime.
- Notarization.
- Stapling.
- Optional CI secrets for Apple signing and notarization, configured only in GitHub repository settings.

Those changes fit between archive build and appcast generation. Sparkle, GitHub Releases, and static appcast hosting stay the same.

## Manual Verification Checklist

- Build Sumi with Sparkle integrated.
- Confirm Sumi > Check for Updates... exists.
- Confirm Settings > About shows version/build and Alpha status.
- Confirm a controlled Alpha appcast can create an update-available state.
- Confirm the sidebar notice appears for an available update.
- Confirm the close button dismisses the notice for that version/build.
- Confirm the same version/build does not reappear after dismissal.
- Confirm a newer version/build appears again.
- Confirm the Update button invokes Sparkle's supported flow.
- Confirm Sumi does not show Sparkle's standard update-available window.
- Confirm no popup appears on normal launch just because an update exists.
- Confirm browsing, sidebar, extensions, favicons, profile loading, and memory/performance modes still start normally.
- Confirm build and tests pass.
