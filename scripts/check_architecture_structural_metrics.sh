#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

# Living components are measured only on generic complexity dimensions. Exact
# method names, constructor counts and test names belong to types and tests,
# not to a shell copy of the implementation. Generic ceilings remain until the
# measured surface is physically deleted. A missing living source is an
# infrastructure error, never a zero-line success.
role_budgets=(
  "BrowserManager|Sumi/Managers/BrowserManager/BrowserManager.swift|200|-"
  "TabManager|Sumi/Managers/TabManager/TabManager.swift|220|-"
  "Tab model|Sumi/Models/Tab/Tab.swift|704|-"
  "ExtensionManager (item 6/7 transition ceiling)|Sumi/Managers/ExtensionManager/ExtensionManager.swift|1050|-"
  "Tab extension page runtime (item 17 transition ceiling)|Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift|1000|-"

  "Normal WebView setup|Sumi/Models/Tab/TabNormalWebViewSetupService.swift|300|-"
  "Main-frame transaction|Sumi/Models/Tab/TabMainFrameRuntimeTransaction.swift|702|-"
  "Main-frame runtime capabilities|Sumi/Models/Tab/TabMainFrameRuntimeCapabilities.swift|124|-"
  "Main-frame runtime types|Sumi/Models/Tab/TabMainFrameRuntimeTypes.swift|215|-"
  "Main-frame transition output|Sumi/Models/Tab/TabMainFrameTransitionOutput.swift|60|-"
  "Web-content recovery capabilities|Sumi/Models/Tab/TabWebContentRecoveryCapabilities.swift|20|-"
  "Main-frame authority reducer|Sumi/Models/Tab/TabMainFrameAuthorityReducer.swift|661|-"
  "Main-frame authority state|Sumi/Models/Tab/TabMainFrameAuthorityState.swift|152|-"
  "Main-frame participant registry|Sumi/Models/Tab/TabMainFrameParticipantRegistry.swift|729|-"
  "Main-frame lifecycle machine|Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift|453|-"
  "Active-navigation settlement|Sumi/Models/Tab/TabMainFrameActiveNavigationSettlement.swift|238|4"
  "Terminal settlement|Sumi/Models/Tab/TabMainFrameTerminalSettlement.swift|211|4"
  "Same-document settlement|Sumi/Models/Tab/TabMainFrameSameDocumentSettlement.swift|124|4"
  "Promotion-replay settlement|Sumi/Models/Tab/TabMainFramePromotionReplaySettlement.swift|88|4"
  "Completed-authority proof|Sumi/Models/Tab/TabMainFrameCompletedAuthorityProof.swift|64|3"
  "Main-frame authority effect ledger|Sumi/Models/Tab/TabMainFrameAuthorityEffectLedger.swift|270|-"
  "Main-frame participant effect ledger|Sumi/Models/Tab/TabMainFrameParticipantEffectLedger.swift|150|-"
  "Main-frame navigation responder|Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift|650|-"
  "Main-frame lifecycle promotion reducer|Sumi/Models/Tab/Navigation/TabMainFrameLifecyclePromotionReducer.swift|286|-"
  "Main-frame load runtime|Sumi/Models/Tab/TabMainFrameLoadRuntime.swift|302|2"
  "Main-frame participant applier|Sumi/Models/Tab/TabMainFrameParticipantTransitionApplier.swift|380|4"
  "Main-frame authority applier|Sumi/Models/Tab/TabMainFrameAuthorityTransitionApplier.swift|160|4"
  "Main-frame continuation applier|Sumi/Models/Tab/TabMainFrameContinuationTransitionApplier.swift|145|-"
  "Main-frame transition committer|Sumi/Models/Tab/TabMainFrameTransitionCommitter.swift|220|4"
  "Main-frame target committer|Sumi/Models/Tab/TabMainFrameTargetTransitionCommitter.swift|80|-"
  "Web-content recovery marker ledger|Sumi/Models/Tab/TabWebContentRecoveryMarkerLedger.swift|44|-"
  "Committed-document runtime|Sumi/Models/Tab/TabCommittedDocumentRuntime.swift|299|3"

  "Browser shell runtime|Sumi/Managers/BrowserManager/BrowserShellRuntime.swift|160|-"
  "Browser window session bundle|Sumi/Managers/BrowserManager/BrowserWindowSessionBundle.swift|120|-"
  "Browser WebView routing|Sumi/Services/BrowserWebViewRoutingService.swift|380|-"
  "Browser window commands|Sumi/Managers/BrowserManager/BrowserWindowCommands.swift|100|-"
  "Window-state reconciler|Sumi/Managers/BrowserManager/BrowserWindowStateReconciler.swift|75|6"
  "Window-selection repair|Sumi/Managers/BrowserManager/BrowserWindowSelectionRepairService.swift|115|5"
  "Window Space-context reconciler|Sumi/Managers/BrowserManager/BrowserWindowSpaceContextReconciler.swift|100|2"
  "Focused Space runtime synchronizer|Sumi/Managers/BrowserManager/FocusedSpaceRuntimeStateSynchronizer.swift|50|3"
  "Space profile runtime service|Sumi/Managers/TabManager/SpaceProfileRuntimeStateService.swift|50|3"
  "Window Space transition|Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService.swift|100|8"
  "Window Space transition live composition|Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift|85|-"
  "Window Space selection handoff|Sumi/Managers/BrowserManager/BrowserWindowSpaceSelectionHandoff.swift|65|4"
  "Window Space context transition|Sumi/Managers/BrowserManager/BrowserWindowSpaceContextTransition.swift|80|5"

  "Closed-tab restore|Sumi/Managers/BrowserManager/ClosedTabRestoreService.swift|90|3"
  "Closed-shortcut restore|Sumi/Managers/BrowserManager/ClosedShortcutRestoreService.swift|190|5"
  "Window-session reopen|Sumi/Managers/BrowserManager/WindowSessionReopenService.swift|90|4"
  "Last-session windows restore|Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift|110|5"
  "Recently-closed item reopen|Sumi/Managers/BrowserManager/RecentlyClosedItemReopenService.swift|80|5"
  "Session recovery commands|Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands.swift|55|3"
  "Session recovery live composition|Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands+Live.swift|85|-"
  "History-clear command|Sumi/Managers/BrowserManager/BrowserHistoryClearCommand.swift|65|-"
  "Startup window restore|Sumi/Managers/BrowserManager/StartupWindowRestoreService.swift|150|6"
  "Clean startup workflow|Sumi/Managers/BrowserManager/CleanStartupWorkflow.swift|140|7"
  "Startup policy|Sumi/Managers/BrowserManager/BrowserStartupPolicy.swift|45|3"
  "Open-window session catalog|Sumi/Managers/BrowserManager/OpenWindowSessionCatalog.swift|45|2"
  "Last-session archive|Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift|125|3"
  "Closed-window history recorder|Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift|45|3"
  "Window-session history capabilities|Sumi/Managers/BrowserManager/WindowSessionHistoryServices.swift|20|-"
  "Window-history live composition|Sumi/Managers/BrowserManager/WindowSessionHistoryServices+Live.swift|65|-"

  "Floating-bar presentation|Sumi/Services/FloatingBarPresentationService.swift|170|5"
  "Floating-bar commit|Sumi/Services/FloatingBarCommitService.swift|235|6"
  "Floating-bar page navigation|Sumi/Services/FloatingBarPageNavigationService.swift|75|2"
  "Floating-bar context factory|Sumi/Managers/BrowserManager/FloatingBarBrowserContextFactory.swift|70|6"
  "Floating-bar live composition|Sumi/Managers/BrowserManager/BrowserURLBarBundle+Live.swift|120|-"
  "Active-page resolver|Sumi/Managers/BrowserManager/ActivePageResolver.swift|120|4"
  "Active-page commands|Sumi/Managers/BrowserManager/ActivePageCommandService.swift|130|5"
  "Active-page live composition|Sumi/Managers/BrowserManager/BrowserShellRuntime+ActivePage.swift|40|-"
  "External URL opening|Sumi/Services/ExternalURLTabOpeningService.swift|55|2"
  "Sidebar URL drop|Sumi/Components/DragDrop/SidebarURLDropService.swift|150|4"
  "Shortcut URL insertion|Sumi/Components/DragDrop/ShortcutURLInsertionService.swift|110|5"

  "Space catalog commands|Sumi/Managers/TabManager/SpaceCatalogCommands.swift|135|7"
  "Space removal|Sumi/Managers/TabManager/SpaceRemovalService.swift|75|6"
  "Space activation|Sumi/Managers/TabManager/SpaceActivationService.swift|160|6"
  "Tab creation placement|Sumi/Managers/TabManager/TabCreationPlacementService.swift|135|5"
  "Space profile transition|Sumi/Managers/TabManager/SpaceProfileTransitionService.swift|355|3"
  "Space content retirement|Sumi/Managers/TabManager/SpaceContentRetirementService.swift|80|5"
  "Space content retirement transaction|Sumi/Managers/TabManager/SpaceContentRetirementTransaction.swift|65|4"
  "Space split-group retirement|Sumi/Managers/TabManager/SpaceSplitGroupRetirementService.swift|65|2"
  "Space tab inventory|Sumi/Managers/TabManager/SpaceTabInventory.swift|40|0"
  "Deleted-Space window-state reconciler|Sumi/Managers/TabManager/DeletedSpaceWindowStateReconciler.swift|135|1"
  "Deleted-Space window-reference pruner|Sumi/Managers/TabManager/DeletedSpaceWindowReferencePruner.swift|120|0"
  "Tab runtime teardown|Sumi/Managers/TabManager/TabRuntimeTeardownService.swift|65|3"
  "Tab runtime teardown preparation|Sumi/Managers/TabManager/TabRuntimeTeardownPreparationService.swift|30|0"
  "Pending profile inheritance|Sumi/Managers/TabManager/PendingTabProfileInheritance.swift|180|0"
  "Tab Space live composition|Sumi/Managers/TabManager/TabSpaceServices+Live.swift|95|-"

  "Live shortcut registry|Sumi/Managers/TabManager/LiveShortcutTabRegistry.swift|175|2"
  "Live shortcut snapshot|Sumi/Managers/TabManager/LiveShortcutTabSnapshot.swift|45|0"
  "Shortcut tab window query|Sumi/Managers/TabManager/ShortcutTabWindowQuery.swift|110|1"
  "Shortcut binding synchronizer|Sumi/Managers/TabManager/ShortcutTabBindingSynchronizer.swift|200|5"
  "Shortcut tab materializer|Sumi/Managers/TabManager/ShortcutTabMaterializer.swift|100|5"
  "Regular shortcut conversion|Sumi/Managers/TabManager/RegularTabShortcutConversionService.swift|125|8"
  "Regular shortcut conversion live composition|Sumi/Managers/TabManager/RegularTabShortcutConversionService+Live.swift|75|-"
  "Shortcut pin-to-regular promotion|Sumi/Managers/TabManager/ShortcutPinToRegularTabService.swift|65|4"
  "Regular shortcut conversion planner|Sumi/Managers/TabManager/RegularTabShortcutConversionPlanner.swift|85|3"
  "Displayed shortcut conversion committer|Sumi/Managers/TabManager/DisplayedTabShortcutConversionCommitter.swift|90|4"
  "Shortcut conversion authorizer|Sumi/Managers/TabManager/TabShortcutConversionAuthorizer.swift|110|1"
  "Regular shortcut structure transition|Sumi/Managers/TabManager/RegularTabShortcutStructureTransition.swift|115|4"
  "Regular shortcut structure plan|Sumi/Managers/TabManager/RegularTabShortcutStructurePlan.swift|105|4"
  "Displayed shortcut window transition|Sumi/Managers/TabManager/DisplayedTabShortcutWindowTransition.swift|45|0"
  "Shortcut promotion|Sumi/Managers/TabManager/ShortcutTabPromotionService.swift|170|8"
  "Shortcut retirement|Sumi/Managers/TabManager/ShortcutLiveTabRetirementService.swift|150|4"
  "Shortcut retirement transaction|Sumi/Managers/TabManager/ShortcutLiveTabRetirementTransaction.swift|105|4"
  "Shortcut selection reconciler|Sumi/Managers/TabManager/ShortcutSelectionReconciler.swift|90|0"
  "Shortcut selection transition|Sumi/Managers/TabManager/ShortcutSelectionTransition.swift|185|0"
  "Live shortcut close|Sumi/Managers/BrowserManager/ShortcutLiveTabCloseService.swift|145|9"

  "Split-shortcut runtime lease|Sumi/Managers/BrowserManager/SplitShortcutRuntimeLease.swift|8|-"
  "Split-shortcut focus|Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift|178|4"
  "Window split materialization|Sumi/Managers/BrowserManager/WindowSplitMaterializationService.swift|110|0"
  "Split-shortcut member resolver|Sumi/Managers/BrowserManager/SplitShortcutMemberResolver.swift|90|0"
  "Split-shortcut member restore|Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreService.swift|192|7"
  "Shortcut launcher placement|Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService.swift|90|4"
  "Shortcut launcher destination resolver|Sumi/Managers/BrowserManager/ShortcutSplitLauncherDestinationResolver.swift|60|2"
  "Shortcut launcher move transaction|Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveTransaction.swift|85|3"
  "Shortcut launcher catalog adapter|Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogAdapter.swift|65|1"
  "Shortcut launcher live composition|Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService+Live.swift|40|-"
  "Hosted split unload|Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift|105|6"
  "Sidebar split commands|Sumi/Managers/BrowserManager/SidebarSplitCommands.swift|30|-"
  "Sidebar split commands live composition|Sumi/Managers/BrowserManager/SidebarSplitCommands+Live.swift|60|-"
  "Split-shortcut live composition|Sumi/Managers/BrowserManager/SplitShortcutServices+Live.swift|138|-"
)

