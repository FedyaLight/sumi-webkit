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
  "BrowserManager|Sumi/Managers/BrowserManager/BrowserManager.swift|560|-"
  "TabManager|Sumi/Managers/TabManager/TabManager.swift|220|-"
  "Tab store restore orchestration|Sumi/Managers/TabManager/TabStoreRestoreService.swift|140|4"
  "Tab store restore attempt|Sumi/Managers/TabManager/TabStoreRestoreAttemptExecutor.swift|145|5"
  "Tab restore payload apply|Sumi/Managers/TabManager/TabRestorePayloadApplyService.swift|180|5"
  "Tab startup reset orchestration|Sumi/Managers/TabManager/TabStartupStateReset.swift|50|5"
  "Tab startup runtime reset|Sumi/Managers/TabManager/TabStartupRuntimeResetTransaction.swift|55|4"
  "Tab startup split reset|Sumi/Managers/TabManager/TabStartupSplitGroupResetTransaction.swift|50|2"
  "Tab startup collection reset|Sumi/Managers/TabManager/TabStartupRegularCollectionResetTransaction.swift|40|3"
  "Tab startup transient reset|Sumi/Managers/TabManager/TabStartupTransientStateResetTransaction.swift|30|2"
  "Last-session merge orchestration|Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift|75|5"
  "Last-session live-state snapshot|Sumi/Managers/TabManager/TabLastSessionLiveStateSnapshotter.swift|120|4"
  "Last-session merge planning|Sumi/Managers/TabManager/TabLastSessionMergePlanningService.swift|35|2"
  "Last-session profile admission|Sumi/Managers/TabManager/TabLastSessionProfileAdmissionTransaction.swift|40|1"
  "Last-session Space materialization|Sumi/Managers/TabManager/TabLastSessionSpaceMaterializer.swift|65|3"
  "Last-session folder materialization|Sumi/Managers/TabManager/TabLastSessionFolderMaterializer.swift|75|1"
  "Last-session shortcut materialization|Sumi/Managers/TabManager/TabLastSessionShortcutMaterializer.swift|70|2"
  "Last-session regular-tab materialization|Sumi/Managers/TabManager/TabLastSessionRegularTabMaterializer.swift|80|3"
  "Last-session selection materialization|Sumi/Managers/TabManager/TabLastSessionSelectionMaterializer.swift|45|2"
  "Last-session merge commit|Sumi/Managers/TabManager/TabLastSessionMergeCommitTransaction.swift|55|5"
  "Last-session merge settlement|Sumi/Managers/TabManager/TabLastSessionMergeSettlement.swift|30|2"
  "Tab model|Sumi/Models/Tab/Tab.swift|704|-"
  "ExtensionManager transition debt|Sumi/Managers/ExtensionManager/ExtensionManager.swift|1050|-"
  "Tab extension runtime transition debt|Sumi/Models/Tab/TabExtensionPageRuntimeOwner.swift|1000|-"

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
  "Window Space transition|Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService.swift|100|4"
  "Window Space transition live composition|Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift|85|-"
  "Window Space preserved selection|Sumi/Managers/BrowserManager/BrowserWindowSpacePreservedSelectionTransaction.swift|45|3"
  "Window Space change transaction|Sumi/Managers/BrowserManager/BrowserWindowSpaceChangeTransaction.swift|65|4"
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
  "Last-session archive|Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift|160|3"
  "Closed-window history recorder|Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift|45|3"
  "Window-session history capabilities|Sumi/Managers/BrowserManager/WindowSessionHistoryServices.swift|20|-"
  "Window-history live composition|Sumi/Managers/BrowserManager/WindowSessionHistoryServices+Live.swift|65|-"

  "Floating-bar presentation|Sumi/Services/FloatingBarPresentationService.swift|170|5"
  "Floating-bar commit|Sumi/Services/FloatingBarCommitService.swift|235|6"
  "Floating-bar page navigation|Sumi/Services/FloatingBarPageNavigationService.swift|75|2"
  "Floating-bar context factory|Sumi/Managers/BrowserManager/FloatingBarBrowserContextFactory.swift|70|6"
  "Floating-bar live composition|Sumi/Managers/BrowserManager/BrowserManager+FloatingBarComposition.swift|120|-"
  "Active-page resolver|Sumi/Managers/BrowserManager/ActivePageResolver.swift|120|4"
  "Active-page commands|Sumi/Managers/BrowserManager/ActivePageCommandService.swift|130|5"
  "Active-page live composition|Sumi/Managers/BrowserManager/BrowserShellRuntime+ActivePage.swift|40|-"
  "External URL opening|Sumi/Services/ExternalURLTabOpeningService.swift|55|2"
  "Sidebar URL drop|Sumi/Components/DragDrop/SidebarURLDropService.swift|150|4"
  "Shortcut URL insertion|Sumi/Components/DragDrop/ShortcutURLInsertionService.swift|110|5"

  "Space creation transaction|Sumi/Managers/TabManager/SpaceCreationTransaction.swift|95|5"
  "Space creation commit|Sumi/Managers/TabManager/SpaceCreationCommitter.swift|45|3"
  "Space catalog commands|Sumi/Managers/TabManager/SpaceCatalogCommands.swift|115|5"
  "Space catalog publication|Sumi/Managers/TabManager/SpaceCatalogMutationPublication.swift|40|2"
  "Space removal|Sumi/Managers/TabManager/SpaceRemovalService.swift|75|4"
  "Space removal catalog commit|Sumi/Managers/TabManager/SpaceRemovalCatalogCommitter.swift|45|3"
  "Space profile presentation transition factory|Sumi/Managers/TabManager/SpaceProfilePresentationTransitionFactory.swift|90|5"
  "Space activation|Sumi/Managers/TabManager/SpaceActivationService.swift|160|6"
  "Tab creation placement|Sumi/Managers/TabManager/TabCreationPlacementService.swift|135|5"
  "Space profile transition service|Sumi/Managers/TabManager/SpaceProfileTransitionService.swift|200|3"
  "Space profile transition repository|Sumi/Managers/TabManager/SpaceProfileTransitionRepository.swift|300|3"
  "Space profile transition publication|Sumi/Managers/TabManager/SpaceProfileTransitionPublication.swift|50|4"
  "Space profile transition availability|Sumi/Managers/TabManager/SpaceProfileTransitionAvailability.swift|60|0"
  "Space content retirement|Sumi/Managers/TabManager/SpaceContentRetirementService.swift|80|5"
  "Space content retirement transaction|Sumi/Managers/TabManager/SpaceContentRetirementTransaction.swift|65|4"
  "Space split-group retirement|Sumi/Managers/TabManager/SpaceSplitGroupRetirementService.swift|65|2"
  "Space tab inventory|Sumi/Managers/TabManager/SpaceTabInventory.swift|40|0"
  "Deleted-Space window-state reconciler|Sumi/Managers/TabManager/DeletedSpaceWindowStateReconciler.swift|135|1"
  "Deleted-Space window-reference pruner|Sumi/Managers/TabManager/DeletedSpaceWindowReferencePruner.swift|120|0"
  "Tab runtime teardown|Sumi/Managers/TabManager/TabRuntimeTeardownService.swift|65|3"
  "Tab runtime teardown preparation|Sumi/Managers/TabManager/TabRuntimeTeardownPreparationService.swift|30|0"
  "Pending profile inheritance|Sumi/Managers/TabManager/PendingTabProfileInheritance.swift|180|0"
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
  "Shortcut selection reconciler|Sumi/Managers/TabManager/ShortcutSelectionReconciler.swift|90|0"
  "Shortcut selection transition|Sumi/Managers/TabManager/ShortcutSelectionTransition.swift|185|0"
  "Live shortcut close|Sumi/Managers/BrowserManager/ShortcutLiveTabCloseService.swift|145|9"

  "Split-shortcut focus|Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift|178|4"
  "Window split materialization|Sumi/Managers/BrowserManager/WindowSplitMaterializationService.swift|80|3"
  "Window split materialization query|Sumi/Managers/BrowserManager/WindowSplitMaterializationQuery.swift|65|4"
  "Split-shortcut member resolver|Sumi/Managers/BrowserManager/SplitShortcutMemberResolver.swift|90|0"
  "Shortcut launcher placement|Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService.swift|90|4"
  "Shortcut launcher destination resolver|Sumi/Managers/BrowserManager/ShortcutSplitLauncherDestinationResolver.swift|60|2"
  "Shortcut launcher move transaction|Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveTransaction.swift|85|3"
  "Hosted split unload|Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift|105|6"
  "Sidebar split focus commands|Sumi/Managers/BrowserManager/SidebarSplitFocusCommands.swift|55|4"
  "Sidebar split close command|Sumi/Managers/BrowserManager/SidebarSplitCloseCommand.swift|55|5"
  "Window split presentation synchronizer|Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift|340|5"
  "Window split presentation effects|Sumi/Managers/SplitRuntime/WindowSplitPresentationEffectExecutor.swift|160|4"
)

