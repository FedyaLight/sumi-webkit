# Sumi Release Process

Sumi releases are built on a local release Mac with the checked-in Xcode project signing settings. GitHub-hosted runners run portable guardrails, but do not produce the public DMGs because their macOS image may lag the SDK required by Sumi's WebKit runtime.

## Alpha 2 Identity

- Product version: `0.0.2`
- Build number: `4`
- Product stage: `Alpha 2`
- Update channel: `alpha`
- Tag: `v0.0.2`
- GitHub release: ordinary public Release, not draft and not GitHub prerelease
- Apple silicon DMG: `release/artifacts/0.0.2/Sumi-0.0.2-macos-arm64.dmg`
- Intel DMG: `release/artifacts/0.0.2/Sumi-0.0.2-macos-x86_64.dmg`
- Sparkle hotfix archive: `Sumi-0.0.2-build4-macos-universal.dmg`
- Alpha appcast: `https://fedyalight.github.io/sumi-webkit/appcast-alpha.xml`
- Legacy `0.0.1` bridge appcast: `https://fedyalight.github.io/sumi-webkit/appcast.xml`

The `0.0.x` version line is Sumi's public Alpha line. GitHub's prerelease flag is not used: Alpha builds are ordinary Releases, like the project's release model requires. Alpha status remains explicit in the release title, notes, application About panel, update channel, and repository documentation.

## Build Both DMGs

Run:

```sh
scripts/release/package_alpha_release.sh
```

The command runs the repository release gates and independently builds each architecture. Packaging verifies the executable architecture and code signature before and after mounting each DMG. It also refuses to package the app when `SumiReleaseChannel` does not match the requested channel, so an Alpha build cannot accidentally be packaged by the stable release script.

Each DMG has a repository-owned Finder layout:

- only `Sumi.app` and the Applications link are visible;
- the two `112 pt` icons are positioned symmetrically;
- Finder toolbar and status bar are hidden for the DMG window;
- the volume uses Sumi's application icon;
- no script or quarantine workaround is embedded in the image.

## Publish Alpha 2

Do not run this command until the release artifacts, signatures, and update path have passed the checks below:

```sh
gh release create v0.0.2 \
  release/artifacts/0.0.2/Sumi-0.0.2-macos-arm64.dmg \
  release/artifacts/0.0.2/Sumi-0.0.2-macos-x86_64.dmg \
  release/artifacts/0.0.2/Sumi-0.0.2-macos-universal.dmg \
  --title "Sumi 0.0.2 Alpha 2" \
  --notes-file docs/releases/0.0.2.md \
  --latest
```

Do not pass `--prerelease`. Alpha 2 is a normal public GitHub Release. Creating the Release is intentionally outside release preparation and must be an explicit later action.

## Update Installed 0.0.1 Builds

The published `0.0.1` app reads `appcast.xml`. Alpha 2 reads `appcast-alpha.xml`. To migrate existing installations without permanently mixing the feeds:

1. Upload the Apple silicon and Intel DMGs for direct downloads, plus the universal DMG used by Sparkle, to the GitHub Release.
2. Set `DOWNLOAD_URL_PREFIX` to the final release asset URL prefix and `SPARKLE_ED_KEY_FILE` to the private EdDSA key stored outside git.
3. Run `scripts/release/generate_alpha_2_appcasts.sh`.
4. Confirm that both appcasts contain the same signed universal `0.0.2` enclosure. Use an immutable build-specific asset name when replacing an already-published build so an old appcast can never refer to new bytes with an old signature. Sparkle intentionally rejects separate archives with the same bundle version; the universal enclosure preserves one update version for existing Apple silicon and Intel installations.
5. Install the public `0.0.1` build and prove it offers and installs `0.0.2` from `appcast.xml`.
6. Install the resulting `0.0.2` build and prove that its About panel says `Alpha`, its feed is `appcast-alpha.xml`, and it no longer depends on the bridge feed.
7. Commit and publish both appcasts through GitHub Pages only after those checks pass.

The bridge is specific to Alpha 2. Later Alpha releases update only `appcast-alpha.xml`. The next stable release replaces `appcast.xml` with the stable feed again.

## Manual Verification

- Open each DMG and confirm the Finder layout is intact.
- Drag Sumi to Applications and launch it.
- Confirm version `0.0.2`, build `4`, channel `alpha`, feed URL, and executable architecture.
- Confirm the universal Sparkle artifact contains both `arm64` and `x86_64` executable slices.
- Verify every application and test bundle with `codesign --verify --deep --strict` and confirm the signing authority belongs to the configured Apple development account.
- Test the Apple-silicon artifact on Apple silicon.
- Test the Intel artifact on physical Intel hardware when available.
- Confirm release notes, asset names, SHA-256 values, and the `latest` release link.

## Future Distribution Hardening

The current artifacts are development-signed and not notarized. A wider distribution path should add Developer ID Application signing, hardened runtime, notarization, and stapling before publication.
