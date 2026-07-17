#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
all_swift_roots=("${production_roots[@]}" SumiTests SumiUITests Packages/SumiWebRuntime)
graph_file="Sumi/Managers/WebViewRuntime/WebViewRuntimeGraph.swift"
profile_runtime_composition_file="Sumi/Managers/WebViewRuntime/WebViewProfileRuntimeComposition.swift"
browser_manager_file="Sumi/Managers/BrowserManager/BrowserManager.swift"
runtime_composition_file="Sumi/Managers/BrowserManager/BrowserManager+WebViewRuntimeComposition.swift"
runtime_wiring_file="Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift"
window_command_channel_file="Sumi/Managers/WebViewRuntime/BrowserWebViewWindowCommandChannel.swift"
close_request_broker_file="Sumi/Managers/WebViewRuntime/BrowserWebViewCloseRequestBroker.swift"
runtime_lifecycle_file="Sumi/Managers/WebViewRuntime/WebViewLifecycleService.swift"
visible_runtime_provider_file="Sumi/Managers/WebViewRuntime/VisibleWebViewRuntimeProvider.swift"
hidden_clone_eviction_file="Sumi/Managers/WebViewRuntime/HiddenCloneEvictionService.swift"
deferred_command_admission_file="Sumi/Managers/WebViewRuntime/DeferredProtectedCommandAdmissionService.swift"
deferred_command_processor_file="Sumi/Managers/WebViewRuntime/DeferredProtectedCommandProcessor.swift"
deferred_executor_live_file="Sumi/Managers/WebViewRuntime/DeferredWebViewCommandExecutor+Live.swift"
window_cleanup_live_file="Sumi/Managers/WebViewRuntime/WebViewWindowCleanupOwner+Live.swift"
replacement_pipeline_file="Sumi/Managers/WebViewRuntime/WebViewReplacementPipeline.swift"
retired_generation_destroyer_file="Sumi/Managers/WebViewRuntime/WebViewRetiredGenerationDestroyer.swift"
committed_tab_retirement_file="Sumi/Managers/WebViewRuntime/WebViewCommittedTabRetirementService.swift"
runtime_tab_registry_file="Sumi/Managers/WebViewRuntime/WebViewRuntimeTabRegistry.swift"
tab_file="Sumi/Models/Tab/Tab.swift"
main_frame_transaction_file="Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift"

window_context_file="App/Window/WindowViewContexts.swift"
window_context_composition_file="Sumi/Managers/BrowserManager/BrowserWindowViewContextComposition.swift"
floating_bar_context_file="FloatingBar/FloatingBarBrowserContext.swift"

for required_file in \
  "$browser_manager_file" \
  "$runtime_composition_file" \
  "$runtime_wiring_file" \
  "$window_command_channel_file" \
  "$close_request_broker_file" \
  "$runtime_lifecycle_file" \
  "$profile_runtime_composition_file" \
  "$replacement_pipeline_file" \
  "$tab_file" \
  "$main_frame_transaction_file"; do
  guard_require_file "$required_file"
done

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  guard_record_failure "$message"
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  local count
  count="$(guard_count_matches "$pattern" "$file")" || return
  if (( count == 0 )); then
    guard_record_failure "$message"
  fi
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

guard_require_file "$graph_file"

# Physical and symbolic tombstones keep the retired coordinator architecture
# from returning under a stale path or through one of its old context types.
retired_paths=(
  "Sumi/Managers/WebViewCoordinator"
  "Sumi/Managers/WebViewRuntime/WebViewCoordinator.swift"
  "Sumi/Managers/WebViewRuntime/WebViewRuntimeAssembler.swift"
  "Sumi/Managers/WebViewRuntime/DeferredProtectedCommandScheduler.swift"
  "Sumi/Managers/WebViewRuntime/WebViewShutdownRuntimeProvider.swift"
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
  guard_expect_absent_path 'retired WebView/window runtime path' "$retired_path"
done

for window_context_path in \
  "$window_context_file" \
  "$window_context_composition_file" \
  "$floating_bar_context_file"; do
  guard_require_file "$window_context_path"
done

require_pattern \
  "$floating_bar_context_file" \
  '^final class FloatingBarBrowserContext\b' \
  'stable floating-bar window context missing'

window_context_roles=(
  WindowWebContentContext
  WindowSidebarContext
  WindowNativeModalContext
  WindowFindContext
  WindowSplitContext
  WindowThemeChromeContext
)
for window_context_role in "${window_context_roles[@]}"; do
  require_pattern \
    "$window_context_file" \
    "^final class ${window_context_role}\\b" \
    "exact window context role missing: $window_context_role"
done

window_context_root_hits="$(
  guard_capture_matches \
    '\b(BrowserManager|WindowViewBrowserContext)\b' \
    App/Window/WindowView.swift "$window_context_file"
)"
fail_matches \
  "window feature contexts reached through the browser root or retired god context" \
  "$window_context_root_hits"

