#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

scan_paths=(
  "Sumi/Managers"
  "Sumi/Models"
  "Sumi/Components"
  "Sumi/Favicons/DDG/SumiDDGFaviconSupport.swift"
  "Vendor/DDG/BrowserServicesKit/Sources/BrowserServicesKit/ContentScopeScript/UserContentController.swift"
)

failed=0

is_allowed() {
  local line="$1"
  case "$line" in
    # BSK controller owns deterministic cleanup and the private per-script removal fallback.
    Vendor/DDG/BrowserServicesKit/Sources/BrowserServicesKit/ContentScopeScript/UserContentController.swift:*removeAllUserScripts*) return 0 ;;
    # Favicon transport observes bounded <link rel=icon> changes and posts a small typed payload.
    Sumi/Favicons/DDG/SumiDDGFaviconSupport.swift:*MutationObserver*) return 0 ;;
    Sumi/Favicons/DDG/SumiDDGFaviconSupport.swift:*setTimeout*) return 0 ;;
    Sumi/Favicons/DDG/SumiDDGFaviconSupport.swift:*JSON.stringify*) return 0 ;;
    # WebExtension bridge compatibility: one-shot lastError/port-open timers, no DOM-frequency native posts.
    Sumi/Managers/ExtensionManager/ExtensionRuntimeResources/externally_connectable_page_bridge.js:*setTimeout*) return 0 ;;
    Sumi/Managers/ExtensionManager/ExtensionManager+ExternallyConnectableNativeMessaging.swift:*setTimeout*) return 0 ;;
    Sumi/Managers/ExtensionManager/ExtensionRuntimeResources/externally_connectable_isolated_bridge.js:*JSON.stringify*) return 0 ;;
    # GM compatibility: caller-provided GM_addElement innerHTML and request-body normalization.
    Sumi/Managers/SumiScripts/UserScriptGMBridge+JSShim.swift:*innerHTML*) return 0 ;;
    Sumi/Managers/SumiScripts/UserScriptGMBridge+JSShim.swift:*JSON.stringify*) return 0 ;;
    # Identity completion and auxiliary surfaces are one-shot callbacks, not injection loops.
    Sumi/Models/Tab/Tab+ScriptMessageHandler.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Models/Tab/Navigation/SumiNavigationHelpers.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Components/MiniWindow/MiniWindowWebView.swift:*evaluateJavaScript*) return 0 ;;
    Sumi/Managers/PeekManager/PeekWebView.swift:*evaluateJavaScript*) return 0 ;;
  esac
  return 1
}

check_pattern() {
  local label="$1"
  local pattern="$2"
  local matches

  matches="$(rg -n --glob '*.swift' --glob '*.js' "$pattern" "${scan_paths[@]}" || true)"
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
check_pattern "high-frequency native event post" "addEventListener\\(['\\\"](?:scroll|mousemove|resize)['\\\"][\\s\\S]{0,240}postMessage"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "userscript hot-path audit passed"
