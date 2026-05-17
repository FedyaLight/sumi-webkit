# Sumi Native Rule Bundle v1

`sumi-webkit` is a prepared-bundle consumer only. The browser does not fetch raw filter lists, parse ABP/uBO syntax, invoke `adblock-rust`, or generate WebKit rules at runtime.

The final browser-side flow is intentionally small:

1. A separate bundle-generation repository — planned as `sumi-protection-bundles` — fetches upstream lists outside the browser.
2. GitHub Actions generates and verifies prepared bundles there.
3. `sumi-webkit` accepts a prepared bundle, verifies the manifest, shard hashes, and native-CSS safety policy, compiles shards through `WKContentRuleListStore`, and publishes the new generation only after lookup succeeds.
4. Sumi keeps the previous generation so a failed install or failed smoke lookup can roll back safely.

The bundle directory layout is:

```text
SumiAdblockBundle/
  manifest.json
  diagnostics.json
  network/*.json
  nativeCSS/*.json
```

`manifest.json` records the schema version, bundle id, profile id, compiler identity, safety-policy version, source-list ids and hashes, shard metadata, unsafe native-CSS count, and deduplication summary. The app keeps only metadata, paths, hashes, and identifiers in provider state; full shard JSON is read only for prepared-bundle verification and WebKit compilation.

## Product contract

The browser exposes only three product levels:

- `Off`: no protection groups, no Tracking Protection, no Adblock, no bundle lookup, and no content-rule lists.
- `Protection`: `trackingNetwork` only.
- `Adblock`: `trackingNetwork` plus `adblockAdsPrivacyNetwork`, backed by the prepared `adguardAdsPrivacy` profile.

Native CSS is not a normal product mode. It remains validated only so prepared bundles can be rejected safely if their manifest does not meet the accepted native-CSS safety policy.

## Development bundle import

Until `sumi-protection-bundles` exists, local developer tooling may still create prepared bundles outside the app. Sumi can consume a prepared development bundle from:

```text
.build/sumi-adblock-bundles/adguardAdsPrivacy/SumiAdblockBundle
```

That path is an import/consumption path only. It is not a browser generation path, and Sumi.app does not run the generation scripts.

## Future static update design

The intended static update path stays outside the browser runtime:

1. GitHub Actions in `sumi-protection-bundles` generates and verifies bundles weekly or on demand.
2. A signed GitHub Release asset or static hosting path exposes the prepared bundle.
3. Sumi downloads only the prepared artifact, verifies it, compiles its shards with WebKit, and keeps the previous generation for rollback.
4. Sumi.app never runs `adblock-rust` and never parses raw filter lists.

The current repository keeps any temporary generation scripts as developer tooling only. They must not be referenced by Sumi.app runtime, release UI, or app-target build phases.
