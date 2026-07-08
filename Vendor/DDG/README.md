DDG vendored snapshot
=====================

This directory contains an in-repo snapshot of one DuckDuckGo
(DuckDuckGo/apple-browsers) Swift package used by Sumi:

- `BrowserServicesKit` — provides the `Navigation` library product (the
  `DistributedNavigationDelegate` WebKit navigation pipeline) and its
  `Common` support target.

The package is intentionally vendored inside the Sumi repository so the app
does not depend on a local `../references` checkout at build time.

Everything else that was once vendored here has been replaced by Sumi-owned
code:

- `Bookmarks`/`Persistence` were ported into the app target
  (`Sumi/Bookmarks/Store/`, `Sumi/Common/Database/SumiPersistentContainerDatabase.swift`);
  see `docs/permissions/LICENSE_NOTES.md` for the Apache 2.0 attribution map.
- `PrivacyConfig` was replaced by `Sumi/Privacy/SumiPrivacyConfiguration.swift`.
- `URLPredictor` (a prebuilt Rust xcframework) was replaced by native Swift
  implementations: `SumiAddressBarClassifier`, `SumiPunycode`, and
  `SumiPublicSuffixList` over the bundled `Sumi/Resources/public_suffix_list.dat`.
  No binary bootstrap step is required anymore.

Provenance
----------

Source repository: https://github.com/duckduckgo/apple-browsers
Source revision (Swift snapshot): 7360a348cc6bc0f06173d35dd59905ae165780c6

The snapshot is consumed exclusively through the `Navigation` library product;
the app never imports the umbrella `BrowserServicesKit` module or `Common`
directly. All app-side integration points are isolated in adapter files named
with the `*+BrowserServicesKit*` convention under `Sumi/Models/Tab/Navigation/`.

Upstream test trees are not vendored. Run the boundary guard when changing the
vendored package, schemes, or test wiring:

    bash scripts/check_ddg_vendor_test_boundary.sh

Upgrading
---------

Because the snapshot is vendored (not a git submodule), an upstream re-sync
must produce a reviewable repository diff. Use the workflow script from a
clean Sumi worktree:

    bash scripts/sync_ddg_vendor_snapshot.sh \
      --source ../references/apple-browsers \
      --ref <duckduckgo/apple-browsers commit>

The script synchronizes only the `Common` and `Navigation` source targets,
preserves Sumi's pruned `Package.swift` manifest, prunes the `Common/TLD`
component (removed in Sumi along with its URLPredictor dependency), rewrites
the Swift snapshot revision above, and runs the DDG test-boundary guard. Use
`--dry-run` first when auditing a large upstream jump.
