# CI test ownership

`test-manifest.json` defines the toolchain, profiles, suite roles, package paths,
Xcode schemes, and `-only-testing` selections. `ci_manifest.py` validates those
selections against the synchronized Xcode test targets and emits local and
hosted matrices. `run_tests.sh` executes them without maintaining another
selector list.

Use `scripts/ci/run_tests.sh inventory` for current source, class, method, and
profile counts. Validation requires every runnable `SumiTests` class to have
exactly one exhaustive nightly owner. It also checks method selectors,
extension-contributed tests, target membership, and helper exclusions. UI
coverage is defined by the manifest's explicit selectors.

## Execution

PR and nightly each run two Swift packages and four app shards: pure policy,
persistence, UI-free services, and WebKit-heavy services. Nightly also runs the
UI smoke suite. Package and app matrices are independent and use
`fail-fast: false`; app/UI concurrency is capped at four. Xcode's internal
parallel testing is disabled.

Each Xcode shard uses its own DerivedData and performs `build-for-testing`
followed by selector-scoped `test-without-building`. Build products are not
transferred between runners. Result bundles use these paths:

- `build/BuildResults/<profile>-<suite>-build.xcresult`
- `build/BuildResults/<profile>-<suite>.xcresult`

The performance profile selects subsets of the same suite owners.
`scripts/run_perf_regression.sh` adds profiling mechanics without duplicating
those selectors. Signed release validation in
`scripts/release/run_release_gates.sh` runs full Xcode schemes separately.

## Commands

- `scripts/ci/preflight.sh fast`: text, shell syntax, JSON, and CI contract checks.
- `scripts/ci/preflight.sh portable`: fast checks plus architecture guardrails.
- `scripts/ci/preflight.sh full`: portable checks, toolchain verification, and the PR profile.
- `scripts/ci/run_tests.sh validate`: validate schema, selectors, and ownership.
- `scripts/ci/run_tests.sh inventory`: report the current inventory.
- `scripts/ci/run_tests.sh matrix <profile> <kind>` or `list <profile> [kind]`: inspect selections.
- `scripts/ci/run_tests.sh run <profile> <suite>`: run one shard.
- `scripts/ci/run_tests.sh profile <profile>`: run the profile sequentially.
- `scripts/ci/run_tests.sh verify-toolchain <profile>`: report and verify Xcode and Swift.

`scripts/install_dev_hooks.sh` enables the tracked pre-push hook, which runs
portable preflight. When adding or removing a selected XCTest class or method,
update the manifest in the same change. The manifest remains the authority for
toolchain versions; workflow runner selection must agree with it.