retired_window_context_hits="$(
  guard_capture_matches '\bWindowViewBrowserContext\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
fail_matches \
  "retired all-feature window context was reintroduced" \
  "$retired_window_context_hits"

runtime_role_files=(
  "$visible_runtime_provider_file"
  "$hidden_clone_eviction_file"
  "$deferred_command_admission_file"
  "$deferred_command_processor_file"
  "$deferred_executor_live_file"
  "$window_cleanup_live_file"
  "$retired_generation_destroyer_file"
  "$committed_tab_retirement_file"
  "$runtime_tab_registry_file"
)
for role_file in "${runtime_role_files[@]}"; do
  guard_require_file "$role_file"
done

guard_expect_no_matches \
  'retired multi-role WebViewRuntimeAssembler reintroduced' \
  '\bWebViewRuntimeAssembler\b|\bwebViewRuntimeAssembler\b' \
  -g '*.swift' -g '!**/.build/**' "${all_swift_roots[@]}"

guard_expect_no_matches \
  'retired WebView shutdown runtime provider reintroduced' \
  '\bWebViewShutdownRuntimeProvider\b' \
  -g '*.swift' -g '!**/.build/**' "${all_swift_roots[@]}"

shutdown_runtime_construction_count="$(
  guard_count_matches \
    'SumiWebViewShutdown\.NormalTabRuntime\(' \
    "$graph_file"
)"
guard_exact \
  'single WebView shutdown runtime construction' \
  "$shutdown_runtime_construction_count" \
  1

role_limits=(
  "$visible_runtime_provider_file:55:3"
  "$hidden_clone_eviction_file:55:4"
  "$deferred_command_admission_file:90:5"
  "$deferred_command_processor_file:220:7"
  "$deferred_executor_live_file:90:0"
  "$window_cleanup_live_file:80:0"
  "$retired_generation_destroyer_file:110:1"
  "$committed_tab_retirement_file:90:2"
  "$runtime_tab_registry_file:260:1"
)
for role_limit in "${role_limits[@]}"; do
  IFS=: read -r role_file max_lines max_collaborators <<< "$role_limit"
  line_count="$(guard_count_lines "$role_file")"
  collaborator_count="$(
    guard_count_matches '^    private let ' "$role_file"
  )"
  guard_max "$role_file LOC" "$line_count" "$max_lines"
  guard_max \
    "$role_file stored collaborators" \
    "$collaborator_count" \
    "$max_collaborators"
done

graph_line_count="$(guard_count_lines "$graph_file")"
profile_runtime_composition_line_count="$(
  guard_count_lines "$profile_runtime_composition_file"
)"
lifecycle_line_count="$(guard_count_lines "$runtime_lifecycle_file")"
lifecycle_collaborator_count="$(
  guard_count_matches '^    private let ' "$runtime_lifecycle_file"
)"
guard_max 'WebViewRuntimeGraph composition root LOC' "$graph_line_count" 640
guard_max \
  'WebView profile runtime composition LOC' \
  "$profile_runtime_composition_line_count" \
  55
profile_runtime_factory_count="$(
  guard_count_matches '^    static func make\(' \
    "$profile_runtime_composition_file"
)"
guard_exact \
  'WebView profile runtime composition factory count' \
  "$profile_runtime_factory_count" \
  1
guard_expect_no_matches \
  'WebView profile runtime composition gained stored state' \
  '^    ((private|fileprivate|internal|public)[[:space:]]+)?(static[[:space:]]+)?(lazy[[:space:]]+)?(let|var)\b' \
  "$profile_runtime_composition_file"
guard_max 'WebViewLifecycleService LOC' "$lifecycle_line_count" 253
guard_max \
  'WebViewLifecycleService stored collaborators' \
  "$lifecycle_collaborator_count" \
  17

guard_expect_no_matches \
  'deferred-command live composition regained graph/lifecycle reach-through' \
  '\b(WebViewRuntimeGraph|WebViewLifecycleService|DeferredWebViewCommandAssembly)\b' \
  "$deferred_executor_live_file" "$window_cleanup_live_file"