stored_state_budgets=(
  "Normal WebView setup|Sumi/Models/Tab/TabNormalWebViewSetupService.swift|2"
  "Web-content recovery marker ledger|Sumi/Models/Tab/TabWebContentRecoveryMarkerLedger.swift|1"
  "Window Space transition live composition|Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift|0"
  "Session recovery live composition|Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands+Live.swift|0"
  "Window-history live composition|Sumi/Managers/BrowserManager/WindowSessionHistoryServices+Live.swift|0"
  "Floating-bar live composition|Sumi/Managers/BrowserManager/BrowserManager+FloatingBarComposition.swift|0"
  "Regular shortcut conversion live composition|Sumi/Managers/TabManager/RegularTabShortcutConversionService+Live.swift|0"
)

production_source_exclusions=(
  -g '!build/**'
  -g '!Vendor/**'
  -g '!SumiTests/**'
  -g '!SumiUITests/**'
  -g '!**/Tests/**'
)

shopt -s nullglob
main_frame_settlement_files=(
  Sumi/Models/Tab/TabMainFrame*Settlement.swift
  Sumi/Models/Tab/TabMainFrameCompletedAuthorityProof.swift
)
main_frame_effect_ledger_files=(
  Sumi/Models/Tab/TabMainFrame*EffectLedger.swift
)
main_frame_topology_candidates=(
  Sumi/Models/Tab/TabMainFrame*.swift
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

guard_sum_transition_topology() {
  local total=0
  local file
  local line_count
  for file in "$@"; do
    case "${file##*/}" in
      *IntentLedger.swift|*LoadRuntime.swift|*RuntimeCapabilities.swift|*RuntimeTransaction.swift)
        continue
        ;;
    esac
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
    guard_max \
      "$label stored dependencies" \
      "$dependency_count" \
      "$maximum_dependencies"
  fi
done

space_profile_transition_topology_lines="$(
  guard_sum_lines \
    Sumi/Managers/TabManager/SpaceProfileTransitionService.swift \
    Sumi/Managers/TabManager/SpaceProfileTransitionAdmission.swift \
    Sumi/Managers/TabManager/SpaceProfileTransitionRepository.swift \
    Sumi/Managers/TabManager/SpaceProfileTransitionPublication.swift \
    Sumi/Managers/TabManager/SpaceProfileTransitionAvailability.swift
)"
guard_max \
  'Space profile transition complete topology LOC' \
  "$space_profile_transition_topology_lines" \
  600

