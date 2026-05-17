# Sumi Native Rule Bundle v1

Sumi Native Rule Bundle v1 is a no-server Adblock data path for WebKit-native content blockers. It moves raw-list conversion out of normal browser runtime:

1. GitHub Actions or a local developer machine fetches selected upstream lists.
2. The local `adblock-rust` adapter converts them to WebKit content-rule JSON.
3. The bundle builder applies Sumi's native CSS white-page safety policy.
4. Safe raw-line and native-JSON duplicate rules are removed.
5. Deterministic `network/` and `nativeCSS/` shards, `manifest.json`, and `diagnostics.json` are written.
6. The app verifies shard hashes, compiles every shard through `WKContentRuleListStore`, and switches the active generation only after all shards compile and can be looked up.

The bundle directory layout is:

```text
SumiAdblockBundle/
  manifest.json
  diagnostics.json
  network/*.json
  nativeCSS/*.json
```

`manifest.json` records the schema version, bundle id, profile id, compiler identity, safety-policy version, source list ids and hashes, shard metadata, unsafe native CSS count, and deduplication summary. The app keeps only metadata, paths, hashes, and identifiers in provider state; full shard JSON is read only for verification and WebKit compilation.

## Local Generation

Use:

```sh
scripts/build_sumi_adblock_bundle.sh --profile currentDefault --output .build/sumi-adblock-bundles
scripts/verify_sumi_adblock_bundle.sh .build/sumi-adblock-bundles/SumiAdblockBundle
```

To build all developer/reference profiles:

```sh
scripts/build_sumi_adblock_bundle.sh --all-profiles --output .build/sumi-adblock-bundles
```

The starting profiles are `currentDefault`, `adguardAdsOnly`, `adguardAdsPrivacy`, and `maximumCustomReference`. They are build-time bundle profiles only and are not exposed as release UI choices.

## Static Update Design

The future no-server update path should stay manual:

1. GitHub Actions generates and verifies bundles weekly or on demand.
2. A GitHub Release asset or GitHub Pages path hosts the static bundle zip.
3. Sumi exposes a manual "Update Adblock data" action.
4. Sumi downloads the bundle, verifies hashes and a signature before use, then compiles shards with WebKit.
5. Sumi keeps the previous generation if download, verification, compilation, lookup, or manifest commit fails.
6. There is no background updater, scheduler, polling loop, custom server, or paid backend.

The current workflow uploads bundles as a GitHub Actions artifact only. Release or Pages publishing should be added only after repository permissions, retention policy, and signing/key handling are decided.