guard_expect_no_matches \
  'deferred-command execution regained the lifecycle constructor cycle' \
  '\bDeferredWebViewCommandAssembly\b|lifecycleService\.cleanup(UnprotectedTrackedWebView|Window|AllWebViews)' \
  "$graph_file"

legacy_coordinator_hits="$(
  guard_capture_matches '\bWebViewCoordinator\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
fail_matches "retired WebViewCoordinator type reintroduced" "$legacy_coordinator_hits"

legacy_context_hits="$(
  guard_capture_matches \
    '\bWebViewCoordinator[A-Za-z0-9_]*RuntimeContext\b|\bWebViewCoordinatorWebKitClosePreparation\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
fail_matches "coordinator-prefixed WebView runtime context reintroduced" "$legacy_context_hits"

retired_god_context_hits="$(
  guard_capture_matches \
    '\b(WebViewBrowserRuntimeContext|WebViewRuntimeContextStore|WebViewRuntimeEnvironment|runtimeContextStore)\b' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
fail_matches "retired WebView runtime god context/store reintroduced" "$retired_god_context_hits"

runtime_composition_body="$(
  sed -n '/^    func composeWebViewRuntime()/,/^    }$/p' \
    "$runtime_composition_file"
)"
runtime_composition_signature_count="$(
  guard_count_matches \
    '^    func composeWebViewRuntime\(\) -> WebViewRuntimeGraph \{' \
    - <<< "$runtime_composition_body"
)" || exit
runtime_graph_body_count="$(
  guard_count_matches \
    '^[[:space:]]*(return[[:space:]]+)?WebViewRuntimeGraph\(' \
    - <<< "$runtime_composition_body"
)" || exit
if (( runtime_composition_signature_count == 0 || runtime_graph_body_count == 0 )); then
  printf 'error: BrowserManager root must construct the exact WebViewRuntimeGraph\n' >&2
  guard_failures=$((guard_failures + 1))
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
  input_count="$(
    guard_count_matches \
      "^[[:space:]]*${exact_composition_input}:" \
      - <<< "$runtime_composition_body"
  )" || exit
  if (( input_count == 0 )); then
    printf 'error: WebView runtime composition lost exact input: %s\n' \
      "$exact_composition_input" >&2
    guard_failures=$((guard_failures + 1))
  fi
done
runtime_composition_forbidden="$(
  guard_capture_matches \
    '\bBrowserWebViewRuntimeFactory\b|^[[:space:]]*for:' \
    - <<< "$runtime_composition_body"
)" || exit
if [[ -n "$runtime_composition_forbidden" ]]; then
  printf 'error: WebView runtime composition regained a manager-taking factory\n' >&2
  guard_failures=$((guard_failures + 1))
fi

runtime_graph_construction_count="$(
  guard_count_matches '^[[:space:]]*(return[[:space:]]+)?WebViewRuntimeGraph\(' \
    "$runtime_composition_file"
)"
runtime_composition_install_count="$(
  guard_count_matches \
    'webViewRuntime = composeWebViewRuntime\(\)' \
    "$browser_manager_file"
)" || exit
if (( runtime_composition_install_count == 0 \
      || runtime_graph_construction_count != 1 )); then
  printf 'error: BrowserManager root must compose one exact WebView runtime\n' >&2
  guard_failures=$((guard_failures + 1))
fi
runtime_composition_line_count="$(guard_count_lines "$runtime_composition_file")"
runtime_composition_call_count="$(
  guard_count_matches '\bcomposeWebViewRuntime\(' \
    -g '*.swift' "${production_roots[@]}"
)"
guard_max 'WebView root composition LOC' "$runtime_composition_line_count" 265
guard_exact \
  'WebView root composition declaration + call' \
  "$runtime_composition_call_count" \
  2

guard_expect_no_matches \
  'WebView runtime composition regained BrowserManager lifetime capture' \
  '\[weak (self|browserManager)\]|\brequireBrowserManager\b|\brequireWindowRegistry\b|let browserManager = self' \
  "$runtime_composition_file"

guard_expect_no_matches \
  'WebView runtime composition regained the split layout/selection cycle' \
  '\bsplitWindowContext\b' \
  "$runtime_composition_file"

window_command_collaborators="$(
  guard_count_matches '^    private let ' "$window_command_channel_file"
)"
close_broker_collaborators="$(
  guard_count_matches '^    private (let|var) ' "$close_request_broker_file"
)"
guard_max \
  'WebView window command channel stored collaborators' \
  "$window_command_collaborators" \
  1
