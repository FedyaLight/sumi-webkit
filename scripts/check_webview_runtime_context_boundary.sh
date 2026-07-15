#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
all_swift_roots=("${production_roots[@]}" SumiTests SumiUITests Packages/SumiWebRuntime)
graph_file="Sumi/Managers/WebViewRuntime/WebViewRuntimeGraph.swift"
browser_manager_file="Sumi/Managers/BrowserManager/BrowserManager.swift"
runtime_composition_file="Sumi/Managers/BrowserManager/BrowserManager+WebViewRuntimeComposition.swift"
runtime_lifecycle_file="Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift"
visible_runtime_provider_file="Sumi/Managers/WebViewRuntime/VisibleWebViewRuntimeProvider.swift"
hidden_clone_eviction_file="Sumi/Managers/WebViewRuntime/HiddenCloneEvictionService.swift"
shutdown_runtime_provider_file="Sumi/Managers/WebViewRuntime/WebViewShutdownRuntimeProvider.swift"
deferred_command_admission_file="Sumi/Managers/WebViewRuntime/DeferredProtectedCommandAdmissionService.swift"
deferred_command_processor_file="Sumi/Managers/WebViewRuntime/DeferredProtectedCommandProcessor.swift"
deferred_executor_live_file="Sumi/Managers/WebViewRuntime/DeferredWebViewCommandExecutor+Live.swift"
window_cleanup_live_file="Sumi/Managers/WebViewRuntime/WebViewWindowCleanupOwner+Live.swift"
replacement_pipeline_file="Sumi/Managers/WebViewRuntime/WebViewReplacementPipeline.swift"
retired_generation_destroyer_file="Sumi/Managers/WebViewRuntime/WebViewRetiredGenerationDestroyer.swift"
committed_tab_retirement_file="Sumi/Managers/WebViewRuntime/WebViewCommittedTabRetirementService.swift"
tab_file="Sumi/Models/Tab/Tab.swift"
main_frame_transaction_file="Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift"
status=0

window_context_file="App/Window/WindowViewContexts.swift"
window_context_composition_file="Sumi/Managers/BrowserManager/BrowserWindowViewContextComposition.swift"
floating_bar_context_file="FloatingBar/FloatingBarBrowserContext.swift"

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

optional_rg() {
  local output
  local scan_status
  if output="$(rg "$@")"; then
    printf '%s\n' "$output"
    return 0
  else
    scan_status=$?
  fi
  if [[ "$scan_status" -eq 1 ]]; then
    return 0
  fi
  printf 'error: rg scan failed with status %s: rg' "$scan_status" >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  return "$scan_status"
}

rg_match_count() {
  local output
  local scan_status
  if output="$(rg --count-matches "$@")"; then
    printf '%s\n' "$output"
    return 0
  else
    scan_status=$?
  fi
  if [[ "$scan_status" -eq 1 ]]; then
    printf '0\n'
    return 0
  fi
  printf 'error: rg count failed with status %s: rg --count-matches' \
    "$scan_status" >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  return "$scan_status"
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
    Sumi/Managers/BrowserManager/BrowserTabManagerRuntimePortsFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserTabRuntimeCompositionService.swift|\
    Sumi/Managers/BrowserManager/BrowserTabSelectionOwner+Live.swift|\
    Sumi/Managers/BrowserManager/TabBrowserRuntimeFactory.swift|\
    Sumi/Managers/BrowserManager/BrowserWebViewCloseRouter.swift|\
    Sumi/Managers/BrowserManager/BrowserWindowViewContextComposition.swift|\
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
  "Sumi/Managers/WebViewRuntime/DeferredProtectedCommandScheduler.swift"
  "Sumi/Managers/BrowserManager/BrowserManagerWebViewRuntimeFactory.swift"
  "Sumi/Managers/BrowserManager/BrowserManagerWebViewCoordinatorRuntimeFactory.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorBrowserRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorInitialDocumentRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorShutdownRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorVisibleRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewCoordinatorWebKitClosePreparation.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewBrowserRuntimeContext.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Context/WebViewRuntimeContextStore.swift"
  "App/Window/WindowViewBrowserContext.swift"
  "Sumi/Managers/BrowserManager/BrowserWindowViewRuntimeWiring.swift"
)
for retired_path in "${retired_paths[@]}"; do
  if [[ -e "$retired_path" ]]; then
    printf 'error: retired WebView/window runtime path reintroduced: %s\n' "$retired_path" >&2
    status=1
  fi