stored_state_budgets=(
  "Normal WebView setup|Sumi/Models/Tab/TabNormalWebViewSetupService.swift|2"
  "Web-content recovery marker ledger|Sumi/Models/Tab/TabWebContentRecoveryMarkerLedger.swift|1"
  "Window Space transition live composition|Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift|0"
  "Session recovery live composition|Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands+Live.swift|0"
  "Window-history live composition|Sumi/Managers/BrowserManager/WindowSessionHistoryServices+Live.swift|0"
  "Floating-bar live composition|Sumi/Managers/BrowserManager/BrowserURLBarBundle+Live.swift|0"
  "Regular shortcut conversion live composition|Sumi/Managers/TabManager/RegularTabShortcutConversionService+Live.swift|0"
  "Shortcut launcher live composition|Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService+Live.swift|0"
)

main_frame_settlement_files=(
  "Sumi/Models/Tab/TabMainFrameActiveNavigationSettlement.swift"
  "Sumi/Models/Tab/TabMainFrameTerminalSettlement.swift"
  "Sumi/Models/Tab/TabMainFrameSameDocumentSettlement.swift"
  "Sumi/Models/Tab/TabMainFramePromotionReplaySettlement.swift"
  "Sumi/Models/Tab/TabMainFrameCompletedAuthorityProof.swift"
)
main_frame_effect_ledger_files=(
  "Sumi/Models/Tab/TabMainFrameAuthorityEffectLedger.swift"
  "Sumi/Models/Tab/TabMainFrameParticipantEffectLedger.swift"
)
main_frame_complete_topology_files=(
  "Sumi/Models/Tab/TabMainFrameAuthorityReducer.swift"
  "Sumi/Models/Tab/TabMainFrameAuthorityState.swift"
  "Sumi/Models/Tab/TabMainFrameParticipantRegistry.swift"
  "Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift"
  "${main_frame_settlement_files[@]}"
  "${main_frame_effect_ledger_files[@]}"
  "Sumi/Models/Tab/TabMainFrameParticipantTransitionApplier.swift"
  "Sumi/Models/Tab/TabMainFrameContinuationTransitionApplier.swift"
  "Sumi/Models/Tab/TabMainFrameAuthorityTransitionApplier.swift"
  "Sumi/Models/Tab/TabMainFrameTransitionCommitter.swift"
  "Sumi/Models/Tab/TabMainFrameTargetTransitionCommitter.swift"
  "Sumi/Models/Tab/TabMainFramePreparedTransition.swift"
  "Sumi/Models/Tab/TabMainFrameRuntimeTypes.swift"
  "Sumi/Models/Tab/TabMainFrameTransitionOutput.swift"
)

