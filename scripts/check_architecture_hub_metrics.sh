#!/usr/bin/env bash
# Architecture hub metrics freeze (plan A0).
# Caps are hard ceilings — god-hub debt must not grow during the 72→100 program.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for architecture hub metrics\n' >&2
  exit 1
fi

failures=0

for retired_document_owner in \
  Sumi/Models/Tab/TabCommittedDocumentOwner.swift \
  Sumi/Models/Tab/TabDocumentSuspensionOwner.swift; do
  if [[ -e "$retired_document_owner" ]]; then
    printf 'error: committed-document authority must not regrow as an Owner façade: %s\n' \
      "$retired_document_owner" >&2
    failures=$((failures + 1))
  fi
done

count_lines() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return
  fi
  wc -l < "$file" | tr -d ' '
}

count_matches() {
  local pattern="$1"
  shift
  local total=0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    total=$((total + ${line##*:}))
  done < <(rg --count-matches "$pattern" -g "*.swift" "$@" 2>/dev/null || true)
  printf '%s\n' "$total"
}

check_max() {
  local label="$1"
  local actual="$2"
  local max="$3"
  printf '%-52s %5d / %5d\n' "$label" "$actual" "$max"
  if (( actual > max )); then
    printf 'error: %s above hub-metrics freeze (%d > %d)\n' "$label" "$actual" "$max" >&2
    failures=$((failures + 1))
  fi
}

check_exact() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  printf '%-52s %5d = %5d\n' "$label" "$actual" "$expected"
  if (( actual != expected )); then
    printf 'error: %s changed (%d != %d)\n' "$label" "$actual" "$expected" >&2
    failures=$((failures + 1))
  fi
}

# Peer Owners on roots: lazy var *Owner in the façade files themselves.
bm_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserManager.swift)"
tm_loc="$(count_lines Sumi/Managers/TabManager/TabManager.swift)"
tab_model_loc="$(count_lines Sumi/Models/Tab/Tab.swift)"
tab_model_methods="$(
  rg --count-matches \
    '^\s*(public |private |internal |fileprivate )?func ' \
    Sumi/Models/Tab/Tab.swift 2>/dev/null || true
)"
tab_model_methods="${tab_model_methods:-0}"
tab_main_frame_transaction="Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift"
tab_main_frame_transaction_loc="$(count_lines "$tab_main_frame_transaction")"
tab_main_frame_transaction_methods="$(
  rg --count-matches \
    '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_main_frame_transaction" 2>/dev/null || true
)"
tab_main_frame_transaction_methods="${tab_main_frame_transaction_methods:-0}"
tab_main_frame_capabilities="Sumi/Models/Tab/TabMainFrameRuntimeCapabilities.swift"
tab_main_frame_capabilities_loc="$(count_lines "$tab_main_frame_capabilities")"
tab_main_frame_capability_methods="$(
  rg --count-matches '^\s*func ' \
    "$tab_main_frame_capabilities" 2>/dev/null || true
)"
tab_main_frame_capability_methods="${tab_main_frame_capability_methods:-0}"
tab_main_frame_authority_reducer="Sumi/Models/Tab/TabMainFrameAuthorityReducer.swift"
tab_main_frame_authority_reducer_loc="$(count_lines "$tab_main_frame_authority_reducer")"
tab_main_frame_authority_reducer_methods="$(
  rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_main_frame_authority_reducer" 2>/dev/null || true
)"
tab_main_frame_authority_reducer_methods="${tab_main_frame_authority_reducer_methods:-0}"
tab_main_frame_authority_state="Sumi/Models/Tab/TabMainFrameAuthorityState.swift"
tab_main_frame_authority_state_loc="$(count_lines "$tab_main_frame_authority_state")"
tab_main_frame_authority_state_methods="$(
  rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_main_frame_authority_state" 2>/dev/null || true
)"
tab_main_frame_authority_state_methods="${tab_main_frame_authority_state_methods:-0}"
tab_main_frame_settlement_files=(
  "Sumi/Models/Tab/TabMainFrameActiveNavigationSettlement.swift"
  "Sumi/Models/Tab/TabMainFrameTerminalSettlement.swift"
  "Sumi/Models/Tab/TabMainFrameSameDocumentSettlement.swift"
  "Sumi/Models/Tab/TabMainFramePromotionReplaySettlement.swift"
  "Sumi/Models/Tab/TabMainFrameCompletedAuthorityProof.swift"
)
tab_main_frame_settlement_loc=0
tab_main_frame_settlement_methods=0
for settlement_file in "${tab_main_frame_settlement_files[@]}"; do
  tab_main_frame_settlement_loc=$((
    tab_main_frame_settlement_loc + $(count_lines "$settlement_file")
  ))
  settlement_methods="$(
    rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' \
      "$settlement_file" 2>/dev/null || true
  )"
  tab_main_frame_settlement_methods=$((
    tab_main_frame_settlement_methods + ${settlement_methods:-0}
  ))
