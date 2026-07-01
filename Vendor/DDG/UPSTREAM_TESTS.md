DDG upstream test quarantine
============================

The DDG test tree is vendored reference material. It must not be counted as
Sumi coverage unless a Sumi-owned target, scheme, and CI gate intentionally
adopt those tests.

Reference-only test roots
-------------------------

- `Vendor/DDG/BrowserServicesKit/Tests`
- `Vendor/DDG/URLPredictor/Sources/URLPredictorTests`

These files are kept to preserve upstream context for future DDG re-syncs and
manual comparison. They are not evidence that Sumi exercises the same behavior.

Active Sumi gates
-----------------

- `Sumi.xcodeproj/xcshareddata/xcschemes/Sumi.xcscheme` runs `SumiTests`.
- `Sumi.xcodeproj/xcshareddata/xcschemes/SumiSmoke.xcscheme` runs
  `SumiUITests`.

The app links only these DDG library products from the Xcode project:

- `Bookmarks`
- `Navigation`
- `Persistence`
- `PrivacyConfig`
- `URLPredictor`

Boundary guard
--------------

Run this before treating DDG test files as active coverage or after changing
DDG package manifests, Sumi schemes, or project test wiring:

    bash scripts/check_ddg_vendor_test_boundary.sh

The guard verifies that the upstream test roots still have quarantine
documentation and that Sumi shared schemes do not reference DDG test targets.
If a future change intentionally promotes any upstream DDG tests into Sumi
coverage, update this document, the guard allowlist, and the relevant CI/test
gate in the same change.