guard_max \
  'WebView close request broker stored collaborators' \
  "$close_broker_collaborators" \
  2
guard_expect_no_matches \
  'WebView command boundary gained a late callback slot or protocol mirror' \
  '@escaping|^    private (let|var).*->[[:space:]]*(Void|Bool)|^[[:space:]]*protocol ' \
  "$window_command_channel_file" "$close_request_broker_file"

command_boundary_hits="$(
  guard_capture_matches \
    '\b(BrowserWebViewWindowCommandChannel|BrowserWebViewCloseRequestBroker)\b' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    "$browser_manager_file"|\
    "$runtime_composition_file"|\
    "$runtime_wiring_file"|\
    "$window_command_channel_file"|\
    "$close_request_broker_file")
      ;;
    *)
      printf 'error: WebView command boundary escaped root composition: %s\n' \
        "$match" >&2
      guard_failures=$((guard_failures + 1))
      ;;
  esac
done <<< "$command_boundary_hits"

# The graph is composition storage, not a feature dependency. Production code
# can name its concrete type only where it is declared and where BrowserManager
# creates it. Tests may construct the graph explicitly.
graph_reference_hits="$(
  guard_capture_matches '\bWebViewRuntimeGraph\b' \
    "${production_roots[@]}" Packages/SumiWebRuntime/Sources \
    -g '*.swift' -g '!**/.build/**'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  case "$file" in
    "$graph_file"|"$runtime_composition_file")
      ;;
    *)
      printf 'error: WebViewRuntimeGraph escaped composition storage: %s\n' "$match" >&2
      guard_failures=$((guard_failures + 1))
      ;;
  esac
done <<< "$graph_reference_hits"

# Concrete graph access is limited to explicit composition edges that extract
# one or more narrow services for downstream feature code.
graph_access_hits="$(
  guard_capture_matches '\.webViewRuntime\b' \
    "${production_roots[@]}" -g '*.swift'
)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  if ! is_allowed_web_view_runtime_access "$file"; then
    printf 'error: WebView runtime graph accessed outside an approved composition edge: %s\n' \
      "$match" >&2
    guard_failures=$((guard_failures + 1))
  fi
done <<< "$graph_access_hits"

legacy_partial_context_hits="$(
  guard_capture_matches \
    '\b(attach|detach)(BrowserRuntimeContext|InitialDocumentRuntimeContext|ShutdownRuntimeContext|VisiblePreparationRuntimeContext)\s*\(' \
    "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
fail_matches "partial WebView runtime context attachment reintroduced" "$legacy_partial_context_hits"

lifecycle_shutdown_body="$(
  if [[ -f "$runtime_lifecycle_file" ]]; then
    sed -n '/^    func cleanupAfterBrowserRuntimeDeallocation()/,/^    }$/p' \
      "$runtime_lifecycle_file"
  fi
)"
lifecycle_shutdown_reset_count="$(
  guard_count_matches \
    'replacementPipeline\.resetForTerminalShutdown\(\)' \
    - <<< "$lifecycle_shutdown_body"
)" || exit
if [[ -z "$lifecycle_shutdown_body" ]] \
    || (( lifecycle_shutdown_reset_count == 0 )); then
  printf 'error: WebViewLifecycleService terminal cleanup must reset the replacement pipeline\n' >&2
  guard_failures=$((guard_failures + 1))
fi

replacement_reset_body="$(
  if [[ -f "$replacement_pipeline_file" ]]; then
    sed -n '/^    func resetForTerminalShutdown()/,/^    }$/p' \
      "$replacement_pipeline_file"
  fi
)"
replacement_settlement_reset_count="$(
  guard_count_matches \
    'settlementService\.resetForTerminalShutdown\(\)' \
    - <<< "$replacement_reset_body"
)" || exit
if [[ -z "$replacement_reset_body" ]] \
    || (( replacement_settlement_reset_count == 0 )); then
  printf 'error: WebViewReplacementPipeline terminal reset must reach settlement service\n' >&2
  guard_failures=$((guard_failures + 1))
fi

