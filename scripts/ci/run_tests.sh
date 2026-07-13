#!/usr/bin/env bash
# Manifest-backed local and hosted CI test entrypoint.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest_tool="$repo_root/scripts/ci/ci_manifest.py"
manifest_path="${SUMI_CI_TEST_MANIFEST:-$repo_root/scripts/ci/test-manifest.json}"
cd "$repo_root"

manifest() {
  python3 "$manifest_tool" \
    --repo-root "$repo_root" \
    --manifest "$manifest_path" \
    "$@"
}

usage() {
  cat <<USAGE
Usage:
  scripts/ci/run_tests.sh validate
  scripts/ci/run_tests.sh run <suite-id>
  scripts/ci/run_tests.sh profile <profile-id> [suite-kind]
  scripts/ci/run_tests.sh matrix <profile-id> [suite-kind]
  scripts/ci/run_tests.sh list <profile-id> [suite-kind]
  scripts/ci/run_tests.sh verify-toolchain <profile-id>
  scripts/ci/run_tests.sh suite-field <suite-id> <field>
  scripts/ci/run_tests.sh selectors <suite-id>
  scripts/ci/run_tests.sh toolchain-field <profile-id> <field>
  scripts/ci/run_tests.sh xcode-field <field>

Environment:
  SUMI_CI_TEST_MANIFEST  Manifest override (primarily for parser tests)
  SUMI_CI_DERIVED_DATA  DerivedData path
  SUMI_CI_RESULT_BUNDLE .xcresult output path
USAGE
}

run_xcode_suite() {
  local suite="$1"
  local project="${SUMI_XCODE_PROJECT:-$(manifest xcode-field project)}"
  local destination="${SUMI_XCODE_DESTINATION:-$(manifest xcode-field destination)}"
  local parallel_testing
  local scheme
  local configuration
  local derived_data="${SUMI_CI_DERIVED_DATA:-$repo_root/build/ci-derived-data}"
  local result_bundle="${SUMI_CI_RESULT_BUNDLE:-$repo_root/build/BuildResults/${suite}.xcresult}"
  local -a selectors=()
  local selector_output

  parallel_testing="$(manifest xcode-field parallel_testing_enabled)"
  scheme="$(manifest suite-field "$suite" scheme)"
  configuration="$(manifest suite-field "$suite" configuration)"
  selector_output="$(manifest selectors "$suite")"
  while IFS= read -r selector; do
    [[ -n "$selector" ]] && selectors+=("-only-testing:$selector")
  done <<< "$selector_output"

  mkdir -p "$(dirname "$result_bundle")" "$derived_data"
  rm -rf "$result_bundle"
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled "$parallel_testing" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "${selectors[@]}" \
    test
}

run_suite() {
  local suite="$1"
  local kind
  local name
  kind="$(manifest suite-field "$suite" kind)"
  name="$(manifest suite-field "$suite" name)"
  echo "==> $name [$suite]"

  case "$kind" in
    swift-package)
      swift test --package-path "$repo_root/$(manifest suite-field "$suite" path)"
      ;;
    xcode-test)
      run_xcode_suite "$suite"
      ;;
    *)
      echo "error: validated manifest returned unsupported suite kind: $kind" >&2
      exit 2
      ;;
  esac
  echo "==> $name passed"
}

run_profile() {
  local profile="$1"
  local kind="${2:-}"
  local -a query=(list "$profile")
  local suite_output
  [[ -n "$kind" ]] && query+=("$kind")
  suite_output="$(manifest "${query[@]}")"
  while IFS= read -r suite; do
    [[ -n "$suite" ]] && run_suite "$suite"
  done <<< "$suite_output"
}

verify_toolchain() {
  local profile="$1"
  local expected_version
  local actual_version
  expected_version="$(manifest toolchain-field "$profile" xcode_version)"
  actual_version="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
  if [[ "$actual_version" != "$expected_version" ]]; then
    echo "error: profile $profile requires Xcode $expected_version; active version is ${actual_version:-unknown}" >&2
    exit 1
  fi
  xcodebuild -version
  swift --version
  xcodebuild -showsdks | sed -n '/macOS SDKs:/,/iOS SDKs:/p'
}

command="${1:-}"
case "$command" in
  validate)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    manifest validate
    ;;
  run)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    run_suite "$2"
    ;;
  profile)
    [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }
    run_profile "$2" "${3:-}"
    ;;
  verify-toolchain)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    verify_toolchain "$2"
    ;;
  matrix|list)
    [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }
    manifest "$@"
    ;;
  suite-field|toolchain-field)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    manifest "$@"
    ;;
  selectors|xcode-field)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    manifest "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