startup_restore_topology_lines="$(
  guard_sum_lines \
    Sumi/Managers/TabManager/TabStartupRestoreAttempt.swift \
    Sumi/Managers/TabManager/TabStartupRestoreLifecycle.swift \
    Sumi/Managers/TabManager/TabRuntimeAttachmentRestoreStarter.swift \
    Sumi/Managers/TabManager/TabStoreRestoreService.swift \
    Sumi/Managers/TabManager/TabRestorePayloadApplyService.swift
)"
guard_max \
  'Startup restore complete topology LOC' \
  "$startup_restore_topology_lines" \
  600

for budget in "${stored_state_budgets[@]}"; do
  IFS='|' read -r label file maximum_state <<< "$budget"
  state_count="$(
    guard_count_matches \
      '^    private (let|var|weak var) [A-Za-z_][A-Za-z0-9_]*' \
      "$file"
  )"
  guard_max "$label stored state" "$state_count" "$maximum_state"
done

production_file_count=0
maximum_file_lines=0
files_over_600_lines=0
files_over_800_lines=0
files_over_8_dependencies=0
files_over_12_dependencies=0
production_file_list="$(mktemp "${TMPDIR:-/tmp}/sumi-production-swift-files.XXXXXX")"
trap 'rm -f "$production_file_list"' EXIT
if ! find . \( \
      -path './.git' -o \
      -path './build' -o \
      -path './Vendor' -o \
      -path './SumiTests' -o \
      -path './SumiUITests' -o \
      -path '*/Tests' -o \
      -path '*/.build' -o \
      -path '*/.swiftpm' \
    \) -prune -o -type f -name '*.swift' -print0 \
    > "$production_file_list"; then
  guard_fatal 'failed to enumerate production Swift sources'