retired_generation_destroy_body="$(
  if [[ -f "$retired_generation_destroyer_file" ]]; then
    sed -n '/^    func destroy($/,/^    private func orderedWebViews(/p' \
      "$retired_generation_destroyer_file"
  fi
)"
retire_navigation_line="$(
  guard_capture_matches \
    'runtime\.retireNavigationGeneration\(' \
    - <<< "$retired_generation_destroy_body" \
    | sed -n '1{s/:.*//;p;}'
)" || exit
physical_destroy_line="$(
  guard_capture_matches \
    'runtime\.destroy\(' \
    - <<< "$retired_generation_destroy_body" \
    | sed -n '1{s/:.*//;p;}'
)" || exit
retired_destroy_call_count="$(
  guard_count_matches \
    'retiredGenerationDestroyer\.destroy\(' \
    "$replacement_pipeline_file"
)" || exit
if (( retired_destroy_call_count == 0 )); then
  printf 'error: replacement pipeline must use the shared retired-generation destroyer\n' >&2
  guard_failures=$((guard_failures + 1))
elif [[ -z "$retired_generation_destroy_body" \
        || -z "$retire_navigation_line" ]]; then
  printf 'error: retired generations must leave Tab navigation runtime before physical destruction\n' >&2
  guard_failures=$((guard_failures + 1))
elif (( retire_navigation_line >= physical_destroy_line )); then
  printf 'error: retired generation departure must precede every physical destroy\n' >&2
  guard_failures=$((guard_failures + 1))
fi

require_pattern \
  "$committed_tab_retirement_file" \
  'navigationTabsByID:' \
  'committed Tab retirement must retire the exact model navigation identity'

require_pattern \
  "$graph_file" \
  'tab\.webViewsDidLeaveNavigationRuntime\(' \
  'replacement pipeline generation departure must reach the exact Tab runtime'

tab_batch_departure_body="$(
  if [[ -f "$tab_file" ]]; then
    sed -n '/^    func webViewsDidLeaveNavigationRuntime(/,/^    }$/p' "$tab_file"
  fi
)"
tab_runtime_departure_count="$(
  guard_count_matches \
    'mainFrameRuntimeTransaction\.webViewsDidLeaveRuntime\(' \
    - <<< "$tab_batch_departure_body"
)" || exit
tab_replay_count="$(
  guard_count_matches \
    'TabMainFrameLifecycleReducer\.replayIfNeeded\(' \
    - <<< "$tab_batch_departure_body"
)" || exit
if [[ -z "$tab_batch_departure_body" ]] \
    || (( tab_runtime_departure_count == 0 || tab_replay_count == 0 )); then
  printf 'error: Tab replacement departure must reduce a whole generation and replay once\n' >&2
  guard_failures=$((guard_failures + 1))
fi

transaction_batch_departure_body="$(
  if [[ -f "$main_frame_transaction_file" ]]; then
    sed -n '/^    func webViewsDidLeaveRuntime(/,/^    func beginRecovery(/p' \
      "$main_frame_transaction_file"
  fi
)"
committed_transition_count="$(
  guard_count_matches \
    'committedDocumentRuntime\.performTransition\(' \
    - <<< "$transaction_batch_departure_body"
)" || exit
committed_removal_count="$(
  guard_count_matches \
    'committedDocumentRuntime\.removeWebViews\(' \
    - <<< "$transaction_batch_departure_body"
)" || exit
load_departure_count="$(
  guard_count_matches \
    'mainFrameLoads\.departure\(of: departingWebViews\)' \
    - <<< "$transaction_batch_departure_body"
)" || exit
lifecycle_departure_count="$(
  guard_count_matches \
    'lifecycle\.departure\(' \
    - <<< "$transaction_batch_departure_body"
)" || exit
if [[ -z "$transaction_batch_departure_body" ]] \
    || (( committed_transition_count == 0 \
      || committed_removal_count == 0 \
      || load_departure_count == 0 \
      || lifecycle_departure_count == 0 )); then
  printf 'error: main-frame replacement departure must batch every authority store\n' >&2
  guard_failures=$((guard_failures + 1))
fi

# The graph may store and lazily construct dependencies, but behavior belongs
# to the concrete services. Static, file-private assembly helpers are allowed.
graph_instance_behavior_hits="$(
  if [[ -f "$graph_file" ]]; then
    guard_capture_matches \
      '^    ((private|fileprivate|internal|public)[[:space:]]+)?(mutating[[:space:]]+)?func\b' \
      "$graph_file"
  fi
)"
fail_matches "WebView runtime graph gained instance behavior" "$graph_instance_behavior_hits"

graph_observation_hits="$(
  if [[ -f "$graph_file" ]]; then
    guard_capture_matches \
      '^import Observation$|@(Observable|ObservationIgnored)\b|:\s*ObservableObject\b' \
      "$graph_file"
  fi
)"
fail_matches "WebView runtime graph became observable UI state" "$graph_observation_hits"