guard_sum_lines() {
  local total=0
  local file
  local line_count
  for file in "$@"; do
    line_count="$(guard_count_lines "$file")" || return
    total=$((total + line_count))
  done
  printf '%d\n' "$total"
}

printf '%s\n' 'Living architecture structural metrics'
printf '%s\n' '--------------------------------------'

for budget in "${role_budgets[@]}"; do
  IFS='|' read -r label file maximum_lines maximum_dependencies <<< "$budget"
  guard_max "$label LOC" "$(guard_count_lines "$file")" "$maximum_lines"
  if [[ "$maximum_dependencies" != '-' ]]; then
    dependency_count="$(
      guard_count_matches \
        '^    private (let|weak var) [A-Za-z_][A-Za-z0-9_]*' \
        "$file"
    )"
    guard_max "$label stored dependencies" "$dependency_count" "$maximum_dependencies"
  fi
done

for budget in "${stored_state_budgets[@]}"; do
  IFS='|' read -r label file maximum_state <<< "$budget"
  state_count="$(
    guard_count_matches \
      '^    private (let|var|weak var) [A-Za-z_][A-Za-z0-9_]*' \
      "$file"
  )"
  guard_max "$label stored state" "$state_count" "$maximum_state"
done

settlement_lines="$(guard_sum_lines "${main_frame_settlement_files[@]}")"
lifecycle_lines="$(guard_count_lines Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift)"
effect_ledger_lines="$(guard_sum_lines "${main_frame_effect_ledger_files[@]}")"
complete_topology_lines="$(guard_sum_lines "${main_frame_complete_topology_files[@]}")"