done

for window_context_path in \
  "$window_context_file" \
  "$window_context_composition_file" \
  "$floating_bar_context_file"; do
  if [[ ! -f "$window_context_path" ]]; then
    printf 'error: role-exact window context boundary missing: %s\n' \
      "$window_context_path" >&2
    status=1
  fi
done

if ! rg -q '^final class FloatingBarBrowserContext\b' \
    "$floating_bar_context_file"; then
  printf 'error: stable floating-bar window context missing\n' >&2
  status=1
fi

window_context_roles=(
  WindowWebContentContext
  WindowSidebarContext
  WindowNativeModalContext
  WindowFindContext
  WindowSplitContext
  WindowThemeChromeContext
)
for window_context_role in "${window_context_roles[@]}"; do
  if ! rg -q "^final class ${window_context_role}\\b" "$window_context_file"; then
    printf 'error: exact window context role missing: %s\n' \
      "$window_context_role" >&2
    status=1
  fi
done

window_context_root_hits="$(
  rg -n '\b(BrowserManager|WindowViewBrowserContext)\b' \
    App/Window/WindowView.swift "$window_context_file" || true
)"
fail_matches \
  "window feature contexts reached through the browser root or retired god context" \
  "$window_context_root_hits"

retired_window_context_hits="$(
  rg -n '\bWindowViewBrowserContext\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**' || true
)"
fail_matches \
  "retired all-feature window context was reintroduced" \
  "$retired_window_context_hits"

runtime_role_files=(
  "$visible_runtime_provider_file"
  "$hidden_clone_eviction_file"
  "$shutdown_runtime_provider_file"
  "$deferred_command_admission_file"
  "$deferred_command_processor_file"
  "$deferred_executor_live_file"
  "$window_cleanup_live_file"
  "$retired_generation_destroyer_file"
  "$committed_tab_retirement_file"
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
  "$deferred_command_admission_file:90:5"
  "$deferred_command_processor_file:220:7"
  "$deferred_executor_live_file:90:0"
  "$window_cleanup_live_file:80:0"
  "$retired_generation_destroyer_file:110:1"
  "$committed_tab_retirement_file:90:2"
)
for role_limit in "${role_limits[@]}"; do
  IFS=: read -r role_file max_lines max_collaborators <<< "$role_limit"
  line_count="$(wc -l < "$role_file" | tr -d ' ')"
  if collaborator_count="$(
    rg_match_count '^    private let ' "$role_file"
  )"; then
    :
  else
    exit $?
  fi
  collaborator_count="${collaborator_count:-0}"
  if (( line_count > max_lines || collaborator_count > max_collaborators )); then
    printf 'error: WebView runtime role grew beyond freeze: %s (%s/%s LOC, %s/%s collaborators)\n' \
      "$role_file" "$line_count" "$max_lines" \
      "$collaborator_count" "$max_collaborators" >&2
    status=1
  fi
done

graph_line_count="$(wc -l < "$graph_file" | tr -d ' ')"
lifecycle_line_count="$(wc -l < "$runtime_lifecycle_file" | tr -d ' ')"
if lifecycle_collaborator_count="$(
  rg_match_count '^    private let ' "$runtime_lifecycle_file"
)"; then
  :
else
  exit $?
fi
if (( graph_line_count > 640 )); then
  printf 'error: WebViewRuntimeGraph composition root regrew (%s/640 LOC)\n' \
    "$graph_line_count" >&2
  status=1
fi
if (( lifecycle_line_count > 253 || lifecycle_collaborator_count > 17 )); then
  printf 'error: WebViewLifecycleService regrew (%s/253 LOC, %s/17 collaborators)\n' \
    "$lifecycle_line_count" "$lifecycle_collaborator_count" >&2
  status=1
fi

if rg -n '\b(WebViewRuntimeGraph|WebViewLifecycleService|DeferredWebViewCommandAssembly)\b' \
    "$deferred_executor_live_file" "$window_cleanup_live_file"; then
  printf 'error: deferred-command live composition regained graph/lifecycle reach-through\n' >&2
  status=1
