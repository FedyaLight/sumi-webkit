#!/usr/bin/env bash
# Unified CI test entrypoint (architecture 72→100 plan B0/B7).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

PROJECT="${SUMI_XCODE_PROJECT:-Sumi.xcodeproj}"
SCHEME="${SUMI_SCHEME:-Sumi}"
DESTINATION="${SUMI_XCODE_DESTINATION:-platform=macOS}"
DERIVED_DATA="${SUMI_CI_DERIVED_DATA:-$repo_root/build/ci-derived-data}"
RESULT_BUNDLE="${SUMI_CI_RESULT_BUNDLE:-$repo_root/build/BuildResults/SumiTests.xcresult}"

# PR smoke: architecture-sensitive subset (not full ~106k LOC SumiTests).
PR_SMOKE_TESTS=(
  "-only-testing:SumiTests/TabManagerStructuralPersistenceTests"
  "-only-testing:SumiTests/TabManagerStructuralBatchingTests"
  "-only-testing:SumiTests/TabStructureEventBusTests"
  "-only-testing:SumiTests/RuntimeStateCoalescerTests"
  "-only-testing:SumiTests/BrowserManagerRuntimeWiringTests"
  "-only-testing:SumiTests/BrowserManagerLifecycleWiringTests"
  "-only-testing:SumiTests/SumiPerformanceModularRegressionTests/testBrowserManagerStartupAndSettingsSurfacesDoNotConstructDisabledRuntimes"
  "-only-testing:SumiTests/SumiPerformanceModularRegressionTests/testEnablingOptionalModuleAfterStartupAttachesRuntime"
  "-only-testing:SumiTests/SumiPerformanceModularRegressionTests/testDefaultNormalTabAttachesOnlyCoreRuntimeAndNoOptionalModuleAssets"
  "-only-testing:SumiTests/BrowserSidebarCommandRoutingOwnerTests"
  "-only-testing:SumiTests/BrowserSidebarActionOwnerTests"
  "-only-testing:SumiTests/SidebarRegularTabsControllerTests"
  "-only-testing:SumiTests/SidebarSpaceBodyInjectionRegressionTests"
  "-only-testing:SumiTests/TabWebViewMaterializationAndRebuildTests"
  "-only-testing:SumiTests/DeferredProtectedCommandTests"
  "-only-testing:SumiTests/InitialDocumentRuntimeHandoffTests"
  "-only-testing:SumiTests/GlanceManagerTests"
  "-only-testing:SumiTests/BrowserShortcutPinUnloadOwnerTests"
)

usage() {
  cat <<USAGE
Usage:
  scripts/ci/run_tests.sh packages
  scripts/ci/run_tests.sh pr-smoke
  scripts/ci/run_tests.sh full
  scripts/ci/run_tests.sh ui-smoke
  scripts/ci/run_tests.sh domain

Environment:
  SUMI_CI_DERIVED_DATA   DerivedData path
  SUMI_CI_RESULT_BUNDLE  .xcresult output path
USAGE
}

run_xcodebuild() {
  mkdir -p "$(dirname "$RESULT_BUNDLE")" "$DERIVED_DATA"
  rm -rf "$RESULT_BUNDLE"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "$@"
}

run_architecture_packages() {
  swift test --package-path Packages/SumiDomain
  swift test --package-path Packages/SumiWebRuntime
}

cmd="${1:-}"
case "$cmd" in
  packages)
    run_architecture_packages
    ;;
  domain)
    swift test --package-path Packages/SumiDomain
    ;;
  pr-smoke)
    echo "==> Architecture package tests"
    run_architecture_packages
    echo "==> Sumi PR smoke unit tests"
    run_xcodebuild "${PR_SMOKE_TESTS[@]}" test
    ;;
  full)
    echo "==> Full Sumi unit tests"
    run_xcodebuild test
    ;;
  ui-smoke)
    echo "==> UI launch smoke"
    run_xcodebuild \
      -scheme SumiSmoke \
      -only-testing:SumiUITests/SumiLaunchSmokeUITests/testLaunchesMainWindow \
      test
    ;;
  *)
    usage
    exit 2
    ;;
esac

echo "ci run_tests.sh $cmd passed"