swiftui_environment_hits="$(
  guard_capture_matches \
    '@(Environment|EnvironmentObject)\b[^\n]*\bWebViewRuntimeGraph\b|\.environment(Object)?\s*\([^)]*\bwebViewRuntime\b' \
    -U "${all_swift_roots[@]}" -g '*.swift' -g '!**/.build/**'
)"
fail_matches "WebView runtime graph injected through SwiftUI Environment" "$swiftui_environment_hits"

# Irreversible retirement is one mandatory typed role. Production supplies a
# concrete authority and tests must choose an explicit participant or the
# fail-closed rejecting fake; independent callback slots and defaults are
# forbidden.
tab_manager_lifecycle_file="Sumi/Managers/TabManager/TabManagerWebViewLifecycleService.swift"
lifecycle_factory_file="Sumi/Managers/BrowserManager/BrowserTabManagerWebViewLifecycleFactory.swift"
test_runtime_ports_file="SumiTests/Support/TestRuntimePorts.swift"
for lifecycle_file in \
  "$tab_manager_lifecycle_file" \
  "$lifecycle_factory_file" \
  "$test_runtime_ports_file"; do
  guard_require_file "$lifecycle_file"
done
for lifecycle_role in \
  TabWebViewAvailabilityParticipant \
  TabWebViewOwnershipParticipant \
  TabWebViewRetirementParticipant \
  TabWebViewProfileTransitionParticipant; do
  require_pattern \
    "$tab_manager_lifecycle_file" \
    "any ${lifecycle_role}" \
    "Tab lifecycle lost mandatory typed role $lifecycle_role"
done
guard_expect_no_matches \
  'Tab lifecycle regained independently injectable callbacks' \
  'private let [[:alnum:]_]+: \(' \
  "$tab_manager_lifecycle_file"
require_pattern \
  "$lifecycle_factory_file" \
  'retirement: BrowserTabWebViewRetirementParticipant\(' \
  'production lifecycle lost concrete retirement authority'
for retirement_operation in \
  canRetire \
  beginCommittedRetirement \
  destroyRetiredGenerations \
  destroyTerminallyDrainedGenerations; do
  for retirement_file in \
    "$tab_manager_lifecycle_file" \
    "$lifecycle_factory_file" \
    "$test_runtime_ports_file"; do
    require_pattern \
      "$retirement_file" \
      "func ${retirement_operation}" \
      "$retirement_file lost typed retirement operation $retirement_operation"
  done
done
guard_expect_no_matches \
  'test lifecycle regained a permissive retirement default' \
  'retirement: RetirementCapabilities[[:space:]]*=' \
  -U "$test_runtime_ports_file"
require_pattern \
  "$test_runtime_ports_file" \
  'static let rejecting = Self\(' \
  'tests lost explicit fail-closed retirement composition'
require_pattern \
  "$test_runtime_ports_file" \
  'ClosureTabWebViewRetirementParticipant\(retirement\)' \
  'tests lost explicit fail-closed retirement participant'

# Space profile mutation is one staged transaction: no observation-emitting
# convenience setter and no sibling production access to its raw/publish pair.
guard_expect_no_matches \
  'direct observation-emitting Space profile mutation returned' \
  '^[[:space:]]*func assignProfile\(' \
  Sumi/Managers/TabManager/TabSpaceCollectionStateOwner.swift
require_pattern \
  Sumi/Models/Space/Space.swift \
  '^[[:space:]]*private\(set\) var profileId: UUID\?' \
  'Space.profileId setter escaped its model boundary'
space_profile_raw_hits="$(
  guard_capture_matches \
    '\.(assignProfileWithoutObservation|publishProfileMutation)\(' \
    Sumi -g '*.swift' \
    -g '!**/SpaceProfileMutationService.swift'
)"
fail_matches \
  "Space profile raw/publish owner escaped SpaceProfileMutationTransaction" \
  "$space_profile_raw_hits"
space_model_raw_hits="$(
  guard_capture_matches \
    '\.(replaceProfileIDWithoutObservation|publishCurrentProfileID)\(' \
    Sumi -g '*.swift' \
    -g '!**/Space.swift' \
    -g '!**/TabSpaceCollectionStateOwner.swift'
)"
fail_matches "Space model raw profile mutation escaped its collection owner" \
  "$space_model_raw_hits"

guard_finish 'WebView runtime context boundary audit'