fi

if rg -n '\bDeferredWebViewCommandAssembly\b|lifecycleService\.cleanup(UnprotectedTrackedWebView|Window|AllWebViews)' \
    "$graph_file"; then
  printf 'error: deferred-command execution regained the lifecycle constructor cycle\n' >&2
  status=1
fi

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

if [[ ! -f "$runtime_composition_file" ]]; then
  printf 'error: BrowserManager WebView runtime composition missing: %s\n' \
    "$runtime_composition_file" >&2
  status=1
else
  runtime_composition_body="$(
    sed -n '/^    func composeWebViewRuntime()/,/^    }$/p' \
      "$runtime_composition_file"
  )"
  if ! rg -q '^    func composeWebViewRuntime\(\) -> WebViewRuntimeGraph \{' \
      <<< "$runtime_composition_body" \
      || ! rg -q '^[[:space:]]*WebViewRuntimeGraph\(' \
      <<< "$runtime_composition_body"; then
    printf 'error: BrowserManager root must construct the exact WebViewRuntimeGraph\n' >&2
    status=1
  fi
  exact_composition_inputs=(
    webViewSessions
    resolveRuntimeTab
    resolveCollectionTab
    windowServices
    deferredServices
    visibleContext
    initialDocumentContext
  )
  for exact_composition_input in "${exact_composition_inputs[@]}"; do
    if ! rg -q "^[[:space:]]*${exact_composition_input}:" \
        <<< "$runtime_composition_body"; then
      printf 'error: WebView runtime composition lost exact input: %s\n' \
        "$exact_composition_input" >&2
      status=1
    fi
  done
  if rg -q '\bBrowserWebViewRuntimeFactory\b|^[[:space:]]*for:' \
      <<< "$runtime_composition_body"; then
    printf 'error: WebView runtime composition regained a manager-taking factory\n' >&2
    status=1
  fi
fi

if ! rg -q 'webViewRuntime = composeWebViewRuntime\(\)' "$browser_manager_file" \
    || [[ "$(rg -c '^[[:space:]]*WebViewRuntimeGraph\(' "$runtime_composition_file")" != 1 ]]; then
  printf 'error: BrowserManager root must compose one exact WebView runtime\n' >&2
  status=1
fi
runtime_composition_line_count="$(wc -l < "$runtime_composition_file" | tr -d ' ')"
runtime_composition_call_count="$(
  rg --count-matches '\bcomposeWebViewRuntime\(' "${production_roots[@]}" \
    -g '*.swift' | awk -F: '{ total += $2 } END { print total + 0 }'
)"
if (( runtime_composition_line_count > 265 || runtime_composition_call_count != 2 )); then
  printf 'error: WebView root composition regrew or escaped (%s/265 LOC, %s/2 declaration+call)\n' \
    "$runtime_composition_line_count" "$runtime_composition_call_count" >&2
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
    "$graph_file"|"$runtime_composition_file")
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

retired_generation_destroy_body="$(
  if [[ -f "$retired_generation_destroyer_file" ]]; then
    sed -n '/^    func destroy($/,/^    private func orderedWebViews(/p' \
      "$retired_generation_destroyer_file"
  fi
)"
if ! rg -q 'retiredGenerationDestroyer\.destroy\(' \
    "$replacement_pipeline_file"; then
  printf 'error: replacement pipeline must use the shared retired-generation destroyer\n' >&2
  status=1
elif [[ -z "$retired_generation_destroy_body" ]] \
    || ! rg -q 'runtime\.retireNavigationGeneration\(' \
      <<< "$retired_generation_destroy_body"; then
  printf 'error: retired generations must leave Tab navigation runtime before physical destruction\n' >&2
  status=1
elif [[ "$(rg -n 'runtime\.retireNavigationGeneration\(' <<< "$retired_generation_destroy_body" | cut -d: -f1 | head -1)" -ge \
        "$(rg -n 'runtime\.destroy\(' <<< "$retired_generation_destroy_body" | cut -d: -f1 | head -1)" ]]; then
  printf 'error: retired generation departure must precede every physical destroy\n' >&2
  status=1
fi