fi
while IFS= read -r -d '' file; do
  production_file_count=$((production_file_count + 1))
  line_count="$(guard_count_lines "$file")"
  dependency_count="$(
    guard_count_matches \
      '^    private (let|weak var) [A-Za-z_][A-Za-z0-9_]*' \
      "$file"
  )"
  (( line_count > maximum_file_lines )) && maximum_file_lines="$line_count"
  (( line_count > 600 )) && files_over_600_lines=$((files_over_600_lines + 1))
  (( line_count > 800 )) && files_over_800_lines=$((files_over_800_lines + 1))
  (( dependency_count > 8 )) && files_over_8_dependencies=$((files_over_8_dependencies + 1))
  (( dependency_count > 12 )) && files_over_12_dependencies=$((files_over_12_dependencies + 1))
done < "$production_file_list"

if (( production_file_count == 0 )); then
  guard_fatal 'tracked production Swift source inventory is empty'
fi

guard_warn_max 'Maximum production Swift file LOC' "$maximum_file_lines" 1100
guard_max 'Maximum production Swift file LOC hard limit' "$maximum_file_lines" 1200
guard_warn_max 'Production Swift files over 600 LOC' "$files_over_600_lines" 43
guard_warn_max 'Production Swift files over 800 LOC' "$files_over_800_lines" 6
guard_warn_max \
  'Production Swift files over 8 stored dependencies' \
  "$files_over_8_dependencies" \
  76
guard_warn_max \
  'Production Swift files over 12 stored dependencies' \
  "$files_over_12_dependencies" \
  25
guard_exact \
  'State stored in +Live composition files' \
  "$(
    guard_count_matches \
      '^    (private )?(let|var|lazy var) ' \
      -g '*+Live.swift' \
      "${production_source_exclusions[@]}" \
      .
  )" \
  0

settlement_lines="$(guard_sum_lines "${main_frame_settlement_files[@]}")"
lifecycle_lines="$(guard_count_lines Sumi/Models/Tab/TabMainFrameLifecycleMachine.swift)"
effect_ledger_lines="$(guard_sum_lines "${main_frame_effect_ledger_files[@]}")"
complete_topology_lines="$(
  guard_sum_transition_topology "${main_frame_topology_candidates[@]}"
)"

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
  2
guard_max \
  'TabManager peer lazy *Owner' \
  "$(guard_count_matches 'lazy var \w+Owner\b' Sumi/Managers/TabManager/TabManager.swift)" \
  0
guard_max \
  'static func live(browserManager:)' \
  "$(
    guard_count_matches \
      'static\s+func\s+live\s*\(\s*browserManager' \
      -g '*.swift' \
      "${production_source_exclusions[@]}" \
      .
  )" \
  40
guard_max \
  'static func live(tabManager:)' \
  "$(
    guard_count_matches \
      'static\s+func\s+live\s*\(\s*tabManager' \
      -g '*.swift' \
      "${production_source_exclusions[@]}" \
      .
  )" \
  40

if [[ -d Navigation && ! -L Navigation ]]; then
  guard_record_failure 'repo chrome folder Navigation/ conflicts with the DDG product name'
fi

guard_finish 'living architecture structural metrics'
