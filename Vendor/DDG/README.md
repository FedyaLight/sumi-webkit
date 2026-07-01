DDG vendored snapshot
=====================

This directory contains in-repo snapshots of two DuckDuckGo (DuckDuckGo/apple-browsers)
Swift packages used by Sumi:

- `BrowserServicesKit` — provides the `Bookmarks`, `Navigation`, `Persistence`, and
  `PrivacyConfig` library products.
- `URLPredictor` — provides the `URLPredictor` library product, which wraps a
  prebuilt Rust static library (`URLPredictorRust.xcframework`).

These packages are intentionally vendored inside the Sumi repository so the app
does not depend on a local `../references` checkout at build time.

Provenance
----------

Source repository: https://github.com/duckduckgo/apple-browsers
Source revision (Swift snapshot): 7360a348cc6bc0f06173d35dd59905ae165780c6

The snapshot is consumed exclusively through the five library products listed
above; the app never imports the umbrella `BrowserServicesKit` module directly.
All app-side integration points are isolated in adapter files named with the
`SumiDDG*` or `*+BrowserServicesKit*` convention (e.g.
`Sumi/Bookmarks/SumiDDGBookmarkRepository.swift`,
`Sumi/Common/Database/SumiDDGCoreDataDatabase.swift`).

The Rust static library (`liburl_predictor.a`) is a prebuilt release artifact
from https://github.com/duckduckgo/url_predictor — pinned to release `0.3.13` in
`scripts/bootstrap_vendor_binaries.sh`, which downloads the xcframework zip and
verifies its archive checksum before unpacking.

Binary integrity
----------------

Only the unpacked `URLPredictor/Binary/URLPredictorRust.xcframework/` is ignored
by version control (see `.gitignore`); the xcframework is materialized locally by
`scripts/bootstrap_vendor_binaries.sh`.
Reference SHA-256 digests for the unpacked slices (plus the xcframework
`Info.plist`) are recorded in `URLPredictor/Binary/CHECKSUMS.sha256` and can be
verified after bootstrap with:

    bash scripts/verify_vendor_checksums.sh

This complements the archive-level checksum in `bootstrap_vendor_binaries.sh` by
guarding against drift in the unpacked tree (e.g. a partial re-extract or a
locally edited slice). `CHECKSUMS.sha256` is tracked so this verification works
after a clean checkout. If `url_predictor` is upgraded, re-run bootstrap and
regenerate `CHECKSUMS.sha256` from the freshly unpacked files.

Upstream tests
--------------

The DDG test files checked in under this directory are upstream reference
material, not Sumi coverage. They are quarantined in place so the source
snapshot remains auditable without implying that Sumi's Xcode schemes execute
those tests.

Sumi's active test gates are the shared `Sumi` and `SumiSmoke` schemes, which
run `SumiTests` and `SumiUITests` respectively. See `UPSTREAM_TESTS.md` for the
full boundary and run the guard below when changing DDG packages, schemes, or
test wiring:

    bash scripts/check_ddg_vendor_test_boundary.sh

Upgrading
---------

Because the snapshot is vendored (not a git submodule), an upstream re-sync is a
manual copy. The `BrowserServicesKit` Swift sources have no local divergence, so
they rebase cleanly. After any re-sync, regenerate `CHECKSUMS.sha256` and confirm
the five linked products still resolve. If upstream tests are refreshed, keep
their quarantine markers and rerun the boundary guard.
