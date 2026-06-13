#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Sumi"
BUNDLE_ID="com.sumi.browser"
PROJECT="Sumi.xcodeproj"
SCHEME="Sumi"
CONFIGURATION="Debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

stop_app() {
  local pids
  pids="$(pgrep -x "$APP_NAME" || true)"
  if [[ -n "$pids" ]]; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
    done <<<"$pids"
  fi
}

build_app() {
  xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

open_app() {
  local open_args=(-n "$APP_BUNDLE")
  if [[ -n "${SUMI_APP_SUPPORT_OVERRIDE:-}" ]]; then
    open_args=(--env "SUMI_APP_SUPPORT_OVERRIDE=$SUMI_APP_SUPPORT_OVERRIDE" "${open_args[@]}")
  fi
  /usr/bin/open "${open_args[@]}"
}

cd "$ROOT_DIR"
stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