done
retired_terminal_finish_choreography="$(
  count_matches \
    'claimAuthorityForTerminalSuccess|claimSharedFinishEffects|reserveTerminalSuccess|finishLifecycle|TabMainFrameCheckpointSettlement' \
    Sumi SumiTests
)"
tab_main_frame_lifecycle_machine="Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift"
tab_main_frame_lifecycle_machine_loc="$(count_lines "$tab_main_frame_lifecycle_machine")"
tab_main_frame_lifecycle_machine_methods="$(
  rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_main_frame_lifecycle_machine" 2>/dev/null || true
)"
tab_main_frame_lifecycle_machine_methods="${tab_main_frame_lifecycle_machine_methods:-0}"
tab_main_frame_responder="Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift"
tab_main_frame_responder_loc="$(count_lines "$tab_main_frame_responder")"
tab_main_frame_promotion_reducer="Sumi/Models/Tab/Navigation/TabMainFrameLifecyclePromotionReducer.swift"
tab_main_frame_promotion_reducer_loc="$(count_lines "$tab_main_frame_promotion_reducer")"
tab_main_frame_load_runtime="Sumi/Models/Tab/TabMainFrameLoadRuntime.swift"
tab_main_frame_load_runtime_loc="$(count_lines "$tab_main_frame_load_runtime")"
tab_main_frame_load_runtime_methods="$(
  rg --count-matches \
    '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_main_frame_load_runtime" 2>/dev/null || true
)"
tab_main_frame_load_runtime_methods="${tab_main_frame_load_runtime_methods:-0}"
tab_recovery_marker_ledger="Sumi/Models/Tab/TabWebContentRecoveryMarkerLedger.swift"
tab_recovery_marker_ledger_loc="$(count_lines "$tab_recovery_marker_ledger")"
tab_recovery_marker_ledger_methods="$(
  rg --count-matches \
    '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_recovery_marker_ledger" 2>/dev/null || true
)"
tab_recovery_marker_ledger_methods="${tab_recovery_marker_ledger_methods:-0}"
tab_committed_document_runtime="Sumi/Models/Tab/TabCommittedDocumentRuntime.swift"
tab_committed_document_runtime_loc="$(count_lines "$tab_committed_document_runtime")"
tab_committed_document_runtime_methods="$(
  rg --count-matches \
    '^\s*(public |private |internal |fileprivate )?func ' \
    "$tab_committed_document_runtime" 2>/dev/null || true
)"
tab_committed_document_runtime_methods="${tab_committed_document_runtime_methods:-0}"
retired_tab_profile_assignment_facade="$(
  count_matches \
    'beginProfileAssignmentIntent|isCurrentProfileAssignmentIntent|hasPendingProfileAssignment|hasUnsettledProfileAssignment|cancelPendingProfileAssignment|commitProfileAssignmentIntent|stageProfileAssignmentIntent|isCurrentStagedProfileAssignmentIntent|finishStagedProfileAssignmentIntent|rollbackStagedProfileAssignmentIntent|abortProfileAssignmentIntent' \
    Sumi SumiTests
)"
tab_profile_assignment_mutation_outside_services="$({
  rg --count-matches \
    '\.profileAssignment\.(begin|cancelPending|commit|stage|finish|rollback|abort|replaceCurrentProfileID)\b' \
    Sumi -g '*.swift' \
    -g '!Sumi/Managers/WebViewRuntime/ProfileTransitionService.swift' \
    -g '!Sumi/Managers/TabManager/SpaceProfileTransaction.swift' \
    -g '!Sumi/Managers/TabManager/SpaceProfileTransitionService.swift' \
    -g '!Sumi/Managers/TabManager/TabProfileTransitionService.swift' \
    2>/dev/null || true
} | awk -F: '{ total += $NF } END { print total + 0 }')"
window_session_bundle_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserWindowSessionBundle.swift)"
shell_runtime_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserShellRuntime.swift)"
webview_routing_loc="$(count_lines Sumi/Services/BrowserWebViewRoutingService.swift)"
window_commands_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserWindowCommands.swift)"
window_reconciler_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserWindowStateReconciler.swift)"
window_space_transition_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService.swift)"
window_space_transition_live_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift)"
window_space_selection_handoff_file="Sumi/Managers/BrowserManager/BrowserWindowSpaceSelectionHandoff.swift"
window_space_context_transition_file="Sumi/Managers/BrowserManager/BrowserWindowSpaceContextTransition.swift"
bm_peer_owners="$(
  rg --count-matches 'lazy var \w+Owner\b' \
    Sumi/Managers/BrowserManager/BrowserManager.swift 2>/dev/null || true
)"
bm_peer_owners="${bm_peer_owners:-0}"
tm_peer_owners="$(
  rg --count-matches 'lazy var \w+Owner\b' \
    Sumi/Managers/TabManager/TabManager.swift 2>/dev/null || true
)"
tm_peer_owners="${tm_peer_owners:-0}"
tm_owner_bags="$(
  rg --count-matches 'lazy var \w+Owners\b' \
    Sumi/Managers/TabManager/TabManager.swift 2>/dev/null || true
)"
tm_owner_bags="${tm_owner_bags:-0}"
tm_facade_owner_accessors="$(
  count_matches '^    var \w+Owner\b' Sumi/Managers/TabManager/TabManager+*.swift
)"
bm_bundles="$(
  rg --count-matches 'lazy var \w+Bundle\b' \
    Sumi/Managers/BrowserManager/BrowserManager.swift 2>/dev/null || true
)"
bm_bundles="${bm_bundles:-0}"
bm_bundle_capabilities="$(
  count_matches '^    let \w+' Sumi/Managers/BrowserManager/*Bundle.swift
)"

live_bm="$(
  count_matches 'static\s+func\s+live\s*\(\s*browserManager' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"
live_tm="$(
  count_matches 'static\s+func\s+live\s*\(\s*tabManager' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"
# Process-lifecycle dissolution: BrowserManager extensions must not re-grow
# façade accessors that hand out command owners, and command routers must not
# reach the process runtime lifecycle / settings attachment.
bm_facade_owner_accessors="$(
  count_matches 'var \w+Owner\b' Sumi/Managers/BrowserManager/BrowserManager+*.swift
)"
retired_app_command_hubs="$(
  count_matches 'BrowserLifecycleBundle|BrowserAppCommandRouter|\bappCommandRouter\b' \
    App Sumi UI
)"
retired_window_session_reachthrough="$(
  count_matches \
    'windowSessionBundle\.(tabContextOwner|visualMutationOwner|scopedNavigationOwner|commands|windowStateValidationOwner|spaceStateOwner)|BrowserWindow(TabContextOwner|VisualMutationOwner|ScopedNavigationOwner|SessionCommands|StateValidationOwner|SpaceStateOwner)' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
retired_stateless_routing_objects="$(
  count_matches \
    'SumiProfileRouter|\bsumiProfileRouter\b|BrowserPermissionSiteSettingsRoutingOwner|\bpermissionSiteSettingsRoutingOwner\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
# Session-recovery split: the former BrowserRecentlyClosedRestoreOwner
# god-object (13 closure deps, 4 unrelated workflows) is tombstoned. Its
# successors are per-workflow services; no successor may re-absorb the old
# dependency bag or reach back into BrowserManager / the history menu owner.
retired_recently_closed_restore="$(
  count_matches 'BrowserRecentlyClosedRestoreOwner|recentlyClosedRestoreOwner|BrowserHistoryMenuOwner|historyMenuOwner' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
session_recovery_services=(
  "Sumi/Managers/BrowserManager/ClosedTabRestoreService.swift"
  "Sumi/Managers/BrowserManager/ClosedShortcutRestoreService.swift"
  "Sumi/Managers/BrowserManager/WindowSessionReopenService.swift"
  "Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift"
  "Sumi/Managers/BrowserManager/RecentlyClosedItemReopenService.swift"
  "Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands.swift"
)
session_recovery_composition="Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands+Live.swift"
if [[ -e Sumi/Managers/BrowserManager/BrowserRecentlyClosedRestoreOwner.swift ]]; then
  printf 'error: tombstone violated: BrowserRecentlyClosedRestoreOwner.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
for service_file in "${session_recovery_services[@]}"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: session-recovery service missing (workflows must stay split): %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
session_recovery_reachback="$(
  count_matches '\bbrowserManager\b|\bBrowserManager\b|BrowserHistoryMenuOwner|historyMenuOwner' \
    "${session_recovery_services[@]}"
)"
mutable_session_restore_identity="$(
  count_matches \
    'map\(\\\.session\)|contains\(\$0\.session\)|uniqued\(by:[[:space:]]*\\\.session\)' \
    Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift \
    Sumi/Managers/BrowserManager/StartupWindowRestoreService.swift \
    Sumi/Services/SumiStartupSessionCoordinator.swift \
    Sumi/Managers/History/LastSessionWindowsStore.swift
)"
if [[ -e Sumi/Managers/BrowserManager/BrowserStartupPolicyOwner.swift ]]; then
  printf 'error: tombstone violated: BrowserStartupPolicyOwner.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
startup_policy_services=(
  "Sumi/Managers/BrowserManager/BrowserStartupPolicy.swift"
  "Sumi/Managers/BrowserManager/CleanStartupWorkflow.swift"
  "Sumi/Managers/BrowserManager/StartupWindowRestoreService.swift"
)
for service_file in "${startup_policy_services[@]}"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: startup policy service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
count_stored_collaborators() {
  local file="$1"
  local stored
  stored="$(rg --count-matches '^    private let [a-zA-Z_]' "$file" 2>/dev/null || true)"
  printf '%s\n' "${stored:-0}"
}
# Window-state repair split: selection recovery, Space/Profile reconciliation,
# and profile runtime derivation are separate roles. Runtime derivation must
# not drift back into persistence snapshot construction or an *Owner façade.
window_selection_repair_file="Sumi/Managers/BrowserManager/BrowserWindowSelectionRepairService.swift"
window_space_context_file="Sumi/Managers/BrowserManager/BrowserWindowSpaceContextReconciler.swift"
focused_space_runtime_file="Sumi/Managers/BrowserManager/FocusedSpaceRuntimeStateSynchronizer.swift"
space_profile_runtime_file="Sumi/Managers/TabManager/SpaceProfileRuntimeStateService.swift"
for service_file in \
  "$window_selection_repair_file" \
  "$window_space_context_file" \
  "$focused_space_runtime_file" \
  "$space_profile_runtime_file"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: window-state repair service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
for service_file in \
  "$window_space_selection_handoff_file" \
  "$window_space_context_transition_file"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: window Space transition service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
if [[ -e Sumi/Managers/BrowserManager/BrowserWindowSpaceStateOwner.swift ]]; then
  printf 'error: tombstone violated: BrowserWindowSpaceStateOwner must stay deleted\n' >&2
  failures=$((failures + 1))
fi
retired_window_space_state_owner="$(
  count_matches 'BrowserWindowSpaceStateOwner|windowSpaceStateOwner' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
if [[ -e Sumi/Managers/TabManager/TabProfileRuntimeStateOwner.swift ]] \
  || [[ -e SumiTests/TabProfileRuntimeStateOwnerTests.swift ]]; then
  printf 'error: tombstone violated: TabProfileRuntimeStateOwner must stay deleted\n' >&2
  failures=$((failures + 1))
fi
retired_profile_runtime_owner="$(
  count_matches 'TabProfileRuntimeStateOwner|updateProfileRuntimeStates' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
profile_runtime_persistence_coupling="$(
  count_matches 'SpaceProfileRuntimeStateService|profileRuntimeState|reconcileProfileRuntimeStates' \
    Sumi/Managers/TabManager/TabStructuralPersistenceService.swift
)"
profile_runtime_window_context_regrowth="$(
  count_matches 'SpaceProfileRuntimeStateService|profileRuntimeState|reconcileProfileRuntimeStates' \
    "$window_space_context_file"
)"
# Space-domain split: the former TabSpaceLifecycleOwner mixed catalog edits,
# deletion, selection handoff, and target resolution behind 30 closures.
# The four successors are composed explicitly and may not reach back through
# TabManager or regrow a behavior-bearing façade.
retired_tab_space_lifecycle="$(
  count_matches 'TabSpaceLifecycleOwner|\bspaceLifecycleOwner\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
tab_space_services=(
  "Sumi/Managers/TabManager/SpaceCatalogCommands.swift"
  "Sumi/Managers/TabManager/SpaceRemovalService.swift"
  "Sumi/Managers/TabManager/SpaceActivationService.swift"
  "Sumi/Managers/TabManager/TabCreationPlacementService.swift"
)
tab_space_removal_helpers=(
  "Sumi/Managers/TabManager/SpaceContentRetirementService.swift"
  "Sumi/Managers/TabManager/SpaceSplitGroupRetirementService.swift"
  "Sumi/Managers/TabManager/SpaceTabInventory.swift"
  "Sumi/Managers/TabManager/DeletedSpaceWindowStateReconciler.swift"
  "Sumi/Managers/TabManager/DeletedSpaceWindowReferencePruner.swift"
  "Sumi/Managers/TabManager/TabRuntimeTeardownService.swift"
)
tab_space_group="Sumi/Managers/TabManager/TabSpaceServices.swift"
tab_space_composition="Sumi/Managers/TabManager/TabSpaceServices+Live.swift"
pending_profile_inheritance_file="Sumi/Managers/TabManager/PendingTabProfileInheritance.swift"
if [[ -e Sumi/Managers/TabManager/TabSpaceLifecycleOwner.swift ]]; then
  printf 'error: tombstone violated: TabSpaceLifecycleOwner.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
if [[ -e Sumi/Managers/TabManager/TabTargetSpaceResolver.swift ]]; then
  printf 'error: tombstone violated: TabTargetSpaceResolver.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
for service_file in \
  "${tab_space_services[@]}" \
  "${tab_space_removal_helpers[@]}" \
  "$tab_space_group" \
  "$tab_space_composition"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: split Space service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
if [[ ! -f "$pending_profile_inheritance_file" ]]; then
  printf 'error: pending profile inheritance service missing: %s\n' \
    "$pending_profile_inheritance_file" >&2
  failures=$((failures + 1))
fi
tab_space_reachback="$(
  count_matches \
    '\bTabManager\b|\btabManager\b' \
    "${tab_space_services[@]}" \
    "${tab_space_removal_helpers[@]}"
)"
retired_tab_creation_resolver_api="$(
  count_matches \
    'TabTargetSpaceResolver|\bprofileIdForNewTab\b|\brequestTargetSpaceProfileBackfill\b|\binitialExplicitProfileId\b|\bprofileIdForUnassignedSpace\b|\bcreateNewTabWithWebView\b|\bduplicateAsRegularForSplit\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
mutable_browser_tab_manager="$(
  count_matches '^    var tabManager: TabManager' \
    Sumi/Managers/BrowserManager/BrowserManager.swift
)"
browser_tab_manager_reassignment="$(
  count_matches '\bbrowserManager\.tabManager\s*=' SumiTests
)"
tab_space_group_capabilities="$(
  rg --count-matches '^    let [A-Za-z_]' "$tab_space_group" 2>/dev/null || true
)"
tab_space_group_capabilities="${tab_space_group_capabilities:-0}"
tab_space_group_behavior="$(count_matches '\bfunc ' "$tab_space_group")"
space_profile_embedded_follower_state="$(
  count_matches \
    'InFlightCreationFollower|creationFollowersBySpaceID|inheritCommittedCreationFollowers|discardCreationFollowers|takeCreationFollowers' \
    Sumi/Managers/TabManager/SpaceProfileTransitionService.swift
)"
pending_profile_inheritance_construction="$(
  count_matches 'PendingTabProfileInheritance\(' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"
pending_profile_inheritance_wiring="$(
  count_matches 'pendingInheritance: pendingInheritance' \
    Sumi/Managers/TabManager/ProfileAssignmentServices.swift
)"
tab_lifecycle_bag_capabilities="$(
  rg --count-matches '^    lazy var [A-Za-z_]' \
    Sumi/Managers/TabManager/TabLifecycleOwnerBag.swift 2>/dev/null || true
)"
tab_lifecycle_bag_capabilities="${tab_lifecycle_bag_capabilities:-0}"
# Shortcut live-tab retirement: physical release and selection reconciliation
# must not return to the activation/conversion owner. The successor is one
# role-exact service plus a stateless reconciler, not another Owner/bag.
shortcut_retirement_file="Sumi/Managers/TabManager/ShortcutLiveTabRetirementService.swift"
shortcut_selection_file="Sumi/Managers/TabManager/ShortcutSelectionReconciler.swift"
shortcut_registry_file="Sumi/Managers/TabManager/LiveShortcutTabRegistry.swift"
shortcut_registry_snapshot="Sumi/Managers/TabManager/LiveShortcutTabSnapshot.swift"
shortcut_window_query_file="Sumi/Managers/TabManager/ShortcutTabWindowQuery.swift"
shortcut_binding_file="Sumi/Managers/TabManager/ShortcutTabBindingSynchronizer.swift"
shortcut_materializer_file="Sumi/Managers/TabManager/ShortcutTabMaterializer.swift"
regular_shortcut_conversion_file="Sumi/Managers/TabManager/RegularTabShortcutConversionService.swift"
regular_shortcut_conversion_live="Sumi/Managers/TabManager/RegularTabShortcutConversionService+Live.swift"
shortcut_pin_promotion_file="Sumi/Managers/TabManager/ShortcutPinToRegularTabService.swift"
shortcut_conversion_planner_file="Sumi/Managers/TabManager/RegularTabShortcutConversionPlanner.swift"
shortcut_conversion_committer_file="Sumi/Managers/TabManager/DisplayedTabShortcutConversionCommitter.swift"
shortcut_conversion_authorizer_file="Sumi/Managers/TabManager/TabShortcutConversionAuthorizer.swift"
shortcut_structure_transition_file="Sumi/Managers/TabManager/RegularTabShortcutStructureTransition.swift"
shortcut_structure_plan_file="Sumi/Managers/TabManager/RegularTabShortcutStructurePlan.swift"
shortcut_window_transition_file="Sumi/Managers/TabManager/DisplayedTabShortcutWindowTransition.swift"
shortcut_promotion_file="Sumi/Managers/TabManager/ShortcutTabPromotionService.swift"
shortcut_selection_transition_file="Sumi/Managers/TabManager/ShortcutSelectionTransition.swift"
shortcut_runtime_files=(
  "$shortcut_registry_file"
  "$shortcut_registry_snapshot"
  "$shortcut_window_query_file"
  "$shortcut_binding_file"
  "$shortcut_materializer_file"
  "$regular_shortcut_conversion_file"
  "$regular_shortcut_conversion_live"
  "$shortcut_pin_promotion_file"
  "$shortcut_conversion_planner_file"
  "$shortcut_conversion_committer_file"
  "$shortcut_conversion_authorizer_file"
  "$shortcut_structure_transition_file"
  "$shortcut_structure_plan_file"
  "$shortcut_promotion_file"
  "$shortcut_retirement_file"
  "$shortcut_selection_file"
)
for service_file in "${shortcut_runtime_files[@]}"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: shortcut runtime service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
unsafe_shortcut_conversion_phase_api="$({
  rg --count-matches '^    func (authorize|canConvert)\(' \
    "$regular_shortcut_conversion_file" 2>/dev/null || true
} | awk '{ total += $1 } END { print total + 0 }')"
retired_shortcut_conversion_hubs="$(
  count_matches \
    '\b(DisplayedTabShortcutConverter|DisplayedTabShortcutConversionPlanner|ShortcutPinConversionOwner|TabShortcutConversionService)\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
retired_shortcut_live_hub="$(
  count_matches \
    'ShortcutLiveTabOwner|ShortcutLiveTabWindowQueryOwner|\bshortcutLiveTabOwner\b|ShortcutLiveTabServices' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
shortcut_live_bag_reach="$(
  count_matches \
    '\b(liveShortcutTabs|shortcutTabWindowQuery|shortcutTabBindings|shortcutTabMaterializer|regularTabShortcutConversion|shortcutPinToRegularTab|shortcutTabPromotion|shortcutLiveTabRetirement)\b' \
    Sumi/Managers/TabManager/TabShortcutOwnerBag.swift \
    Sumi/Managers/TabManager/TabManager+OwnerAccessors.swift
)"
shortcut_dependency_bags="$(
  count_matches 'struct Dependencies\b' \
    "$shortcut_registry_file" "$shortcut_window_query_file" \
    "$shortcut_binding_file" "$shortcut_materializer_file" \
    "$regular_shortcut_conversion_file" "$shortcut_promotion_file"
)"
retired_shortcut_retirement_surface="$(
  count_matches \
    'deactivateShortcutLiveTab|userInitiatedUnload|removeLiveShortcutTabs|clearDeletedShortcutPinSelectionReferences|persistWindowSessionsForShortcutSelectionCleanup|ShortcutPinSelectionCleanupResult' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
shortcut_retirement_owner_regrowth="$(
  count_matches \
    'ShortcutLiveTabRetirementOwner|ShortcutSelectionReconciliationOwner|ShortcutLiveTabServices' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
shortcut_retirement_physical_cleanup="$(
  count_matches \
    'performComprehensiveWebViewCleanup|webViewLifecycle\.(unloadTab|requireRemoveAllWebViews)|\.detach\s*\(' \
    "${shortcut_runtime_files[@]}"
)"
shortcut_retirement_browser_policy="$(
  count_matches '\bBrowserManager\b|BrowserNotificationPresenting|\bnotifications\b' \
    "$shortcut_retirement_file" "$shortcut_selection_file"
)"
# Split-shortcut browser routing: the retired 500+ LOC Owner mixed focus,
# materialization, launcher restoration, retirement, and hosted-group unload.
# These workflows must remain separate services behind a behavior-free group.
split_shortcut_group="Sumi/Managers/BrowserManager/SplitShortcutServices.swift"
split_shortcut_runtime_lease="Sumi/Managers/BrowserManager/SplitShortcutRuntimeLease.swift"
split_shortcut_focus="Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift"
split_shortcut_materialization="Sumi/Managers/BrowserManager/WindowSplitMaterializationService.swift"
split_shortcut_resolver="Sumi/Managers/BrowserManager/SplitShortcutMemberResolver.swift"
split_shortcut_restore="Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreService.swift"
split_shortcut_launcher="Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService.swift"
split_shortcut_launcher_resolver="Sumi/Managers/BrowserManager/ShortcutSplitLauncherDestinationResolver.swift"
split_shortcut_launcher_transaction="Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveTransaction.swift"
split_shortcut_launcher_catalog="Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogAdapter.swift"
split_shortcut_launcher_composition="Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService+Live.swift"
split_shortcut_unload="Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift"
split_shortcut_composition="Sumi/Managers/BrowserManager/SplitShortcutServices+Live.swift"
split_shortcut_sidebar_commands="Sumi/Managers/BrowserManager/SidebarSplitCommands.swift"
split_shortcut_sidebar_commands_composition="Sumi/Managers/BrowserManager/SidebarSplitCommands+Live.swift"
split_shortcut_files=(
  "$split_shortcut_focus"
  "$split_shortcut_materialization"
  "$split_shortcut_resolver"
  "$split_shortcut_restore"
  "$split_shortcut_launcher"
  "$split_shortcut_launcher_resolver"
  "$split_shortcut_launcher_transaction"
  "$split_shortcut_launcher_catalog"
  "$split_shortcut_unload"
)
for service_file in \
  "${split_shortcut_files[@]}" \
  "$split_shortcut_group" \
  "$split_shortcut_runtime_lease" \
  "$split_shortcut_sidebar_commands" \
  "$split_shortcut_sidebar_commands_composition" \
  "$split_shortcut_launcher_composition" \
  "$split_shortcut_composition"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: split-shortcut service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
for retired_file in \
  Sumi/Managers/BrowserManager/BrowserSidebarSplitShortcutRoutingOwner.swift \
  SumiTests/BrowserSidebarSplitShortcutRoutingOwnerTests.swift; do
  if [[ -e "$retired_file" ]]; then
    printf 'error: tombstone violated: retired split routing hub returned: %s\n' "$retired_file" >&2
    failures=$((failures + 1))
  fi
done
retired_split_shortcut_hub="$(
  count_matches \
    'BrowserSidebarSplitShortcutRoutingOwner|BrowserSidebarSplitShortcutRouting|splitShortcutRouting' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
split_shortcut_group_capabilities="$(
  rg --count-matches '^    let [A-Za-z_]' "$split_shortcut_group" 2>/dev/null || true
)"
split_shortcut_group_capabilities="${split_shortcut_group_capabilities:-0}"
split_shortcut_group_behavior="$(count_matches '\bfunc ' "$split_shortcut_group")"
split_shortcut_dependency_bags="$(
  count_matches 'struct (Actions|Dependencies)\b' "${split_shortcut_files[@]}"
)"
split_shortcut_domain_reachback="$(
  count_matches '\bBrowserManager\b|\bbrowserManager\b' "${split_shortcut_files[@]}"
)"
split_shortcut_launcher_reachback="$(
  count_matches '\b(TabManager|BrowserManager|tabManager|browserManager)\b' \
    "$split_shortcut_launcher"
)"
split_shortcut_composition_state="$(
  count_matches '^    (private )?(let|var|lazy var) ' "$split_shortcut_composition"
)"
split_shortcut_runtime_providers="$(
  count_matches \
    '^    private let runtimeLease: \(\) -> SplitShortcutRuntimeLease\?' \
    "$split_shortcut_focus" "$split_shortcut_restore" "$split_shortcut_unload"
)"
split_shortcut_stored_runtime_managers="$(
  count_matches \
    '^    private let [A-Za-z_]+: TabManager\b' \
    "$split_shortcut_focus" "$split_shortcut_restore" "$split_shortcut_unload"
)"
split_shortcut_separate_runtime_providers="$(
  count_matches \
    '^    private let [A-Za-z_]+: \(\) -> TabManager\?' \
    "$split_shortcut_focus" "$split_shortcut_restore" "$split_shortcut_unload"
)"
split_shortcut_runtime_lease_acquisitions="$(
  count_matches '\bruntimeLease\(\)' \
    "$split_shortcut_focus" "$split_shortcut_restore" "$split_shortcut_unload"
)"
split_shortcut_runtime_lease_capabilities="$(
  count_matches '^    let (tabManager|splitManager):' "$split_shortcut_runtime_lease"
)"
split_shortcut_live_weak_runtime_provider="$(
  count_matches \
    'let runtimeLease: \(\) -> SplitShortcutRuntimeLease\? = \{ \[weak browserManager\] in' \
    "$split_shortcut_composition"
)"

# Live shortcut close is one browser workflow, not an Owner façade.
shortcut_live_close="Sumi/Managers/BrowserManager/ShortcutLiveTabCloseService.swift"
if [[ -e Sumi/Managers/BrowserManager/BrowserShortcutLiveTabCloseOwner.swift ]]; then
  printf 'error: tombstone violated: BrowserShortcutLiveTabCloseOwner.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
retired_shortcut_live_close_owner="$(
  count_matches 'BrowserShortcutLiveTabCloseOwner' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
# Window-session durable writes must remain usable during root teardown without
# retaining or consulting the live last-session projection. Only the
# coordinator may combine the durable service with archive refresh semantics.
window_session_durable_file="Sumi/Services/WindowSessionPersistenceService.swift"
retired_window_session_pending_write="$(
  count_matches \
    'WindowSessionPendingWrite|commitWhileRuntimeIsLive|commitDurableSnapshotOnly|\bpendingWrite\s*\(' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
durable_write_archive_reachback="$(
  count_matches \
    'LastSessionWindowArchive|OpenWindowSessionCatalog|WindowSessionPersistenceScheduler' \
    "$window_session_durable_file"
)"
restore_raw_persistence_dependency="$(
  count_matches 'WindowSessionPersistenceService' \
    Sumi/Services/WindowSessionRestoreService.swift
)"
raw_durable_api_outside_coordinator="$(
  (rg -n '\.(persistDurableSnapshot|durableWrite)\s*\(' \
      App FloatingBar SidebarChrome Settings Sumi UI \
      -g '*.swift' -g '!WindowSessionPersistenceCoordinator.swift' \
      2>/dev/null || true) | wc -l | tr -d ' '
)"
# Window-session history split: the former BrowserWindowHistorySessionOwner
# mixed open-window cataloging, last-session archive upkeep, and closed-window
# history recording behind one six-dependency object. It is tombstoned; its
# successors are role-exact services composed via a behavior-free group, and
# none of them may reach back into BrowserManager.
retired_window_history_owner="$(
  count_matches 'BrowserWindowHistorySessionOwner|\bhistorySessionOwner\b' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
window_history_services=(
  "Sumi/Managers/BrowserManager/OpenWindowSessionCatalog.swift"
  "Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift"
  "Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift"
)
window_history_group="Sumi/Managers/BrowserManager/WindowSessionHistoryServices.swift"
window_history_composition="Sumi/Managers/BrowserManager/WindowSessionHistoryServices+Live.swift"
if [[ -e Sumi/Managers/BrowserManager/BrowserWindowHistorySessionOwner.swift ]]; then
  printf 'error: tombstone violated: BrowserWindowHistorySessionOwner.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
if [[ -e SumiTests/BrowserWindowHistorySessionOwnerTests.swift ]]; then
  printf 'error: tombstone violated: BrowserWindowHistorySessionOwnerTests.swift must stay deleted\n' >&2
  failures=$((failures + 1))
fi
for service_file in "${window_history_services[@]}" "$window_history_group" "$window_history_composition"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: window-session history service missing (roles must stay split): %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
window_history_reachback="$(
  count_matches '\bbrowserManager\b|\bBrowserManager\b' \
    "${window_history_services[@]}" "$window_history_group"
)"
window_history_group_capabilities="$(
  rg --count-matches '^    (let|var|lazy var) [A-Za-z_]' \
    "$window_history_group" 2>/dev/null || true
)"
window_history_group_capabilities="${window_history_group_capabilities:-0}"
window_history_group_behavior="$(
  count_matches '\bfunc ' "$window_history_group"
)"
window_session_capabilities="$(
  rg --count-matches '^    (let|var|lazy var) [A-Za-z_][A-Za-z0-9_]*' \
    Sumi/Managers/BrowserManager/BrowserWindowSessionBundle.swift 2>/dev/null || true
)"
window_session_capabilities="${window_session_capabilities:-0}"
shell_window_capabilities="$(
  rg --count-matches '^    lazy var window[A-Z][A-Za-z0-9_]*\b' \
    Sumi/Managers/BrowserManager/BrowserShellRuntime.swift 2>/dev/null || true
)"
shell_window_capabilities="${shell_window_capabilities:-0}"
window_service_reachback="$(
  count_matches '\bbrowserManager\b|BrowserManager\(' \
    Sumi/Managers/BrowserManager/BrowserWindowTabContext.swift \
    Sumi/Managers/BrowserManager/BrowserWindowVisualCoordinator.swift
)"

# Floating-bar split: presentation state and commit routing must not regrow the
# former two-layer forwarding façade or its 17-action dependency bag.
floating_presentation_file="Sumi/Services/FloatingBarPresentationService.swift"
floating_commit_file="Sumi/Services/FloatingBarCommitService.swift"
floating_page_navigation_file="Sumi/Services/FloatingBarPageNavigationService.swift"
floating_services_group="Sumi/Services/FloatingBarServices.swift"
floating_context_factory="Sumi/Managers/BrowserManager/FloatingBarBrowserContextFactory.swift"
floating_composition="Sumi/Managers/BrowserManager/BrowserURLBarBundle+Live.swift"
for service_file in \
  "$floating_presentation_file" \
  "$floating_commit_file" \
  "$floating_page_navigation_file" \
  "$floating_services_group" \
  "$floating_context_factory" \
  "$floating_composition"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: floating-bar split service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
for retired_file in \
  Sumi/Managers/BrowserManager/BrowserFloatingBarRoutingOwner.swift \
  Sumi/Services/FloatingBarNavigationOwner.swift \
  SumiTests/FloatingBarNavigationOwnerTests.swift \
  SumiTests/BrowserFloatingBarBrowserContextOwnerTests.swift; do
  if [[ -e "$retired_file" ]]; then
    printf 'error: tombstone violated: retired floating-bar file returned: %s\n' "$retired_file" >&2
    failures=$((failures + 1))
  fi
done
retired_floating_bar_hubs="$(
  count_matches \
    'BrowserFloatingBarRoutingOwner|FloatingBarNavigationOwner|BrowserFloatingBarBrowserContextOwner|floatingBarRoutingOwner|floatingBarBrowserContextOwner' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
floating_bar_action_bags="$(
  count_matches 'struct (Actions|Dependencies)' \
    "$floating_presentation_file" \
    "$floating_commit_file" \
    "$floating_page_navigation_file"
)"
floating_bar_domain_reachback="$(
  count_matches '\bbrowserManager\b|BrowserManager\(' \
    "$floating_presentation_file" \
    "$floating_commit_file" \
    "$floating_page_navigation_file" \
    "$floating_services_group"
)"
floating_group_capabilities="$(
  rg --count-matches '^    let [A-Za-z_]' \
    "$floating_services_group" 2>/dev/null || true
)"
floating_group_capabilities="${floating_group_capabilities:-0}"
floating_group_behavior="$(count_matches '\bfunc ' "$floating_services_group")"

# Active-page split: window-scoped resolution, page commands, external URL
# opening, and sidebar drop placement must remain physically separate. The
# shell extension is composition-only; it must not hide state outside the core.
active_page_resolver="Sumi/Managers/BrowserManager/ActivePageResolver.swift"
active_page_commands="Sumi/Managers/BrowserManager/ActivePageCommandService.swift"
active_page_composition="Sumi/Managers/BrowserManager/BrowserShellRuntime+ActivePage.swift"
external_url_opening="Sumi/Services/ExternalURLTabOpeningService.swift"
sidebar_url_drop="Sumi/Components/DragDrop/SidebarURLDropService.swift"
shortcut_url_insertion="Sumi/Components/DragDrop/ShortcutURLInsertionService.swift"
for service_file in \
  "$active_page_resolver" \
  "$active_page_commands" \
  "$active_page_composition" \
  "$external_url_opening" \
  "$sidebar_url_drop" \
  "$shortcut_url_insertion"; do
  if [[ ! -f "$service_file" ]]; then
    printf 'error: active-page split service missing: %s\n' "$service_file" >&2
    failures=$((failures + 1))
  fi
done
for retired_file in \
  Sumi/Managers/BrowserManager/BrowserActivePageRoutingOwner.swift \
  SumiTests/BrowserActivePageRoutingOwnerTests.swift \
  Sumi/Managers/BrowserManager/BrowserURLBarCommands.swift; do
  if [[ -e "$retired_file" ]]; then
    printf 'error: tombstone violated: retired active-page hub returned: %s\n' "$retired_file" >&2
    failures=$((failures + 1))
  fi
done
retired_active_page_hub="$(
  count_matches \
    'BrowserActivePageRoutingOwner|activePageRoutingOwner|BrowserURLBarCommands' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
active_page_dependency_bags="$(
  count_matches 'struct (Actions|Dependencies)' \
    "$active_page_resolver" \
    "$active_page_commands" \
    "$external_url_opening" \
    "$sidebar_url_drop" \
    "$shortcut_url_insertion"
)"
active_page_domain_reachback="$(
  count_matches '\bbrowserManager\b|BrowserManager\(' \
    "$active_page_resolver" \
    "$active_page_commands" \
    "$external_url_opening" \
    "$sidebar_url_drop" \
    "$shortcut_url_insertion"
)"
active_page_composition_state="$(
  count_matches '^    (private )?(let|var|lazy var) ' "$active_page_composition"
)"
urlbar_active_page_reachthrough="$(
  count_matches 'urlBarBundle\.activePage|activePageRoutingOwner' \
    App FloatingBar SidebarChrome Settings Sumi UI SumiTests
)"
sidebar_drop_urlbar_reachthrough="$(
  count_matches 'urlBarBundle' Sumi/Components/DragDrop/SidebarDropCoordinator.swift
)"
manual_urlbar_page_resolution="$(
  count_matches 'glanceManager\.active(Session|Preview)|ephemeralTabs|tabForID' \
    Sumi/Components/Sidebar/URLBarView.swift
)"
external_url_runtime_retention="$(
  count_matches \
    'private let (windowRegistry|tabOpening)|private var (windowRegistry|tabOpening)' \
    "$external_url_opening"
)"

legacy_runtime_context_handlers="$(
  count_matches \
    '\b(visibleWebViewPreparationRuntime|cleanupScopeRuntime|hiddenCloneEvictionRuntime|deferredProtectedCommandRuntime|trackedCleanupExecutionRuntime|webViewShutdownRuntime)\s*\(' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"

# Folder collision: chrome must not live under Navigation/ (DDG product name).
if [[ -d Navigation ]] && [[ ! -L Navigation ]]; then
  printf 'error: repo folder Navigation/ must be renamed to SidebarChrome/ (DDG product collision)\n' >&2
  failures=$((failures + 1))
fi

printf '%s\n' 'Architecture hub metrics freeze'
printf '%s\n' '--------------------------------'
check_max "BrowserManager.swift LOC" "$bm_loc" 200
check_max "TabManager.swift LOC" "$tm_loc" 220
check_max "Tab.swift LOC" "$tab_model_loc" 704
check_max "Tab.swift methods" "$tab_model_methods" 34
# Exact navigation lifetime and separate same-document publication add two
# explicit capability operations. The settlement aggregate below prevents the
# split from hiding net growth behind individually small files.
check_max "TabMainFrameRuntimeTransaction.swift LOC" \
  "$tab_main_frame_transaction_loc" 702
check_max "TabMainFrameRuntimeTransaction methods" \
  "$tab_main_frame_transaction_methods" 37
check_max "TabMainFrameRuntimeCapabilities.swift LOC" \
  "$tab_main_frame_capabilities_loc" 124
check_max "TabMainFrameRuntimeCapabilities methods" \
  "$tab_main_frame_capability_methods" 23
check_max "TabMainFrameAuthorityReducer.swift LOC" \
  "$tab_main_frame_authority_reducer_loc" 661
check_max "TabMainFrameAuthorityReducer methods" \
  "$tab_main_frame_authority_reducer_methods" 25
check_max "TabMainFrameAuthorityState.swift LOC" \
  "$tab_main_frame_authority_state_loc" 152
check_max "TabMainFrameAuthorityState methods" \
  "$tab_main_frame_authority_state_methods" 10
check_max "TabMainFrameLifecycleMachine.swift LOC" \
  "$tab_main_frame_lifecycle_machine_loc" 453
check_max "TabMainFrameLifecycleMachine methods" \
  "$tab_main_frame_lifecycle_machine_methods" 20
check_max "Main-frame settlement aggregate LOC" \
  "$tab_main_frame_settlement_loc" 725
check_max "Main-frame settlement aggregate methods" \
  "$tab_main_frame_settlement_methods" 23
check_max "Lifecycle machine + settlement aggregate LOC" \
  "$((tab_main_frame_lifecycle_machine_loc + tab_main_frame_settlement_loc))" 1178
check_max "Lifecycle machine + settlement aggregate methods" \
  "$((tab_main_frame_lifecycle_machine_methods + tab_main_frame_settlement_methods))" 43
check_max "Active navigation settlement LOC" \
  "$(count_lines "${tab_main_frame_settlement_files[0]}")" 238
check_max "Active navigation settlement methods" \
  "$(rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' "${tab_main_frame_settlement_files[0]}")" 8
check_max "Active navigation settlement collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "${tab_main_frame_settlement_files[0]}")" 4
check_max "Terminal settlement LOC" \
  "$(count_lines "${tab_main_frame_settlement_files[1]}")" 211
check_max "Terminal settlement methods" \
  "$(rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' "${tab_main_frame_settlement_files[1]}")" 6
check_max "Terminal settlement collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "${tab_main_frame_settlement_files[1]}")" 4
check_max "Same-document settlement LOC" \
  "$(count_lines "${tab_main_frame_settlement_files[2]}")" 124
check_max "Same-document settlement methods" \
  "$(rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' "${tab_main_frame_settlement_files[2]}")" 3
check_max "Same-document settlement collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "${tab_main_frame_settlement_files[2]}")" 4
check_max "Promotion replay settlement LOC" \
  "$(count_lines "${tab_main_frame_settlement_files[3]}")" 88
check_max "Promotion replay settlement methods" \
  "$(rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' "${tab_main_frame_settlement_files[3]}")" 4
check_max "Promotion replay settlement collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "${tab_main_frame_settlement_files[3]}")" 4
check_max "Completed authority proof LOC" \
  "$(count_lines "${tab_main_frame_settlement_files[4]}")" 64
check_max "Completed authority proof methods" \
  "$(rg --count-matches '^\s*(public |private |internal |fileprivate )?func ' "${tab_main_frame_settlement_files[4]}")" 2
check_max "Completed authority proof collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "${tab_main_frame_settlement_files[4]}")" 3
check_exact "Retired terminal finish choreography" \
  "$retired_terminal_finish_choreography" 0
check_max "SumiTabLifecycleNavigationResponder.swift LOC" \
  "$tab_main_frame_responder_loc" 650
check_max "TabMainFrameLifecyclePromotionReducer.swift LOC" \
  "$tab_main_frame_promotion_reducer_loc" 286
check_max "TabMainFrameLoadRuntime.swift LOC" \
  "$tab_main_frame_load_runtime_loc" 302
check_max "TabMainFrameLoadRuntime methods" \
  "$tab_main_frame_load_runtime_methods" 40
check_max "TabMainFrameLoadRuntime collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "$tab_main_frame_load_runtime")" 2
check_max "TabWebContentRecoveryMarkerLedger.swift LOC" \
  "$tab_recovery_marker_ledger_loc" 44
check_max "TabWebContentRecoveryMarkerLedger methods" \
  "$tab_recovery_marker_ledger_methods" 3
check_max "TabWebContentRecoveryMarkerLedger stored state" \
  "$(rg --count-matches '^    private (let|var|weak var) [a-zA-Z_]' "$tab_recovery_marker_ledger")" 1
# 294 → 299: read-only canonical-document authority proof exposed for exact
# action-invocation admission (no new mutation surface).
check_max "TabCommittedDocumentRuntime.swift LOC" \
  "$tab_committed_document_runtime_loc" 299
check_max "TabCommittedDocumentRuntime methods" \
  "$tab_committed_document_runtime_methods" 22
check_max "TabCommittedDocumentRuntime collaborators" \
  "$(rg --count-matches '^    private (let|weak var) [a-zA-Z_]' "$tab_committed_document_runtime")" 3
check_exact "Retired Tab profile-assignment facade" \
  "$retired_tab_profile_assignment_facade" 0
check_exact "Tab profile mutation outside transaction services" \
  "$tab_profile_assignment_mutation_outside_services" 0
check_max "BrowserWindowSessionBundle.swift LOC" "$window_session_bundle_loc" 120
check_max "BrowserWindowSessionBundle capabilities" "$window_session_capabilities" 6
check_max "BrowserShellRuntime.swift LOC" "$shell_runtime_loc" 160
check_max "BrowserShellRuntime window capabilities" "$shell_window_capabilities" 3
check_max "BrowserWebViewRoutingService.swift LOC" "$webview_routing_loc" 380
check_max "BrowserWindowCommands.swift LOC" "$window_commands_loc" 100
check_max "BrowserWindowStateReconciler.swift LOC" "$window_reconciler_loc" 75
check_max "BrowserWindowStateReconciler collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/BrowserWindowStateReconciler.swift)" 6
check_max "BrowserWindowSelectionRepairService.swift LOC" "$(count_lines "$window_selection_repair_file")" 115
check_max "BrowserWindowSelectionRepairService collaborators" "$(count_stored_collaborators "$window_selection_repair_file")" 5
check_max "BrowserWindowSpaceContextReconciler.swift LOC" "$(count_lines "$window_space_context_file")" 100
check_max "BrowserWindowSpaceContextReconciler collaborators" "$(count_stored_collaborators "$window_space_context_file")" 2
check_max "FocusedSpaceRuntimeStateSynchronizer.swift LOC" "$(count_lines "$focused_space_runtime_file")" 50
check_max "Focused Space runtime collaborators" "$(count_stored_collaborators "$focused_space_runtime_file")" 3
check_max "SpaceProfileRuntimeStateService.swift LOC" "$(count_lines "$space_profile_runtime_file")" 50
check_max "SpaceProfileRuntimeStateService collaborators" "$(count_stored_collaborators "$space_profile_runtime_file")" 3
check_max "Retired profile runtime Owner surface" "$retired_profile_runtime_owner" 0
check_exact "Profile runtime / window-context regrowth" "$profile_runtime_window_context_regrowth" 0
check_exact "Profile runtime / persistence coupling" "$profile_runtime_persistence_coupling" 0
check_max "BrowserWindowSpaceTransitionService.swift LOC" "$window_space_transition_loc" 100
check_max "BrowserWindowSpaceTransitionService collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService.swift)" 8
check_max "Window Space transition live composition LOC" "$window_space_transition_live_loc" 85
check_max "Window Space transition live stored state" "$(count_stored_collaborators Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift)" 0
check_max "BrowserWindowSpaceSelectionHandoff.swift LOC" "$(count_lines "$window_space_selection_handoff_file")" 65
check_max "BrowserWindowSpaceSelectionHandoff collaborators" "$(count_stored_collaborators "$window_space_selection_handoff_file")" 4
check_max "BrowserWindowSpaceContextTransition.swift LOC" "$(count_lines "$window_space_context_transition_file")" 80
check_max "BrowserWindowSpaceContextTransition collaborators" "$(count_stored_collaborators "$window_space_context_transition_file")" 5
check_exact "Retired window Space state Owner" "$retired_window_space_state_owner" 0
check_max "BrowserManager peer lazy *Owner" "$bm_peer_owners" 0
check_max "BrowserManager façade *Owner accessors" "$bm_facade_owner_accessors" 0
check_max "BrowserManager capability bundles" "$bm_bundles" 7
check_max "BrowserManager bundled capabilities" "$bm_bundle_capabilities" 26
check_max "Retired app command/lifecycle hubs" "$retired_app_command_hubs" 0
check_max "Retired window-session reach-through" "$retired_window_session_reachthrough" 0
check_max "Retired stateless routing objects" "$retired_stateless_routing_objects" 0
check_max "Retired recently-closed restore owner" "$retired_recently_closed_restore" 0
check_max "Session recovery domain BM/menu reachback" "$session_recovery_reachback" 0
check_max "Mutable session restore identity" "$mutable_session_restore_identity" 0
check_max "ClosedTabRestoreService.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/ClosedTabRestoreService.swift)" 90
check_max "ClosedTabRestoreService stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/ClosedTabRestoreService.swift)" 3
check_max "ClosedShortcutRestoreService.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/ClosedShortcutRestoreService.swift)" 190
check_max "ClosedShortcutRestoreService stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/ClosedShortcutRestoreService.swift)" 5
check_max "WindowSessionReopenService.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/WindowSessionReopenService.swift)" 90
check_max "WindowSessionReopenService stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/WindowSessionReopenService.swift)" 4
check_max "LastSessionWindowsRestoreService.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift)" 110
check_max "LastSessionWindowsRestoreService stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift)" 5
check_max "RecentlyClosedItemReopenService.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/RecentlyClosedItemReopenService.swift)" 80
check_max "RecentlyClosedItemReopenService stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/RecentlyClosedItemReopenService.swift)" 5
check_max "BrowserSessionRecoveryCommands.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands.swift)" 55
check_max "BrowserSessionRecoveryCommands stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands.swift)" 3
check_max "Session recovery live composition LOC" "$(count_lines "$session_recovery_composition")" 85
check_max "Session recovery live composition stored state" "$(count_stored_collaborators "$session_recovery_composition")" 0
check_max "BrowserHistoryClearCommand.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/BrowserHistoryClearCommand.swift)" 65
check_max "Retired window-session pending-write API" "$retired_window_session_pending_write" 0
check_max "Durable window write live/scheduler reachback" "$durable_write_archive_reachback" 0
check_max "Restore service raw persistence dependency" "$restore_raw_persistence_dependency" 0
check_max "Raw durable API outside coordinator" "$raw_durable_api_outside_coordinator" 0
check_max "Retired window-history session owner" "$retired_window_history_owner" 0
check_max "OpenWindowSessionCatalog.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/OpenWindowSessionCatalog.swift)" 45
check_max "OpenWindowSessionCatalog stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/OpenWindowSessionCatalog.swift)" 2
check_max "LastSessionWindowArchive.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift)" 125
check_max "LastSessionWindowArchive stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift)" 3
check_max "StartupWindowRestoreService.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/StartupWindowRestoreService.swift)" 150
check_max "StartupWindowRestoreService stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/StartupWindowRestoreService.swift)" 6
check_max "CleanStartupWorkflow.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/CleanStartupWorkflow.swift)" 140
check_max "CleanStartupWorkflow stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/CleanStartupWorkflow.swift)" 7
check_max "BrowserStartupPolicy.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/BrowserStartupPolicy.swift)" 45
check_max "BrowserStartupPolicy stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/BrowserStartupPolicy.swift)" 3
check_max "ClosedWindowHistoryRecorder.swift LOC" "$(count_lines Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift)" 45
check_max "ClosedWindowHistoryRecorder stored collaborators" "$(count_stored_collaborators Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift)" 3
check_max "WindowSessionHistoryServices capabilities" "$window_history_group_capabilities" 3
check_max "WindowSessionHistoryServices behavior methods" "$window_history_group_behavior" 0
check_max "WindowSessionHistoryServices.swift LOC" "$(count_lines "$window_history_group")" 20
check_max "Window-history live composition LOC" "$(count_lines "$window_history_composition")" 65
check_max "Window-history live composition stored state" "$(count_stored_collaborators "$window_history_composition")" 0
check_max "Window-history domain BrowserManager reachback" "$window_history_reachback" 0
check_max "Window service BrowserManager reachback" "$window_service_reachback" 0
check_exact "Retired floating-bar forwarding hubs" "$retired_floating_bar_hubs" 0
check_exact "Floating-bar Actions/Dependencies bags" "$floating_bar_action_bags" 0
check_exact "Floating-bar domain BrowserManager reachback" "$floating_bar_domain_reachback" 0
check_exact "FloatingBarServices capabilities" "$floating_group_capabilities" 3
check_exact "FloatingBarServices behavior methods" "$floating_group_behavior" 0
check_max "FloatingBarPresentationService.swift LOC" "$(count_lines "$floating_presentation_file")" 170
check_max "Floating-bar presentation collaborators" "$(count_stored_collaborators "$floating_presentation_file")" 5
check_max "FloatingBarCommitService.swift LOC" "$(count_lines "$floating_commit_file")" 235
check_max "Floating-bar commit collaborators" "$(count_stored_collaborators "$floating_commit_file")" 6
check_max "FloatingBarPageNavigationService.swift LOC" "$(count_lines "$floating_page_navigation_file")" 75
check_max "Floating-bar page-navigation collaborators" "$(count_stored_collaborators "$floating_page_navigation_file")" 2
check_max "FloatingBarBrowserContextFactory.swift LOC" "$(count_lines "$floating_context_factory")" 70
check_max "Floating-bar context-factory collaborators" "$(count_stored_collaborators "$floating_context_factory")" 6
check_max "Floating-bar live composition LOC" "$(count_lines "$floating_composition")" 120
check_max "Floating-bar live composition stored state" "$(count_stored_collaborators "$floating_composition")" 0
check_exact "Retired active-page routing hubs" "$retired_active_page_hub" 0
check_exact "Active-page Actions/Dependencies bags" "$active_page_dependency_bags" 0
check_exact "Active-page domain BrowserManager reachback" "$active_page_domain_reachback" 0
check_exact "Active-page live composition stored state" "$active_page_composition_state" 0
check_exact "URL-bar active-page reach-through" "$urlbar_active_page_reachthrough" 0
check_exact "Sidebar drop URL-bar reach-through" "$sidebar_drop_urlbar_reachthrough" 0
check_exact "Manual URL-bar active-page resolution" "$manual_urlbar_page_resolution" 0
check_exact "External URL runtime strong retention" "$external_url_runtime_retention" 0
check_max "ActivePageResolver.swift LOC" "$(count_lines "$active_page_resolver")" 120
check_max "Active-page resolver collaborators" "$(count_stored_collaborators "$active_page_resolver")" 4
check_max "ActivePageCommandService.swift LOC" "$(count_lines "$active_page_commands")" 130
check_max "Active-page command collaborators" "$(count_stored_collaborators "$active_page_commands")" 5
check_max "Active-page live composition LOC" "$(count_lines "$active_page_composition")" 40
check_max "ExternalURLTabOpeningService.swift LOC" "$(count_lines "$external_url_opening")" 55
check_max "External URL opening collaborators" "$(count_stored_collaborators "$external_url_opening")" 2
check_max "SidebarURLDropService.swift LOC" "$(count_lines "$sidebar_url_drop")" 150
check_max "Sidebar URL-drop collaborators" "$(count_stored_collaborators "$sidebar_url_drop")" 4
check_max "ShortcutURLInsertionService.swift LOC" "$(count_lines "$shortcut_url_insertion")" 110
check_max "Shortcut URL-insertion collaborators" "$(count_stored_collaborators "$shortcut_url_insertion")" 5
check_max "Retired Tab Space lifecycle owner" "$retired_tab_space_lifecycle" 0
check_exact "Retired tab creation resolver API" "$retired_tab_creation_resolver_api" 0
check_exact "Mutable BrowserManager TabManager" "$mutable_browser_tab_manager" 0
check_exact "BrowserManager TabManager reassignment" "$browser_tab_manager_reassignment" 0
check_exact "TabSpaceServices capabilities" "$tab_space_group_capabilities" 4
check_max "TabSpaceServices behavior methods" "$tab_space_group_behavior" 0
check_max "Space services TabManager reachback" "$tab_space_reachback" 0
check_max "SpaceCatalogCommands.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceCatalogCommands.swift)" 135
check_max "SpaceCatalogCommands stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceCatalogCommands.swift)" 7
check_max "SpaceRemovalService.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceRemovalService.swift)" 75
check_max "SpaceRemovalService stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceRemovalService.swift)" 6
check_max "SpaceContentRetirementService.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceContentRetirementService.swift)" 80
check_max "SpaceContentRetirementService stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceContentRetirementService.swift)" 5
check_max "SpaceSplitGroupRetirementService.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceSplitGroupRetirementService.swift)" 65
check_max "Space split-group retirement collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceSplitGroupRetirementService.swift)" 2
check_max "SpaceTabInventory.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceTabInventory.swift)" 40
check_max "SpaceTabInventory stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceTabInventory.swift)" 0
check_max "DeletedSpaceWindowStateReconciler.swift LOC" "$(count_lines Sumi/Managers/TabManager/DeletedSpaceWindowStateReconciler.swift)" 135
check_max "DeletedSpaceWindowStateReconciler collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/DeletedSpaceWindowStateReconciler.swift)" 1
check_max "DeletedSpaceWindowReferencePruner.swift LOC" "$(count_lines Sumi/Managers/TabManager/DeletedSpaceWindowReferencePruner.swift)" 120
check_max "Deleted Space reference pruner collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/DeletedSpaceWindowReferencePruner.swift)" 0
check_max "TabRuntimeTeardownService.swift LOC" "$(count_lines Sumi/Managers/TabManager/TabRuntimeTeardownService.swift)" 65
check_max "TabRuntimeTeardownService stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/TabRuntimeTeardownService.swift)" 3
check_max "SpaceActivationService.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceActivationService.swift)" 160
check_max "SpaceActivationService stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceActivationService.swift)" 6
check_max "TabCreationPlacementService.swift LOC" "$(count_lines Sumi/Managers/TabManager/TabCreationPlacementService.swift)" 135
check_max "TabCreationPlacementService stored collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/TabCreationPlacementService.swift)" 5
check_max "SpaceProfileTransitionService.swift LOC" "$(count_lines Sumi/Managers/TabManager/SpaceProfileTransitionService.swift)" 355
check_max "Space profile transition collaborators" "$(count_stored_collaborators Sumi/Managers/TabManager/SpaceProfileTransitionService.swift)" 3
check_max "PendingTabProfileInheritance.swift LOC" "$(count_lines "$pending_profile_inheritance_file")" 180
check_max "Pending profile inheritance collaborators" "$(count_stored_collaborators "$pending_profile_inheritance_file")" 0
check_exact "Embedded Space creation-follower state" "$space_profile_embedded_follower_state" 0
check_exact "Pending profile inheritance construction" "$pending_profile_inheritance_construction" 1
check_exact "Shared pending profile inheritance wiring" "$pending_profile_inheritance_wiring" 2
check_max "TabSpace live composition LOC" "$(count_lines "$tab_space_composition")" 95
check_max "Tab lifecycle bag capabilities" "$tab_lifecycle_bag_capabilities" 9
check_exact "Retired shortcut retirement surface" "$retired_shortcut_retirement_surface" 0
check_exact "Shortcut retirement Owner/bag regrowth" "$shortcut_retirement_owner_regrowth" 0
check_exact "Shortcut retirement physical cleanup duplication" "$shortcut_retirement_physical_cleanup" 0
check_exact "Shortcut retirement browser/notification policy" "$shortcut_retirement_browser_policy" 0
check_exact "Retired shortcut live-tab god surface" "$retired_shortcut_live_hub" 0
check_exact "Shortcut live services hidden in Owner bag/accessor" "$shortcut_live_bag_reach" 0
check_exact "Shortcut live closure Dependencies bags" "$shortcut_dependency_bags" 0
check_exact "Retired split-shortcut routing hub" "$retired_split_shortcut_hub" 0
check_exact "SplitShortcutServices capabilities" "$split_shortcut_group_capabilities" 3
check_exact "SplitShortcutServices behavior methods" "$split_shortcut_group_behavior" 0
check_exact "Split-shortcut Actions/Dependencies bags" "$split_shortcut_dependency_bags" 0
check_exact "Split-shortcut domain BrowserManager reachback" "$split_shortcut_domain_reachback" 0
check_exact "Launcher placement manager reachback" "$split_shortcut_launcher_reachback" 0
check_exact "Split-shortcut live composition stored state" "$split_shortcut_composition_state" 0
check_exact "Split-shortcut runtime lease providers" "$split_shortcut_runtime_providers" 3
check_exact "Split services stored runtime managers" "$split_shortcut_stored_runtime_managers" 0
check_exact "Split services separate runtime providers" "$split_shortcut_separate_runtime_providers" 0
check_exact "Split command runtime lease acquisitions" "$split_shortcut_runtime_lease_acquisitions" 4
check_exact "SplitShortcutRuntimeLease capabilities" "$split_shortcut_runtime_lease_capabilities" 1
check_exact "Split live weak runtime provider" "$split_shortcut_live_weak_runtime_provider" 1
check_max "SplitShortcutRuntimeLease.swift LOC" "$(count_lines "$split_shortcut_runtime_lease")" 8
check_max "SplitShortcutFocusService.swift LOC" "$(count_lines "$split_shortcut_focus")" 178
check_max "SplitShortcutFocusService collaborators" "$(count_stored_collaborators "$split_shortcut_focus")" 4
check_max "WindowSplitMaterializationService.swift LOC" "$(count_lines "$split_shortcut_materialization")" 110
check_max "Window split materialization collaborators" "$(count_stored_collaborators "$split_shortcut_materialization")" 0
check_max "SplitShortcutMemberResolver.swift LOC" "$(count_lines "$split_shortcut_resolver")" 90
check_max "SplitShortcutMemberResolver collaborators" "$(count_stored_collaborators "$split_shortcut_resolver")" 0
check_max "SplitShortcutMemberRestoreService.swift LOC" "$(count_lines "$split_shortcut_restore")" 192
check_max "SplitShortcutMemberRestoreService collaborators" "$(count_stored_collaborators "$split_shortcut_restore")" 7
check_max "ShortcutSplitLauncherPlacementService.swift LOC" "$(count_lines "$split_shortcut_launcher")" 90
check_max "ShortcutSplitLauncherPlacementService collaborators" "$(count_stored_collaborators "$split_shortcut_launcher")" 4
check_max "ShortcutSplitLauncherDestinationResolver LOC" "$(count_lines "$split_shortcut_launcher_resolver")" 60
check_max "Shortcut launcher destination collaborators" "$(count_stored_collaborators "$split_shortcut_launcher_resolver")" 2
check_max "ShortcutSplitLauncherMoveTransaction LOC" "$(count_lines "$split_shortcut_launcher_transaction")" 85
check_max "Shortcut launcher move collaborators" "$(count_stored_collaborators "$split_shortcut_launcher_transaction")" 3
check_max "ShortcutSplitLauncherCatalogAdapter LOC" "$(count_lines "$split_shortcut_launcher_catalog")" 65
check_max "Shortcut launcher catalog collaborators" "$(count_stored_collaborators "$split_shortcut_launcher_catalog")" 1
check_max "ShortcutSplitLauncherPlacement live composition LOC" "$(count_lines "$split_shortcut_launcher_composition")" 40
check_max "ShortcutSplitLauncherPlacement live stored state" "$(count_stored_collaborators "$split_shortcut_launcher_composition")" 0
check_max "ShortcutHostedSplitUnloadService.swift LOC" "$(count_lines "$split_shortcut_unload")" 105
check_max "ShortcutHostedSplitUnloadService collaborators" "$(count_stored_collaborators "$split_shortcut_unload")" 6
check_max "SidebarSplitCommands.swift LOC" "$(count_lines "$split_shortcut_sidebar_commands")" 30
check_max "SidebarSplitCommands live composition LOC" "$(count_lines "$split_shortcut_sidebar_commands_composition")" 60
check_max "Split-shortcut live composition LOC" "$(count_lines "$split_shortcut_composition")" 138
check_exact "Retired shortcut live close Owner" "$retired_shortcut_live_close_owner" 0
check_max "ShortcutLiveTabCloseService.swift LOC" "$(count_lines "$shortcut_live_close")" 145
check_max "ShortcutLiveTabCloseService collaborators" "$(count_stored_collaborators "$shortcut_live_close")" 9
check_max "LiveShortcutTabRegistry.swift LOC" "$(count_lines "$shortcut_registry_file")" 175
check_max "LiveShortcutTabRegistry collaborators" "$(count_stored_collaborators "$shortcut_registry_file")" 2
check_max "LiveShortcutTabSnapshot.swift LOC" "$(count_lines "$shortcut_registry_snapshot")" 45
check_max "Live shortcut snapshot collaborators" "$(count_stored_collaborators "$shortcut_registry_snapshot")" 0
check_max "ShortcutTabWindowQuery.swift LOC" "$(count_lines "$shortcut_window_query_file")" 110
check_max "ShortcutTabWindowQuery collaborators" "$(count_stored_collaborators "$shortcut_window_query_file")" 1
check_max "ShortcutTabBindingSynchronizer.swift LOC" "$(count_lines "$shortcut_binding_file")" 200
check_max "ShortcutTabBindingSynchronizer collaborators" "$(count_stored_collaborators "$shortcut_binding_file")" 5
check_max "ShortcutTabMaterializer.swift LOC" "$(count_lines "$shortcut_materializer_file")" 100
check_max "ShortcutTabMaterializer collaborators" "$(count_stored_collaborators "$shortcut_materializer_file")" 5
check_exact "Unsafe shortcut conversion phase API" "$unsafe_shortcut_conversion_phase_api" 0
check_exact "Retired shortcut conversion hubs" "$retired_shortcut_conversion_hubs" 0
check_max "RegularTabShortcutConversionService.swift LOC" "$(count_lines "$regular_shortcut_conversion_file")" 125
check_max "Regular tab shortcut conversion collaborators" "$(count_stored_collaborators "$regular_shortcut_conversion_file")" 8
check_max "Regular tab shortcut conversion live LOC" "$(count_lines "$regular_shortcut_conversion_live")" 75
check_max "Regular tab shortcut conversion live stored state" "$(count_stored_collaborators "$regular_shortcut_conversion_live")" 0
check_max "ShortcutPinToRegularTabService.swift LOC" "$(count_lines "$shortcut_pin_promotion_file")" 65
check_max "Shortcut pin promotion collaborators" "$(count_stored_collaborators "$shortcut_pin_promotion_file")" 4
check_max "RegularTabShortcutConversionPlanner.swift LOC" "$(count_lines "$shortcut_conversion_planner_file")" 85
check_max "Regular tab shortcut conversion planner collaborators" "$(count_stored_collaborators "$shortcut_conversion_planner_file")" 3
check_max "Displayed conversion committer LOC" "$(count_lines "$shortcut_conversion_committer_file")" 90
check_max "Displayed conversion committer collaborators" "$(count_stored_collaborators "$shortcut_conversion_committer_file")" 4
check_max "Tab shortcut conversion authorizer LOC" "$(count_lines "$shortcut_conversion_authorizer_file")" 110
check_max "Tab shortcut conversion authorizer collaborators" "$(count_stored_collaborators "$shortcut_conversion_authorizer_file")" 1
check_max "RegularTabShortcutStructureTransition.swift LOC" "$(count_lines "$shortcut_structure_transition_file")" 115
check_max "RegularTabShortcutStructureTransition collaborators" "$(count_stored_collaborators "$shortcut_structure_transition_file")" 4
check_max "Regular tab shortcut structure plan LOC" "$(count_lines "$shortcut_structure_plan_file")" 105
check_max "Regular tab shortcut structure plan collaborators" "$(count_stored_collaborators "$shortcut_structure_plan_file")" 4
check_max "DisplayedTabShortcutWindowTransition.swift LOC" "$(count_lines "$shortcut_window_transition_file")" 45
check_max "DisplayedTabShortcutWindowTransition collaborators" "$(count_stored_collaborators "$shortcut_window_transition_file")" 0
check_max "ShortcutTabPromotionService.swift LOC" "$(count_lines "$shortcut_promotion_file")" 170
check_max "ShortcutTabPromotionService collaborators" "$(count_stored_collaborators "$shortcut_promotion_file")" 8
check_max "ShortcutLiveTabRetirementService.swift LOC" "$(count_lines "$shortcut_retirement_file")" 150
check_max "ShortcutLiveTabRetirementService collaborators" "$(count_stored_collaborators "$shortcut_retirement_file")" 4
check_max "ShortcutSelectionReconciler.swift LOC" "$(count_lines "$shortcut_selection_file")" 90
check_max "ShortcutSelectionReconciler collaborators" "$(count_stored_collaborators "$shortcut_selection_file")" 0
check_max "ShortcutSelectionTransition.swift LOC" "$(count_lines "$shortcut_selection_transition_file")" 185
check_max "ShortcutSelectionTransition collaborators" "$(count_stored_collaborators "$shortcut_selection_transition_file")" 0
check_max "TabManager peer lazy *Owner" "$tm_peer_owners" 0
check_max "TabManager hidden *Owners bags" "$tm_owner_bags" 3
check_max "TabManager forwarding *Owner accessors" "$tm_facade_owner_accessors" 26
check_max "static func live(browserManager:)" "$live_bm" 40
check_max "static func live(tabManager:)" "$live_tm" 40
# W1: direct closure-runtime factories were replaced by typed attached contexts.
check_max "Legacy runtime-context handlers" "$legacy_runtime_context_handlers" 0

if (( failures > 0 )); then
  exit 1
fi

printf '\narchitecture hub metrics freeze passed\n'