if ! rg -q 'navigationTabsByID:' "$committed_tab_retirement_file"; then
  printf 'error: committed Tab retirement must retire the exact model navigation identity\n' >&2
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

# Irreversible retirement is one mandatory typed role. Production supplies a
# concrete authority and tests must choose an explicit participant or the
# fail-closed rejecting fake; independent callback slots and defaults are
# forbidden.
tab_manager_lifecycle_file="Sumi/Managers/TabManager/TabManagerWebViewLifecycleService.swift"
lifecycle_factory_file="Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift"
test_runtime_ports_file="SumiTests/Support/TestRuntimePorts.swift"
for lifecycle_role in \
  TabWebViewAvailabilityParticipant \
  TabWebViewOwnershipParticipant \
  TabWebViewRetirementParticipant \
  TabWebViewProfileTransitionParticipant; do
  if ! rg -q -e "any ${lifecycle_role}" "$tab_manager_lifecycle_file"; then
    printf 'error: Tab lifecycle lost mandatory typed role %s\n' \
      "$lifecycle_role" >&2
    status=1
  fi
done
if rg -q -e 'private let [[:alnum:]_]+: \(' "$tab_manager_lifecycle_file"; then
  printf 'error: Tab lifecycle regained independently injectable callbacks\n' >&2
  status=1
fi
if ! rg -q -e 'retirement: BrowserTabWebViewRetirementParticipant\(' \
  "$lifecycle_factory_file"; then
  printf 'error: production lifecycle lost concrete retirement authority\n' >&2
  status=1
fi
for retirement_operation in \
  canRetire \
  beginCommittedRetirement \
  destroyRetiredGenerations \
  destroyTerminallyDrainedGenerations; do
  for retirement_file in \
    "$tab_manager_lifecycle_file" \
    "$lifecycle_factory_file" \
    "$test_runtime_ports_file"; do
    if ! rg -q -e "func ${retirement_operation}" "$retirement_file"; then
      printf 'error: %s lost typed retirement operation %s\n' \
        "$retirement_file" "$retirement_operation" >&2
      status=1
    fi
  done
done
if rg -U -q -e 'retirement: RetirementCapabilities[[:space:]]*=' \
  "$test_runtime_ports_file"; then
  printf 'error: test lifecycle regained a permissive retirement default\n' >&2
  status=1
fi
if ! rg -q -e 'static let rejecting = Self\(' "$test_runtime_ports_file" \
  || ! rg -q -e 'ClosureTabWebViewRetirementParticipant\(retirement\)' \
    "$test_runtime_ports_file"; then
  printf 'error: tests lost explicit fail-closed retirement composition\n' >&2
  status=1
fi

# Space profile mutation is one staged transaction: no observation-emitting
# convenience setter and no sibling production access to its raw/publish pair.
if rg -q '^[[:space:]]*func assignProfile\(' \
    Sumi/Managers/TabManager/TabSpaceCollectionStateOwner.swift; then
  printf 'error: direct observation-emitting Space profile mutation returned\n' >&2
  status=1
fi
if ! rg -q '^[[:space:]]*private\(set\) var profileId: UUID\?' \
    Sumi/Models/Space/Space.swift; then
  printf 'error: Space.profileId setter escaped its model boundary\n' >&2
  status=1
fi
if space_profile_raw_hits="$(
  optional_rg -n \
    '\.(assignProfileWithoutObservation|publishProfileMutation)\(' \
    Sumi -g '*.swift' \
    -g '!**/SpaceProfileMutationService.swift'
)"; then
  :
else
  exit $?
fi
fail_matches \
  "Space profile raw/publish owner escaped SpaceProfileMutationTransaction" \
  "$space_profile_raw_hits"
if space_model_raw_hits="$(
  optional_rg -n \
    '\.(replaceProfileIDWithoutObservation|publishCurrentProfileID)\(' \
    Sumi -g '*.swift' \
    -g '!**/Space.swift' \
    -g '!**/TabSpaceCollectionStateOwner.swift'
)"; then
  :
else
  exit $?
fi
fail_matches "Space model raw profile mutation escaped its collection owner" \
  "$space_model_raw_hits"

if [[ "$status" -ne 0 ]]; then
  echo "WebView runtime context boundary audit failed" >&2
  exit "$status"
fi

echo "WebView runtime context boundary audit passed"
