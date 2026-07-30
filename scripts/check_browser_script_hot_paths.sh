#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

scan_paths=(
  "Sumi/Managers"
  "Sumi/Models"
  "Sumi/Components"
  "Sumi/UserScripts"
  "Sumi/Notifications"
  "Sumi/Boosts"
  "Sumi/Utils/WebKit"
  "Sumi/Favicons/V2/SumiFaviconUserScript.swift"
)

failed=0

is_allowed() {
  local line="$1"
  case "$line" in
    # Favicon transport observes bounded <link rel=icon> changes and posts a small typed payload.
    Sumi/Favicons/V2/SumiFaviconUserScript.swift:*MutationObserver*) return 0 ;;
    Sumi/Favicons/V2/SumiFaviconUserScript.swift:*setTimeout*) return 0 ;;
    Sumi/Favicons/V2/SumiFaviconUserScript.swift:*JSON.stringify*) return 0 ;;
    Sumi/Models/Tab/Navigation/SumiNavigationHelpers.swift:*evaluateJavaScript*) return 0 ;;
    # Exact, demand-driven WebKit bridges. None poll or run while idle.
    Sumi/Utils/WebKit/FocusableWKWebView.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Utils/WebKit/SumiElementZapperSession.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Utils/WebKit/SumiReaderModeService.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Utils/WebKit/WebKitTransientChromeInteractionShieldOwner.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Utils/WebKit/WebContentOverlayScrollChrome.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/UserScripts/SumiBackgroundVideoOptimizationSubframeStubUserScript.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Boosts/SumiBoostsModule.swift:*evaluateJavaScript*) return 0 ;;
    # Closing a dedicated normal-tab controller may remove all of its scripts.
    Sumi/UserScripts/SumiNormalTabBrowserServicesKitUserContentControllerAdapter.swift:*removeAllUserScripts*) return 0 ;;
    # Notification dispatch preserves browser EventTarget exception behavior.
    Sumi/Notifications/SumiWebNotificationUserScript.swift:*setTimeout*) return 0 ;;
    # Media timers and observation are installed only after video playback or
    # while a background optimization mode is active.
    Sumi/UserScripts/SumiBackgroundVideoOptimizationUserScript.swift:*setTimeout*) return 0 ;;
    Sumi/UserScripts/SumiBackgroundVideoOptimizationUserScript.swift:*MutationObserver*) return 0 ;;
    # Reader extraction and element-zapper serialization are explicit user actions.
    Sumi/Utils/WebKit/SumiReaderModeService.swift:*innerHTML*) return 0 ;;
    Sumi/Utils/WebKit/SumiElementZapperPageScript.swift:*JSON.stringify*) return 0 ;;
    # Documentation warning, not a DOM write.
    Sumi/Boosts/SumiBoostCSSBuilder.swift:*innerHTML*) return 0 ;;
  esac
  return 1
}

check_pattern() {
  local label="$1"
  local pattern="$2"
  local matches

  matches="$(guard_capture_matches "$pattern" -g '*.swift' -g '*.js' "${scan_paths[@]}")" || return
  [[ -z "$matches" ]] && return

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! is_allowed "$line"; then
      printf 'Disallowed %s: %s\n' "$label" "$line" >&2
      failed=1
    fi
  done <<< "$matches"
}

check_pattern "document-idle/native JS injection" "evaluateJavaScript"
check_pattern "production removeAllUserScripts workaround" "removeAllUserScripts"
check_pattern "setInterval polling" "setInterval"
check_pattern "timer script hot path" "setTimeout"
check_pattern "mutation observer" "MutationObserver"
check_pattern "full DOM snapshot" "outerHTML|innerHTML"
check_pattern "large JSON serialization" "JSON\\.stringify"
check_pattern "high-frequency native event post" "addEventListener\\(['\\\"](scroll|mousemove|resize)['\\\"].{0,240}postMessage"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "browser script hot-path audit passed"
