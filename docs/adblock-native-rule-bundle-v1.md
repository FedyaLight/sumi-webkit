# Sumi Native Rule Bundle v1

`sumi-webkit` is a prepared-bundle consumer only. The browser does not fetch raw filter lists, parse ABP/uBO syntax, invoke `adblock-rust`, or generate WebKit rules at runtime.

The final browser-side flow is intentionally small:

1. A separate bundle-generation repository, `sumi-protection-bundles`, fetches upstream lists outside the browser.
2. GitHub Actions generates and verifies prepared bundles there.
3. `sumi-webkit` accepts a prepared bundle, verifies the manifest, shard hashes, and native-CSS safety policy, compiles shards through `WKContentRuleListStore`, and publishes the new generation only after lookup succeeds.
4. Sumi keeps the previous generation so a failed install or failed smoke lookup can roll back safely.

The bundle directory layout is:

```text
SumiAdblockBundle/
  manifest.json
  diagnostics.json
  trackingNetwork/*.json
  network/*.json
  nativeCSS/*.json
```

`manifest.json` records the schema version, bundle id, profile id, compiler identity, safety-policy version, source-list ids and hashes, logical group metadata, profile-to-group mapping, shard metadata, unsafe native-CSS count, and deduplication/overlap summary. The app keeps only metadata, paths, hashes, identifiers, and logical groups in provider state; full shard JSON is read only for prepared-bundle verification and WebKit compilation.

`trackingNetwork` is generated in `sumi-protection-bundles` from DuckDuckGo Tracker Radar / Tracker Data Set (TDS) (`https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json`). The generated tracking shards are CC BY-NC-SA 4.0 derived data for non-commercial Sumi bundle use, with share-alike terms preserved for derived `trackingNetwork` data. Bundle and release manifests must include `sourceName`, `sourceURL`, `sourceLicense`, `sourceLicenseURL`, `attribution`, `generatedAt`, `sourceSha256`, `ruleCount`, and `shardCount` for this group.

`adblockAdsPrivacyNetwork` is generated outside the browser with the bundle generator's `adblock-rust` adapter. The current `adguardAdsPrivacy` profile records source-list metadata for AdGuard DNS filter, AdGuard Base, uBlock filters - Ads, uBlock filters - Badware risks, uBlock filters - Privacy, uBlock filters - Unbreak, and uBlock filters - Quick fixes. Bundle manifests must preserve the source-list ids, display names, URLs, hashes, byte sizes, categories, and rule counts. The combined adblock group reports `license: see source lists`; Sumi documentation and UI must not claim that this group has a single project-owned license.

Cosmetic/scriptlet shards may be present in release assets for bundle completeness, but Sumi's native browser runtime attaches network content-rule lists only.

## Product contract

The browser exposes only three product levels:

- `Off`: no protection groups, no Tracking Protection, no Adblock, no bundle lookup, and no content-rule lists.
- `Protection`: `trackingNetwork` only.
- `Adblock`: `trackingNetwork` plus `adblockAdsPrivacyNetwork`, backed by the prepared `adguardAdsPrivacy` profile. Element zapper rules are user-authored site rules layered on top of this native blocker; they are not a separate blocker backend.

Native CSS is not a normal product mode. Release bundles omit native-CSS shards by default, and the browser compiles and attaches network shards only. Native-CSS validation remains as a developer-only safety path so prepared bundles can be rejected safely if their manifest does not meet the accepted native-CSS safety policy.

## Development bundle import

Local developer tooling may still create prepared bundles outside the app. Sumi can consume a prepared development bundle from:

```text
.build/sumi-adblock-bundles/adguardAdsPrivacy/SumiAdblockBundle
```

That path is an import/consumption path only. It is not a browser generation path, and Sumi.app does not run the generation scripts.

## Remote release update design

The static update path stays outside the browser runtime:

