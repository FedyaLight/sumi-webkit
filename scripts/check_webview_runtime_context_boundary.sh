#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
all_swift_roots=("${production_roots[@]}" SumiTests SumiUITests Packages/SumiWebRuntime)
graph_file="Sumi/Managers/WebViewRuntime/WebViewRuntimeGraph.swift"
browser_manager_file="Sumi/Managers/BrowserManager/BrowserManager.swift"
runtime_factory_file="Sumi/Managers/BrowserManager/BrowserManagerWebViewRuntimeFactory.swift"
runtime_lifecycle_file="Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift"
visible_runtime_provider_file="Sumi/Managers/WebViewRuntime/VisibleWebViewRuntimeProvider.swift"
hidden_clone_eviction_file="Sumi/Managers/WebViewRuntime/HiddenCloneEvictionService.swift"
shutdown_runtime_provider_file="Sumi/Managers/WebViewRuntime/WebViewShutdownRuntimeProvider.swift"
replacement_pipeline_file="Sumi/Managers/WebViewRuntime/WebViewReplacementPipeline.swift"
tab_file="Sumi/Models/Tab/Tab.swift"
main_frame_transaction_file="Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift"
status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

is_allowed_web_view_runtime_access() {
  local candidate="$1"
  case "$candidate" in
    App/SumiApp.swift|\
    Sumi/Managers/BrowserManager/BrowserAuxiliaryWindowCompositionFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserBoostRuntimeFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserExtensionBridgeComposition.swift|\
    Sumi/Managers/BrowserManager/BrowserExtensionManagerRuntimeFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserGlanceRuntimeService.swift|\
    Sumi/Managers/BrowserManager/BrowserManager.swift|\
    Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift|\
    Sumi/Managers/BrowserManager/BrowserTabCompositorRuntimeWiring.swift|\
    Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserTabRuntimeCompositionService.swift|\
    Sumi/Managers/BrowserManager/BrowserTabSelectionOwner+Live.swift|\
    Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserWebViewCloseRouter.swift|\
    Sumi/Managers/BrowserManager/BrowserWindowViewRuntimeWiring.swift|\
    Sumi/Managers/BrowserManager/TabBrowserNavigationRuntimeFactory.swift|\
    Sumi/Managers/BrowserManager/TabBrowserWebViewRuntimeFactory.swift)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ ! -f "$graph_file" ]]; then
  printf 'error: canonical WebView runtime graph missing: %s\n' "$graph_file" >&2
  status=1
fi

# Physical and symbolic tombstones keep the retired coordinator architecture
# from returning under a stale path or through one of its old context types.
retired_paths=(
  "Sumi/Managers/WebViewCoordinator"
  "Sumi/Managers/WebViewRuntime/WebViewCoordinator.swift"
  "Sumi/Managers/WebViewRuntime/WebViewRuntimeAssembler.swift"
  "Sumi/Managers/BrowserManager/BrowserManagerWebViewCoordinatorRuntimeFactory.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorBrowserRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorInitialDocumentRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorShutdownRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorVisibleRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorWebKitClosePreparation.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewBrowserRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewRuntimeContextStore.swift"
)
for retired_path in "${retired_paths[@]}"; do
  if [[ -e "$retired_path" ]]; then
    printf 'error: retired WebView coordinator path reintroduced: %s\n' "$retired_path" >&2
    status=1
  fi
done

runtime_role_files=(
  "$visible_runtime_provider_file"
  "$hidden_clone_eviction_file"
  "$shutdown_runtime_provider_file"
)
for role_file in "${runtime_role_files[@]}"; do
  if [[ ! -f "$role_file" ]]; then
    printf 'error: role-exact WebView runtime layer missing: %s\n' "$role_file" >&2
    status=1
  fi
done

if rg -q '\bWebViewRuntimeAssembler\b|\bruntimeAssembler\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'; then
  printf 'error: retired multi-role WebViewRuntimeAssembler reintroduced\n' >&2
  status=1
fi

role_limits=(
  "$visible_runtime_provider_file:55:3"
  "$hidden_clone_eviction_file:55:4"
  "$shutdown_runtime_provider_file:20:1"
)
for role_limit in "${role_limits[@]}"; do
  IFS=: read -r role_file max_lines max_collaborators <<< "$role_limit"
  line_count="$(wc -l < "$role_file" | tr -d ' ')"
  collaborator_count="$(rg --count-matches '^    private let ' "$role_file" || true)"
  collaborator_count="${collaborator_count:-0}"
  if (( line_count > max_lines || collaborator_count > max_collaborators )); then
    printf 'error: WebView runtime role grew beyond freeze: %s (%s/%s LOC, %s/%s collaborators)\n' \
      "$role_file" "$line_count" "$max_lines" \
      "$collaborator_count" "$max_collaborators" >&2
    status=1
  fi
