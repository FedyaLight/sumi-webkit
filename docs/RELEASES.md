# Sumi Release Process

Sumi releases are built on a local release Mac with the checked-in Xcode project signing settings. GitHub-hosted runners run portable guardrails, but do not produce the public DMGs because their macOS image may lag the SDK required by Sumi's WebKit runtime.

## 0.0.1 Identity

- Product version: `0.0.1`
- Build number: `1`
- Tag: `v0.0.1`
- Apple silicon DMG: `Sumi-0.0.1-macos-arm64.dmg`
- Intel DMG: `Sumi-0.0.1-macos-x86_64.dmg`
- Stable appcast: `https://fedyalight.github.io/sumi-webkit/appcast.xml`

## Build Both DMGs

Run:

```sh
scripts/release/package_stable_release.sh
```

The command runs the repository release gates and independently builds each architecture. Packaging verifies the executable architecture and code signature before and after mounting each DMG.

Each DMG has a repository-owned Finder layout:

- only `Sumi.app` and the Applications link are visible;
- the two `112 pt` icons are positioned symmetrically;
- Finder toolbar and status bar are hidden for the DMG window;
- the volume uses Sumi's application icon;
- no script or quarantine workaround is embedded in the image.

## Publish

Create or update the ordinary GitHub Release:

```sh
gh release create v0.0.1 \
  release/artifacts/Sumi-0.0.1-macos-arm64.dmg \
  release/artifacts/Sumi-0.0.1-macos-x86_64.dmg \
  --title "Sumi 0.0.1" \
  --notes-file docs/releases/0.0.1.md
```

Release notes must state that the artifacts are not Apple-notarized and include the exact quarantine workaround from `docs/releases/0.0.1.md`.

## Appcast

The first stable appcast is empty because there is no older public build to update. Before publishing a later release:

1. Increment at least `CURRENT_PROJECT_VERSION`.
2. Choose and validate an architecture-aware Sparkle update payload.
3. Generate the signed appcast with the private EdDSA key stored outside git.
4. Test the update from an installed older release on the supported architectures.
5. Publish the appcast only after the release artifact URL is final.

Do not pass two same-version, single-architecture DMGs to Sparkle without proving that it selects the correct payload on both architectures.

## Manual Verification

- Open each DMG and confirm the Finder layout is intact.
- Drag Sumi to Applications and launch it.
- Confirm the bundle version and executable architecture.
- Verify `codesign --verify --deep --strict`.
- Test the Apple-silicon artifact on Apple silicon.
- Test the Intel artifact on physical Intel hardware when available.
- Confirm release notes, asset names, SHA-256 values, and the `latest` release link.

## Future Distribution Hardening

The current artifacts are development-signed and not notarized. A wider distribution path should add Developer ID Application signing, hardened runtime, notarization, and stapling before publication.