guard_max 'Main-frame settlement aggregate LOC' "$settlement_lines" 725
guard_max \
  'Main-frame lifecycle + settlement aggregate LOC' \
  "$((lifecycle_lines + settlement_lines))" \
  1178
guard_max 'Main-frame split effect-ledger aggregate LOC' "$effect_ledger_lines" 420
guard_max 'Main-frame complete transition topology LOC' "$complete_topology_lines" 4150

guard_max \
  'BrowserManager peer lazy *Owner' \
  "$(guard_count_matches 'lazy var \w+Owner\b' Sumi/Managers/BrowserManager/BrowserManager.swift)" \
  0
guard_max \
  'TabManager peer lazy *Owner' \
  "$(guard_count_matches 'lazy var \w+Owner\b' Sumi/Managers/TabManager/TabManager.swift)" \
  0
guard_max \
  'static func live(browserManager:)' \
  "$(guard_count_swift_matches 'static\s+func\s+live\s*\(\s*browserManager' App FloatingBar SidebarChrome Settings Sumi UI)" \
  40
guard_max \
  'static func live(tabManager:)' \
  "$(guard_count_swift_matches 'static\s+func\s+live\s*\(\s*tabManager' App FloatingBar SidebarChrome Settings Sumi UI)" \
  40

if [[ -d Navigation && ! -L Navigation ]]; then
  guard_record_failure 'repo chrome folder Navigation/ conflicts with the DDG product name'
fi

guard_finish 'living architecture structural metrics'