done

legacy_coordinator_hits="$(
  rg -n '\bWebViewCoordinator\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "retired WebViewCoordinator type reintroduced" "$legacy_coordinator_hits"

legacy_context_hits="$(
  rg -n '\bWebViewCoordinator[A-Za-z0-9_]*RuntimeContext\b|\bWebViewCoordinatorWebKitClosePreparation\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "coordinator-prefixed WebView runtime context reintroduced" "$legacy_context_hits"

retired_god_context_hits="$(
  rg -n '\b(WebViewBrowserRuntimeContext|WebViewRuntimeContextStore|WebViewRuntimeEnvironment|runtimeContextStore)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "retired WebView runtime god context/store reintroduced" "$retired_god_context_hits"

if [[ ! -f "$runtime_factory_file" ]]; then
  printf 'error: exact WebView runtime factory missing: %s\n' "$runtime_factory_file" >&2
  status=1
else
  factory_make_body="$(
    sed -n '/^    static func make(/,/^    }$/p' "$runtime_factory_file"
  )"
  if ! rg -q '^    static func make\(' <<< "$factory_make_body" \
      || ! rg -q '\) -> WebViewRuntimeGraph \{' <<< "$factory_make_body" \
      || ! rg -q '^[[:space:]]*WebViewRuntimeGraph\(' <<< "$factory_make_body"; then
    printf 'error: BrowserWebViewRuntimeFactory.make must construct the exact WebViewRuntimeGraph\n' >&2
    status=1
  fi
fi

if ! rg -q 'BrowserWebViewRuntimeFactory\.make\(' "$browser_manager_file"; then
  printf 'error: BrowserManager must construct its WebView runtime through BrowserWebViewRuntimeFactory.make\n' >&2
  status=1
fi

# The graph is composition storage, not a feature dependency. Production code
# can name its concrete type only where it is declared and where BrowserManager
# creates it. Tests may construct the graph explicitly.
graph_reference_hits="$(
  rg -n '\bWebViewRuntimeGraph\b' \
    "${production_roots[@]}" Packages/SumiWebRuntime/Sources \
    -g '*.swift' -g '!**/.build/**' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    "$graph_file"|"$runtime_factory_file")
      ;;
    *)
      printf 'error: WebViewRuntimeGraph escaped composition storage: %s\n' "$match" >&2
      status=1
      ;;
  esac
done <<< "$graph_reference_hits"

# Concrete graph access is limited to explicit composition edges that extract
# one or more narrow services for downstream feature code.
graph_access_hits="$(
  rg -n '\.webViewRuntime\b' \
    "${production_roots[@]}" -g '*.swift' || true
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if ! is_allowed_web_view_runtime_access "$file"; then
    printf 'error: WebView runtime graph accessed outside an approved composition edge: %s\n' \
      "$match" >&2
    status=1
  fi
done <<< "$graph_access_hits"

legacy_partial_context_hits="$(
  rg -n '\b(attach|detach)(BrowserRuntimeContext|InitialDocumentRuntimeContext|ShutdownRuntimeContext|VisiblePreparationRuntimeContext)\s*\(' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "partial WebView runtime context attachment reintroduced" "$legacy_partial_context_hits"

lifecycle_shutdown_body="$(
  if [[ -f "$runtime_lifecycle_file" ]]; then
    sed -n '/^    func cleanupAfterBrowserRuntimeDeallocation()/,/^    }$/p' \
      "$runtime_lifecycle_file"
  fi
)"
if [[ -z "$lifecycle_shutdown_body" ]] \
    || ! rg -q 'replacementPipeline\.resetForTerminalShutdown\(\)' \
      <<< "$lifecycle_shutdown_body"; then
  printf 'error: WebViewLifecycleService terminal cleanup must reset the replacement pipeline\n' >&2
  status=1
fi

