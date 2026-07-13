# CI test ownership

`test-manifest.json` is the sole authority for CI toolchain intent, profiles,
suite kinds, package paths, Xcode schemes, and `-only-testing` selections.
`ci_manifest.py` validates that schema and emits the fields and matrices used by
GitHub Actions. `run_tests.sh` is the local and hosted executor; it never owns a
suite list.

Test-selection inventory:

- `.github/workflows/sumi-ci.yml` owns PR/push orchestration, build artifacts,
  and timeouts; its suite matrices come from the `pr` manifest profile.
- `.github/workflows/sumi-nightly.yml` owns scheduled orchestration and failure
  artifacts; its suite matrices come from the `nightly` manifest profile.
- `scripts/run_perf_regression.sh` owns profiling/build mechanics, while its
  optimized-stack and UI-smoke selectors come from this manifest.
- `scripts/release/run_alpha_release_gates.sh` intentionally owns signed release
  validation against full Xcode schemes and requires Xcode 27+; it is not a CI
  shard or compatibility lane.
- There are no Make, Just, npm/package-manager, or other `scripts/ci` test
  selection sources.

`macos-26` is a moving GitHub-hosted image. Both CI profiles select its installed
Xcode 26.6 bundle through `DEVELOPER_DIR`; `run_tests.sh verify-toolchain` checks
the active version before tests start.
