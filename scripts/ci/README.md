# CI test ownership

`test-manifest.json` is the sole authority for CI toolchain intent, profiles,
suite roles, package paths, Xcode schemes, and `-only-testing` selections.
`ci_manifest.py` validates that schema against the synchronized Xcode test
target sources and emits every local/hosted matrix. `run_tests.sh` executes one
manifest profile shard or a local sequential aggregate; it owns no selector
list.

## Current inventory

The item 46 migration inventory is:

| Target or profile | Before | After |
| --- | ---: | ---: |
| `SumiTests` Swift sources | 557 | 557 |
| Concrete `SumiTests` XCTest classes | 541 | 541 |
| `SumiTests` test methods | 4,180 | 4,180 |
| Reusable `SumiTests` XCTestCase bases | 3 | 3, excluded from selectors |
| Reusable-base / non-XCTest helper-only sources | 3 / 25 | 3 / 25, reported by validation |
| `SumiUITests` concrete classes / methods | 3 / 36 | 3 / 36 |
| SumiDomain / SumiWebRuntime package tests | 40 / 120 | 40 / 120 |
| PR app selectors / distinct classes | 22 / 20 | 22 / 20 |
| Nightly owned `SumiTests` classes | implicit full scheme | 541 explicit classes |
| Nightly UI selectors | 1 | 1 |

The four exhaustive nightly app roles own 56 pure-policy, 94
persistence/migration, 215 UI-free service, and 176 WebKit-heavy classes.
Those numbers are an inventory snapshot, not guard ceilings: validation always
compares the live repository declarations with the manifest union and requires
each runnable class to have exactly one nightly owner. It also validates every
method selector, extension-contributed test method, synchronized Xcode target
membership, and helper exclusion.

The UI lane intentionally remains the existing launch smoke. The other 35 UI
methods remain the explicit item 48 coverage gap. The known item 49 failure,
`SafariExtensionScriptingRuntimeTests.testWorkerDrivenScriptingInjectionMirrorsProtonBootstrap`,
is not skipped; its class is attributable to the WebKit-heavy shard.

## Process topology

Before item 46, PR used two package matrix jobs serialized with
`max-parallel: 1`, followed by one app job that ran a separate `xcodebuild
build` and one 22-selector `xcodebuild test`. Nightly used two serialized
package jobs followed by serialized `full` and `ui-smoke` jobs. Excluding the
manifest job, that was 3 PR test processes and 4 nightly test processes; app
tests were also prevented from starting by any package failure.

The old PR app job used shared `build/DerivedData` plus
`build/BuildResults/Sumi.xcresult` and
`build/BuildResults/SumiPRSmoke.xcresult`. Nightly used the runner default
DerivedData name in each isolated job and emitted
`SumiNightly-full.xcresult` or `SumiNightly-ui-smoke.xcresult`. Package lanes
invoked `swift test --package-path`; app lanes invoked an app-only build and
then `xcodebuild test` on PR, or a single `xcodebuild test` on nightly.

After item 46:

| Profile | Package jobs | App/UI jobs | Test processes | Hosted concurrency |
| --- | ---: | ---: | ---: | --- |
| PR | 2 | 4 role shards | 6 | 2 package and 4 app jobs may run independently |
| Nightly | 2 | 4 role shards + 1 UI smoke | 7 | packages uncapped; app/UI capped at 4 |

Package and app matrices are independent siblings after manifest validation.
Every matrix has `fail-fast: false`; a failed package or app shard therefore
does not cancel or prevent the others. The app cap of four bounds paid macOS
runner pressure while still providing real multi-process sharding. Swift/Xcode
intra-process parallel testing remains `NO`.

Each Xcode job has fresh runner-local DerivedData and performs
`build-for-testing` followed by selector-scoped `test-without-building`.
DerivedData is never transferred between runners. Matrix-generated paths are
unique per profile and shard:

- `build/BuildResults/<profile>-<suite>-build.xcresult`
- `build/BuildResults/<profile>-<suite>.xcresult`

The non-CI `performance` profile keeps the optimized regression selection as
explicit subsets of the same pure-policy and WebKit-heavy owners. The
performance script aggregates those profile selectors; there is no orphan
performance suite or second ownership list.

## Commands and consumers

- `scripts/ci/run_tests.sh validate` performs strict schema, selector, target
  membership, helper, and exhaustive ownership validation.
- `scripts/ci/run_tests.sh inventory` prints current source/class/method and
  profile/process counts.
- `scripts/ci/run_tests.sh matrix <profile> <kind>` and `list` provide hosted
  and local matrix queries.
- `scripts/ci/run_tests.sh run <profile> <suite>` runs exactly one process
  shard. `profile <profile>` is the local sequential aggregate.
- `scripts/ci/check_test_sharding.sh` is the narrow parser/runner/workflow
  contract guard wired into both CI manifest jobs.
- `scripts/run_perf_regression.sh` owns profiling/build mechanics, while its
  optimized-stack and UI-smoke selectors come from manifest profiles/suites.
- `scripts/release/run_alpha_release_gates.sh` intentionally owns signed
  release validation against full Xcode schemes and requires Xcode 27+; it is
  not a CI shard or compatibility lane.

Both hosted profiles keep SumiDomain and SumiWebRuntime as explicit package
lanes on `macos-26` with Xcode 26.6 selected through `DEVELOPER_DIR`.