replacement_reset_body="$(
  if [[ -f "$replacement_pipeline_file" ]]; then
    sed -n '/^    func resetForTerminalShutdown()/,/^    }$/p' \
      "$replacement_pipeline_file"
  fi
)"
if [[ -z "$replacement_reset_body" ]] \
    || ! rg -q 'settlementService\.resetForTerminalShutdown\(\)' \
      <<< "$replacement_reset_body"; then
  printf 'error: WebViewReplacementPipeline terminal reset must reach settlement service\n' >&2
  status=1
fi

replacement_destroy_body="$(
  if [[ -f "$replacement_pipeline_file" ]]; then
    sed -n '/^    private static func destroy(/,/^    private static func preferredWebView(/p' \
      "$replacement_pipeline_file"
  fi
)"
if [[ -z "$replacement_destroy_body" ]] \
    || ! rg -q 'runtime\.retireNavigationGeneration\(' \
      <<< "$replacement_destroy_body"; then
  printf 'error: replacement generations must leave Tab navigation runtime before physical destruction\n' >&2
  status=1
elif [[ "$(rg -n 'runtime\.retireNavigationGeneration\(' <<< "$replacement_destroy_body" | cut -d: -f1 | head -1)" -ge \
        "$(rg -n 'runtime\.destroy\(' <<< "$replacement_destroy_body" | cut -d: -f1 | head -1)" ]]; then
  printf 'error: replacement generation departure must precede every physical destroy\n' >&2
  status=1
fi

if ! rg -q 'tab\.webViewsDidLeaveNavigationRuntime\(' "$graph_file"; then
  printf 'error: replacement pipeline generation departure must reach the exact Tab runtime\n' >&2
  status=1
fi

tab_batch_departure_body="$(
  if [[ -f "$tab_file" ]]; then
    sed -n '/^    func webViewsDidLeaveNavigationRuntime(/,/^    }$/p' "$tab_file"
  fi
)"
if [[ -z "$tab_batch_departure_body" ]] \
    || ! rg -q 'mainFrameRuntimeTransaction\.webViewsDidLeaveRuntime\(' \
      <<< "$tab_batch_departure_body" \
    || ! rg -q 'TabMainFrameLifecycleReducer\.replayIfNeeded\(' \
      <<< "$tab_batch_departure_body"; then
  printf 'error: Tab replacement departure must reduce a whole generation and replay once\n' >&2
  status=1
fi

transaction_batch_departure_body="$(
  if [[ -f "$main_frame_transaction_file" ]]; then
    sed -n '/^    func webViewsDidLeaveRuntime(/,/^    func beginRecovery(/p' \
      "$main_frame_transaction_file"
  fi
)"
if [[ -z "$transaction_batch_departure_body" ]] \
    || ! rg -q 'committedDocumentRuntime\.performTransition\(' \
      <<< "$transaction_batch_departure_body" \
    || ! rg -q 'committedDocumentRuntime\.removeWebViews\(' \
      <<< "$transaction_batch_departure_body" \
    || ! rg -q 'mainFrameLoads\.departure\(of: departingWebViews\)' \
      <<< "$transaction_batch_departure_body" \
    || ! rg -q 'lifecycle\.departure\(' \
      <<< "$transaction_batch_departure_body"; then
  printf 'error: main-frame replacement departure must batch every authority store\n' >&2
  status=1
fi

# The graph may store and lazily construct dependencies, but behavior belongs
# to the concrete services. Static, file-private assembly helpers are allowed.
graph_instance_behavior_hits="$(
  if [[ -f "$graph_file" ]]; then
    rg -n '^    ((private|fileprivate|internal|public)[[:space:]]+)?(mutating[[:space:]]+)?func\b' \
      "$graph_file" || true
  fi
)"
fail_matches "WebView runtime graph gained instance behavior" "$graph_instance_behavior_hits"

graph_observation_hits="$(
  if [[ -f "$graph_file" ]]; then
    rg -n '^import Observation$|@(Observable|ObservationIgnored)\b|:\s*ObservableObject\b' \
      "$graph_file" || true
  fi
)"
fail_matches "WebView runtime graph became observable UI state" "$graph_observation_hits"

swiftui_environment_hits="$(
  rg -n -U \
    '@(Environment|EnvironmentObject)\b[^\n]*\bWebViewRuntimeGraph\b|\.environment(Object)?\s*\([^)]*\bwebViewRuntime\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches "WebView runtime graph injected through SwiftUI Environment" "$swiftui_environment_hits"

if [[ "$status" -ne 0 ]]; then
  echo "WebView runtime context boundary audit failed" >&2
  exit "$status"
fi

echo "WebView runtime context boundary audit passed"