1. GitHub Actions in `sumi-protection-bundles` generates and verifies bundles weekly or on demand.
2. GitHub Release assets expose a machine-readable release manifest, checksums, bundle manifests, diagnostics, and prepared shard JSON.
3. Sumi checks for updates only after the user presses **Update bundles** in Privacy / Protection settings.
4. Sumi downloads only the release manifest and prepared assets, verifies compatibility, byte sizes, and SHA-256 hashes, then replaces its cached prepared bundle after staging succeeds.
5. If Protection or Adblock is already the applied level, Sumi compiles the prepared shards for the requested logical groups with WebKit and commits the new active generation only after validation succeeds.
6. Sumi keeps the previous generation so failed downloads, hash mismatches, incompatible manifests, and compile failures do not replace the last known good active bundle set.

Sumi.app never runs `adblock-rust`, never parses raw filter lists, never converts DDG TDS through TrackerRadarKit, and never checks for bundle updates on launch or timers. Existing pages may need reload or a full Sumi restart after a manual bundle update; the UI reports restart-required instead of claiming live replacement.

The current repository keeps any temporary generation scripts as developer tooling only. They must not be referenced by Sumi.app runtime, release UI, or app-target build phases.

There is no browser-side DDG TrackerRadarKit fallback. Protection requires a prepared `trackingNetwork` group from the signed app, development, or remote bundle. Adblock requires both prepared `trackingNetwork` and prepared `adblockAdsPrivacyNetwork`.

## Refactor parity ledger

Protection-runtime refactors must preserve Sumi as a prepared-bundle consumer. The browser may verify signed release manifests, validate SHA-256 hashes, validate byte sizes and paths, reject downgrades, cache prepared bundles, compile prepared WebKit shards, restore cached generations, and roll back after install or lookup failure.

The following are legacy/runtime-generation surfaces and should stay absent from Sumi.app runtime:

- TrackerRadarKit imports or DDG TDS conversion code.
- Raw tracker/adblock list fetching, raw filter parsing, EasyList/EasyPrivacy runtime references, and `adblock-rust` invocation.
- Browser-side WebKit rule generation or `runtimeGenerated` fallback paths.
- Automatic background bundle/list update timers.
- Old debug-only adblock status/current-tab diagnostics and embedded catalog install APIs.

Allowed DDG/TDS references are limited to prepared `trackingNetwork` source metadata: source name, source URL, license, attribution, generated timestamp, source hash, source rule count, and source shard count. Allowed adblock source-list references are limited to prepared bundle metadata and user-facing attribution: source-list names, URLs, hashes, byte sizes, categories, and rule counts.

Run these checks after each protection-runtime cleanup pass:

```sh
git diff --check
scripts/check_userscript_hot_paths.sh
scripts/check_tracker_radar_import_boundary.sh
scripts/check_prepared_bundle_runtime_boundary.sh
xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:SumiTests/SumiAdBlockingModuleTests -only-testing:SumiTests/SumiAdblockNativeRuleBundleTests -only-testing:SumiTests/SumiAdblockUpdatePipelineTests -only-testing:SumiTests/SumiProtectionBundleRemoteUpdateTests -only-testing:SumiTests/SumiProtectionCoordinatorTests
scripts/run_perf_regression.sh verify
```

Split these changes into separate migration tasks if product direction changes: removing local development prepared-bundle import, removing signed app-resource bundle support, changing the GitHub repository/schema/signing keys, moving content blocking into SwiftPM, or changing Off/Protection/Adblock semantics.

## Manual validation

1. Open Privacy / Protection settings and press **Update bundles**.
2. Confirm diagnostics show `remoteManifestSignatureVerified=true`.
3. Restart Sumi when the settings state reports that a restart is required.
4. Test `Off`; diagnostics should show no active groups and no bundle work except the explicit update.
5. Test `Protection`; diagnostics should show `generationSource=remoteReleaseBundle`, `activeGroups=trackingNetwork`, `trackingNetworkSource=DuckDuckGo Tracker Radar / TDS`, and `sourceLicense=CC BY-NC-SA 4.0`.
6. Test `Adblock`; diagnostics should show `activeGroups=trackingNetwork,adblockAdsPrivacyNetwork` with empty missing identifiers.
