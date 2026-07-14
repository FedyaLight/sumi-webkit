#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CI_TEST_RUNNER="$ROOT/scripts/ci/run_tests.sh"
PROJECT="${SUMI_XCODE_PROJECT:-$ROOT/$("$CI_TEST_RUNNER" xcode-field project)}"
PERFORMANCE_PROFILE="performance"
PERFORMANCE_SUITE="$("$CI_TEST_RUNNER" list "$PERFORMANCE_PROFILE" xcode-test | sed -n '1p')"
SCHEME="${SUMI_SCHEME:-$("$CI_TEST_RUNNER" suite-field "$PERFORMANCE_SUITE" scheme)}"
DESTINATION="${SUMI_XCODE_DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA="${SUMI_PERF_DERIVED_DATA:-$ROOT/.build/performance/perf-derived-data}"
TRACE_DIR="${SUMI_PERF_TRACE_DIR:-$ROOT/.build/profiles}"
TIME_LIMIT="${SUMI_PERF_TIME_LIMIT:-90s}"

usage() {
  cat <<USAGE
Usage:
  scripts/run_perf_regression.sh verify
  scripts/run_perf_regression.sh trace <xctrace-template> <scenario-name>
  scripts/run_perf_regression.sh ui-smoke

Environment:
  SUMI_PERF_DERIVED_DATA   DerivedData path (default: .build/performance/perf-derived-data)
  SUMI_PERF_TRACE_DIR      Trace output dir (default: .build/profiles)
  SUMI_PERF_TIME_LIMIT     xctrace time limit (default: 90s)
  SUMI_APP_SUPPORT_OVERRIDE Optional app support fixture passed to xctrace with --env
USAGE
}

run_xcodebuild() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    "$@" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
}

build_configuration() {
  local configuration="$1"
  echo "==> Building $SCHEME $configuration (unsigned)"
  run_xcodebuild -configuration "$configuration" build
}

verify() {
  local -a optimized_stack_tests=()
  local suite
  local selector_output
  while IFS= read -r suite; do
    selector_output="$("$CI_TEST_RUNNER" selectors "$suite" "$PERFORMANCE_PROFILE")"
    while IFS= read -r selector; do
      [[ -n "$selector" ]] && optimized_stack_tests+=("-only-testing:$selector")
    done <<< "$selector_output"
  done <<< "$("$CI_TEST_RUNNER" list "$PERFORMANCE_PROFILE" xcode-test)"

  mkdir -p "$DERIVED_DATA"
  build_configuration Debug
  build_configuration Release

  echo "==> Running optimized-stack regression tests"
  run_xcodebuild "${optimized_stack_tests[@]}" test
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '-' \
    | sed 's/^-//; s/-$//'
}

trace() {
  local template="${1:-}"
  local scenario="${2:-}"

  if [[ -z "$template" || -z "$scenario" ]]; then
    usage
    exit 2
  fi

  mkdir -p "$TRACE_DIR" "$DERIVED_DATA"
  build_configuration Release

  local app="$DERIVED_DATA/Build/Products/Release/Sumi.app"
  local timestamp
  local template_slug
  local scenario_slug
  timestamp="$(date +%Y%m%d-%H%M%S)"
  template_slug="$(slugify "$template")"
  scenario_slug="$(slugify "$scenario")"
  local output="$TRACE_DIR/${timestamp}-${scenario_slug}-${template_slug}.trace"

  echo "==> Recording $template for scenario '$scenario'"
  echo "==> Output: $output"
  echo "==> Drive the scenario manually while recording; filter signposts by subsystem com.sumi.browser and category PerformanceTrace."

  local -a env_args=()
  if [[ -n "${SUMI_APP_SUPPORT_OVERRIDE:-}" ]]; then
    env_args+=(--env "SUMI_APP_SUPPORT_OVERRIDE=$SUMI_APP_SUPPORT_OVERRIDE")
  fi

  xcrun xctrace record \
    --template "$template" \
    --instrument os_signpost \
    --time-limit "$TIME_LIMIT" \
    --output "$output" \
    "${env_args[@]}" \
    --launch -- "$app"
}

ui_smoke() {
  local scheme
  local -a selectors=()
  local selector_output
  scheme="$("$CI_TEST_RUNNER" suite-field ui-smoke scheme)"
  selector_output="$("$CI_TEST_RUNNER" selectors ui-smoke)"
  while IFS= read -r selector; do
    [[ -n "$selector" ]] && selectors+=("-only-testing:$selector")
  done <<< "$selector_output"

  echo "==> Running cheap launch UI smoke through SumiSmoke"
  echo "==> Requires local macOS UI automation permissions; this is intentionally outside the verify gate"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$scheme" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA-smoke" \
    "${selectors[@]}" \
    test \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
}

case "${1:-}" in
  verify)
    verify
    ;;
  trace)
    shift
    trace "$@"
    ;;
  ui-smoke)
    ui_smoke
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
