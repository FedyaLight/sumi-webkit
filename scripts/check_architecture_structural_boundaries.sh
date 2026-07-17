#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

guard_expect_no_matches \
  'production services reached exact split roles through WindowSplitContext' \
  '\bsplitWindowContext\.(query|layout|drops|dropTargets|previews|updates)\b' \
  App Sumi Settings SidebarChrome FloatingBar UI -g '*.swift'
guard_expect_no_matches \
  'exact window-session services reached through BrowserWindowSessionBundle' \
  '\bwindowSessionBundle\.(persistence|activation)\b' \
  App Sumi Settings SidebarChrome FloatingBar UI SumiTests -g '*.swift'

shopt -s nullglob
session_recovery_services=(
  Sumi/Managers/BrowserManager/*Restore*.swift
  Sumi/Managers/BrowserManager/*Reopen*.swift
  Sumi/Managers/BrowserManager/*RecentlyClosed*.swift
  Sumi/Managers/BrowserManager/*SessionRecovery*.swift
)
filtered_session_recovery_services=()
for source in "${session_recovery_services[@]}"; do
  [[ "$source" == *+Live.swift ]] || filtered_session_recovery_services+=("$source")
done
session_recovery_services=("${filtered_session_recovery_services[@]}")
tab_space_services=(
  Sumi/Managers/TabManager/SpaceCatalog*.swift
  Sumi/Managers/TabManager/SpaceRemoval*.swift
  Sumi/Managers/TabManager/SpaceActivation*.swift
  Sumi/Managers/TabManager/SpaceContentRetirement*.swift
  Sumi/Managers/TabManager/SpaceSplitGroupRetirement*.swift
  Sumi/Managers/TabManager/SpaceTabInventory.swift
  Sumi/Managers/TabManager/DeletedSpace*.swift
  Sumi/Managers/TabManager/TabCreationPlacement*.swift
  Sumi/Managers/TabManager/TabRuntimeTeardown*.swift
  Packages/SumiDomain/Sources/SumiDomain/Window/WindowSelectionHistory.swift
)
shortcut_runtime_services=(
  Sumi/Managers/TabManager/*Shortcut*.swift
)
filtered_shortcut_runtime_services=()
for source in "${shortcut_runtime_services[@]}"; do
  [[ "$source" == *Owner.swift ]] || filtered_shortcut_runtime_services+=("$source")
done
shortcut_runtime_services=("${filtered_shortcut_runtime_services[@]}")
split_shortcut_services=(
  Sumi/Managers/BrowserManager/*SplitShortcut*.swift
  Sumi/Managers/BrowserManager/*ShortcutSplit*.swift
  Sumi/Managers/BrowserManager/WindowSplitMaterialization*.swift
  Sumi/Managers/BrowserManager/ShortcutHostedSplit*.swift
)
sidebar_command_services=(
  Sumi/Managers/BrowserManager/SidebarSplitFocusCommands.swift
  Sumi/Managers/BrowserManager/SidebarSplitCloseCommand.swift
  Sumi/Managers/BrowserManager/BrowserSidebarSpaceTransitionRoutingOwner.swift
)
filtered_split_shortcut_services=()
for source in "${split_shortcut_services[@]}"; do
  [[ "$source" == *+Live.swift ]] || filtered_split_shortcut_services+=("$source")
done
split_shortcut_services=("${filtered_split_shortcut_services[@]}")
window_history_services=(
  Sumi/Managers/BrowserManager/OpenWindowSessionCatalog.swift
  Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift
  Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift
  Sumi/Managers/BrowserManager/WindowSessionHistoryServices.swift
)
floating_bar_services=(Sumi/Services/FloatingBar*.swift)
active_page_services=(
  Sumi/Managers/BrowserManager/*ActivePage*.swift
  Sumi/Services/ExternalURL*.swift
  Sumi/Components/DragDrop/SidebarURL*.swift
  Sumi/Components/DragDrop/ShortcutURL*.swift
)
tab_selection_services=(
  Sumi/Managers/TabManager/TabActiveSelectionOwner.swift
  Sumi/Managers/TabManager/TabActiveSpaceSelectionUpdater.swift
  Sumi/Managers/TabManager/TabSelectionContextProjection.swift
)
tab_selection_role_files=(
  Sumi/Managers/BrowserManager/BrowserTabSelectionActivation.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionStateApplication.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionMaterializationOwner.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionChromeEffects.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionMediaEffects.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionPresentationEffects.swift
  Sumi/Managers/BrowserManager/BrowserTabSelectionPublicationTransaction.swift
)
sidebar_editor_presentation_services=(
  Sumi/Managers/BrowserManager/SidebarSpaceEditorPresentationService.swift
  Sumi/Managers/BrowserManager/SidebarFolderEditorPresentationService.swift
  Sumi/Managers/BrowserManager/SidebarFolderSearchPresentationService.swift
  Sumi/Managers/BrowserManager/SidebarShortcutEditorPresentationService.swift
)
profile_selection_services=(
  Sumi/Managers/TabManager/ProfileSelectionCoordinator.swift
  Sumi/Managers/TabManager/SpaceProfileReconciliationService.swift
  Sumi/Managers/TabManager/SpaceProfileTransitionService.swift
  Sumi/Managers/TabManager/SpaceProfileTransitionAdmission.swift
  Sumi/Managers/TabManager/SpaceProfileTransitionRepository.swift
  Sumi/Managers/TabManager/SpaceProfileTransitionPublication.swift
  Sumi/Managers/TabManager/SpaceProfileTransitionAvailability.swift
)
profile_selection_core=(
  "${profile_selection_services[@]}"
)
profile_assignment_policy_core=(
  Sumi/Managers/TabManager/ProfileAssignmentPolicy.swift
)
profile_assignment_manager_free_core=(
  Sumi/Managers/TabManager/ProfileAssignmentPolicy.swift
  Sumi/Managers/TabManager/TabProfileTransitionService.swift
  Sumi/Managers/TabManager/TabProfileTransitionPublication.swift
  Sumi/Managers/TabManager/ProfileDeletionMigration.swift
  Sumi/Managers/TabManager/ProfileDeletionSettlementCoordinator.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationPlan.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationPlanner.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceStructureMutation.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceTopologyMutation.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationApplicator.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceRetirementService.swift
  Sumi/Managers/TabManager/SpaceProfileMutationService.swift
)
runtime_attachment_services=(
  Sumi/Managers/TabManager/TabRuntimePortsAttachmentOwner.swift
  Sumi/Managers/TabManager/TabRuntimeAttachmentBootstrap.swift
  Sumi/Managers/TabManager/PendingShortcutPinAdopter.swift
  Sumi/Managers/TabManager/TabRuntimeAttachmentSettlement.swift
  Sumi/Managers/TabManager/TabRuntimeAttachmentDeferredWorkOwner.swift
  Sumi/Managers/TabManager/TabRuntimeAttachmentRestoreStarter.swift
  Sumi/Managers/TabManager/TabRuntimePreparationOwner.swift
)
search_manager="Sumi/Managers/SearchManager/SearchManager.swift"

guard_require_discovered_sources() {
  local label="$1"
  shift
  if (( $# == 0 )); then
    guard_fatal "no living sources discovered for $label"
  fi
}

guard_require_discovered_sources 'session recovery' "${session_recovery_services[@]}"
guard_require_discovered_sources 'Tab Space' "${tab_space_services[@]}"
guard_require_discovered_sources 'shortcut runtime' "${shortcut_runtime_services[@]}"
guard_require_discovered_sources 'split shortcut' "${split_shortcut_services[@]}"
guard_require_discovered_sources 'sidebar command' "${sidebar_command_services[@]}"
guard_require_discovered_sources 'window history' "${window_history_services[@]}"
guard_require_discovered_sources 'floating bar' "${floating_bar_services[@]}"
guard_require_discovered_sources 'active page' "${active_page_services[@]}"
guard_require_discovered_sources 'Tab selection' "${tab_selection_services[@]}"
guard_require_discovered_sources 'Tab selection roles' "${tab_selection_role_files[@]}"
guard_require_discovered_sources \
  'sidebar editor presentation' \
  "${sidebar_editor_presentation_services[@]}"
guard_require_discovered_sources 'profile selection' "${profile_selection_core[@]}"
guard_require_discovered_sources 'profile assignment policy' "${profile_assignment_policy_core[@]}"
guard_require_discovered_sources 'manager-free profile assignment' "${profile_assignment_manager_free_core[@]}"
guard_require_discovered_sources 'runtime attachment' "${runtime_attachment_services[@]}"
guard_require_file "$search_manager"

# Main-frame mutation must stay behind the exact owners/composition root. This
# protects authority placement without freezing method counts or test names.
guard_expect_no_matches \
  'prevalidated main-frame apply outside exact owners' \
  'applyPrevalidated' \
  -g '*.swift' \
  -g '!TabMainFrameTransitionCommitter.swift' \
  -g '!TabMainFrameTargetTransitionCommitter.swift' \
  -g '!TabMainFrameAuthorityState.swift' \
  -g '!TabMainFrameParticipantRegistry.swift' \
  -g '!TabMainFrameAuthorityEffectLedger.swift' \
  -g '!TabMainFrameParticipantEffectLedger.swift' \
  Sumi/Models/Tab
guard_expect_no_matches \
  'main-frame composition outside lifecycle machine' \
  'TabMainFrameContinuationTransitionApplier\(|TabMainFrameTransitionCommitter\.lifecycleComposition\(' \
  -g '*.swift' -g '!TabMainFrameLifecycleMachine.swift' Sumi/Models/Tab
guard_expect_no_matches \
  'main-frame mutable-owner construction outside lifecycle machine' \
  'TabMainFrame(ParticipantRegistry|AuthorityState)\(\)' \
  -g '*.swift' -g '!TabMainFrameLifecycleMachine.swift' Sumi/Models/Tab
guard_expect_no_matches \
  'prepared main-frame transition outside committer' \
  'TabMainFramePreparedTransition\.(document|terminal|sameDocument|continuation)\(' \
  -g '*.swift' -g '!TabMainFrameTransitionCommitter.swift' Sumi/Models/Tab
guard_expect_no_matches \
  'authority mutation plan supplied directly to main-frame committer' \
  'TabMainFrameAuthorityPlan' \
  Sumi/Models/Tab/TabMainFrameTransitionCommitter.swift
guard_expect_no_matches \
  'callback fields in main-frame mutation plans' \
  '^\s+(fileprivate )?let [A-Za-z_][A-Za-z0-9_]*:.*->' \
  Sumi/Models/Tab/TabMainFrameAuthorityState.swift \
  Sumi/Models/Tab/TabMainFrameParticipantRegistry.swift \
  Sumi/Models/Tab/TabMainFrameAuthorityEffectLedger.swift \
  Sumi/Models/Tab/TabMainFrameParticipantEffectLedger.swift \
  Sumi/Models/Tab/TabMainFramePreparedTransition.swift
guard_expect_no_matches \
  'Tab profile mutation outside transaction services' \
  '\.profileAssignment\.(begin|cancelPending|commit|stage|finish|rollback|abort|replaceCurrentProfileID)\b' \
  -g '*.swift' \
  -g '!ProfileTransitionService.swift' \
  -g '!SpaceProfileTransitionAdmission.swift' \
  -g '!SpaceProfileTransaction.swift' \
  -g '!SpaceProfileTransitionService.swift' \
  -g '!TabProfileTransitionService.swift' \
  -g '!Sumi/Managers/WebViewRuntime/ProfileTransitionModelParticipant.swift' \
  Sumi

guard_expect_no_matches \
  'BrowserManager façade Owner accessors' \
  'var \w+Owner\b' \
  -g 'BrowserManager+*.swift' Sumi/Managers/BrowserManager
guard_expect_no_matches \
  'SearchManager TabManager reachback' \
  '\b(TabManager|tabManager)\b' \
  "$search_manager"
guard_expect_no_matches \
  'session-recovery BrowserManager reachback' \
  '\bbrowserManager\b|\bBrowserManager\b|BrowserHistoryMenuOwner|historyMenuOwner' \
  "${session_recovery_services[@]}"
guard_expect_no_matches \
  'mutable session-restore identity projection' \
  'map\(\\\.session\)|contains\(\$0\.session\)|uniqued\(by:[[:space:]]*\\\.session\)' \
  Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift \
  Sumi/Managers/BrowserManager/StartupWindowRestoreService.swift \
  Sumi/Services/SumiStartupSessionCoordinator.swift \
  Sumi/Managers/History/LastSessionWindowsStore.swift
guard_expect_no_matches \
  'profile runtime in structural persistence' \
  'SpaceProfileRuntimeStateService|profileRuntimeState|reconcileProfileRuntimeStates' \
  Sumi/Managers/TabManager/TabStructuralPersistenceService.swift
guard_expect_no_matches \
  'profile runtime in window-context reconciliation' \
  'SpaceProfileRuntimeStateService|profileRuntimeState|reconcileProfileRuntimeStates' \
  Sumi/Managers/BrowserManager/BrowserWindowSpaceContextReconciler.swift
guard_expect_no_matches \
  'Space services TabManager reachback' \
  '\bTabManager\b|\btabManager\b' \
  "${tab_space_services[@]}"
guard_expect_no_matches \
  'mutable BrowserManager TabManager' \
  '^    var tabManager: TabManager' \
  Sumi/Managers/BrowserManager/BrowserManager.swift
guard_expect_no_matches \
  'BrowserManager raw tab-residence session identity mirror' \
  '\btabResidenceSessionIdentity\b' \
  Sumi/Managers/BrowserManager/BrowserManager.swift \
  Sumi/BrowserRuntime/BrowserKernelGraph.swift
guard_expect_no_matches \
  'Tab selection generic dependency bags' \
  '\bstruct[[:space:]]+(Dependencies|Actions|Context|Environment|Capabilities)\b' \
  "${tab_selection_services[@]}" \
  "${tab_selection_role_files[@]}"
guard_expect_no_matches \
  'Tab selection manager reachback' \
  '\bTabManager\b|\btabManager\b' \
  "${tab_selection_services[@]}" \
  "${tab_selection_role_files[@]}"
guard_expect_no_matches \
  'Tab selection stored callback dependencies' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${tab_selection_services[@]}" \
  "${tab_selection_role_files[@]}"
guard_expect_no_matches \
  'Browser selection transaction stored callback dependencies' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  Sumi/Managers/BrowserManager/BrowserTabSelectionOwner.swift \
  "${tab_selection_role_files[@]}"
guard_expect_absent_path \
  'retired Tab-selection aggregate' \
  Sumi/Managers/BrowserManager/BrowserTabSelectionRoles.swift
guard_expect_absent_path \
  'retired sidebar-editor presentation aggregate' \
  Sumi/Managers/BrowserManager/SidebarEditorPresentationServices.swift
for role_file in \
  "${tab_selection_role_files[@]}" \
  "${sidebar_editor_presentation_services[@]}"; do
  role="$(basename "$role_file" .swift)"
  guard_require_file "$role_file"
  guard_exact \
    "$role stays in its role-exact file" \
    "$(guard_count_matches "^final[[:space:]]+class[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_exact \
    "$role file owns one top-level role" \
    "$(guard_count_matches '^final[[:space:]]+class[[:space:]]+' "$role_file")" \
    1
  guard_expect_no_matches \
    "$role has no callback dependency bag" \
    '\bstruct[[:space:]]+(Dependencies|Actions|Context|Environment|Capabilities)\b|^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
    "$role_file"
  guard_expect_no_matches \
    "$role has no manager recovery" \
    '\bBrowserManager\b|\bbrowserManager\b|\bTabManager\b|\btabManager\b' \
    "$role_file"
  guard_max \
    "$role stored collaborators" \
    "$(guard_count_matches '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' "$role_file")" \
    5
done
for selection_service in \
  "${tab_selection_services[@]}" \
  "${tab_selection_role_files[@]}"; do
  selection_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$selection_service"
  )"
  guard_max \
    "$(basename "$selection_service" .swift) stored collaborators" \
    "$selection_collaborators" \
    5
done
guard_expect_no_matches \
  'profile selection generic dependency bags' \
  '\bstruct[[:space:]]+(Dependencies|Actions|Context|Environment|Capabilities)\b' \
  "${profile_selection_core[@]}"
guard_expect_no_matches \
  'profile selection manager reachback' \
  '\bTabManager\b|\btabManager\b' \
  "${profile_selection_core[@]}"
guard_expect_no_matches \
  'profile selection stored callback dependencies' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${profile_selection_core[@]}"
guard_expect_no_matches \
  'mutable runtime resolution inside Space-profile transaction pipeline' \
  '\bruntime(Connection|PortConnection)\.current\b' \
  Sumi/Managers/TabManager/SpaceProfileReconciliationService.swift \
  Sumi/Managers/TabManager/SpaceProfileTransitionService.swift \
  Sumi/Managers/TabManager/SpaceProfileTransitionAdmission.swift \
  Sumi/Managers/TabManager/SpaceProfileMutationService.swift
space_reconciliation_exact_lease_calls="$(
  guard_count_matches \
    'spaceTransitions\.start\([[:space:][:print:]]*using:[[:space:]]*lease' \
    --multiline \
    Sumi/Managers/TabManager/SpaceProfileReconciliationService.swift
)"
guard_exact \
  'Space reconciliation exact-lease transition entry' \
  "$space_reconciliation_exact_lease_calls" \
  1
for profile_selection_service in "${profile_selection_services[@]}"; do
  profile_selection_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$profile_selection_service"
  )"
  guard_max \
    "$(basename "$profile_selection_service" .swift) stored collaborators" \
    "$profile_selection_collaborators" \
    5
done
guard_expect_no_matches \
  'profile assignment policy manager reachback' \
  '\bTabManager\b|\btabManager\b' \
  "${profile_assignment_policy_core[@]}"
guard_expect_no_matches \
  'profile assignment policy generic dependency bags' \
  '\bstruct[[:space:]]+(Dependencies|Actions|Context|Environment|Capabilities)\b' \
  "${profile_assignment_policy_core[@]}"
guard_expect_no_matches \
  'profile assignment policy stored callback dependencies' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${profile_assignment_policy_core[@]}"
profile_assignment_policy_collaborators="$(
  guard_count_matches \
    '^[[:space:]]*private[[:space:]]+let\b' \
    "${profile_assignment_policy_core[@]}"
)"
guard_exact \
  'ProfileAssignmentPolicy stored collaborators' \
  "$profile_assignment_policy_collaborators" \
  4
guard_expect_no_matches \
  'profile assignment manager recovery' \
  '\btabManager\b|:[[:space:]]*TabManager\b' \
  "${profile_assignment_manager_free_core[@]}"
guard_expect_no_matches \
  'profile assignment generic dependency bags' \
  '\bstruct[[:space:]]+(Dependencies|Actions|Context|Environment|Capabilities)\b' \
  "${profile_assignment_manager_free_core[@]}"
guard_expect_no_matches \
  'direct profile-pin removal outside structural mutation authority' \
  '\bremovePinnedPins\(' \
  -g '*.swift' Sumi
guard_expect_no_matches \
  'dead pending Space activation state' \
  '\bpendingSpaceActivation\b' \
  Sumi
guard_expect_no_matches \
  'runtime attachment generic dependency bags' \
  '\bstruct[[:space:]]+(Dependencies|Actions|Context|Environment|Capabilities)\b' \
  "${runtime_attachment_services[@]}"
guard_expect_no_matches \
  'runtime attachment manager reachback' \
  '\bTabManager\b|\btabManager\b' \
  "${runtime_attachment_services[@]}"
guard_expect_no_matches \
  'runtime attachment stored callback dependencies' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${runtime_attachment_services[@]}"
for runtime_attachment_service in "${runtime_attachment_services[@]}"; do
  runtime_attachment_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$runtime_attachment_service"
  )"
  guard_max \
    "$(basename "$runtime_attachment_service" .swift) stored collaborators" \
    "$runtime_attachment_collaborators" \
    5
done
runtime_attachment_owner_collaborators="$(
  guard_count_matches \
    '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
    Sumi/Managers/TabManager/TabRuntimePortsAttachmentOwner.swift
)"
guard_max \
  'TabRuntimePortsAttachmentOwner hard collaborator cap' \
  "$runtime_attachment_owner_collaborators" \
  3
pending_pin_adopter_collaborators="$(
  guard_count_matches \
    '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
    Sumi/Managers/TabManager/PendingShortcutPinAdopter.swift
)"
guard_max \
  'PendingShortcutPinAdopter hard collaborator cap' \
  "$pending_pin_adopter_collaborators" \
  3
runtime_attachment_settlement_collaborators="$(
  guard_count_matches \
    '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
    Sumi/Managers/TabManager/TabRuntimeAttachmentSettlement.swift
)"
guard_max \
  'TabRuntimeAttachmentSettlement hard collaborator cap' \
  "$runtime_attachment_settlement_collaborators" \
  4
guard_expect_no_matches \
  'runtime-port property mutation outside attachment authority' \
  '\bruntimePortConnection\.(attach|detach)\(' \
  -g '*.swift' \
  Sumi
guard_expect_no_matches \
  'runtime connection mutation outside attachment authority' \
  '\bconnection\.(attach|detach)\(' \
  -g '*.swift' \
  -g '!TabRuntimePortsAttachmentOwner.swift' \
  Sumi/Managers/TabManager
guard_expect_no_matches \
  'TabManager runtime-port installation bypass' \
  '\binstallRuntimePorts\b' \
  Sumi
guard_expect_no_matches \
  'direct pending-pin drain outside atomic adopter' \
  '\bdrainPendingPinnedWithoutProfile\(' \
  -g '*.swift' \
  -g '!PendingShortcutPinAdopter.swift' \
  -g '!ShortcutPinCollectionStateOwner.swift' \
  Sumi
guard_expect_no_matches \
  'direct runtime-attachment object publication' \
  'objectWillChange\.send\(' \
  "${runtime_attachment_services[@]}"
automatic_restore_policy_count="$(
  guard_count_matches \
    'guard policy\.automaticallyStarts else' \
    Sumi/Managers/TabManager/TabRuntimeAttachmentRestoreStarter.swift
)"
guard_exact \
  'automatic attachment restore policy authority' \
  "$automatic_restore_policy_count" \
  1
enabled_restore_graph_gate_count="$(
  guard_count_matches \
    'startupRestorePolicy\.isEnabled' \
    Sumi/BrowserRuntime/BrowserTabRuntimeLifecycleFactory.swift
)"
guard_exact \
  'attachment restore graph enabled-load gate' \
  "$enabled_restore_graph_gate_count" \
  1
guard_expect_no_matches \
  'executable runtime ownership returned to TabManager' \
  '\b(runtimePortsAttachmentOwner|faviconPresentationRefreshOwner)\b' \
  Sumi/Managers/TabManager/TabManager.swift
tab_runtime_lifecycle_owner_count="$(
  guard_count_matches \
    'private let (runtimePorts|faviconRefresh):' \
    Sumi/BrowserRuntime/TabRuntimeLifecycle.swift
)"
guard_exact \
  'TabRuntimeLifecycle exact executable owners' \
  "$tab_runtime_lifecycle_owner_count" \
  2
guard_expect_no_matches \
  'startup restore bypass outside attachment owner' \
  'startupRestoreLifecycle\.startIfNeeded\(' \
  -g '*.swift' \
  -g '!TabRuntimeAttachmentRestoreStarter.swift' \
  Sumi
guard_expect_no_matches \
  'tab resource runtime regained a manager locator or dependency bag' \
  '\b(BrowserManager|TabManager)\b|struct[[:space:]]+Dependencies\b|\.live\(browserManager:' \
  Sumi/Managers/BrowserManager/BrowserTabRuntimeCompositionService.swift
guard_expect_no_matches \
  'tab resource root wiring recovered roles through TabManager' \
  '\bbrowserManager\.tabManager\b|\blet[[:space:]]+tabManager\b' \
  Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift
guard_expect_no_matches \
  'tab feature factories recovered roles through TabManager' \
  '\bTabManager\b|\btabManager\b' \
  Sumi/BrowserRuntime/BrowserTabRuntimeLifecycleFactory.swift \
  Sumi/BrowserRuntime/BrowserTabStoreRestoreFactory.swift
guard_expect_no_matches \
  'BrowserManager TabManager reassignment' \
  '\bbrowserManager\.tabManager\s*=' \
  -g '*.swift' SumiTests
guard_expect_no_matches \
  'unsafe shortcut conversion phase API' \
  '^    func (authorize|canConvert)\(' \
  Sumi/Managers/TabManager/RegularTabShortcutConversionService.swift
for eager_shortcut_role in \
  liveShortcutTabs shortcutTabWindowQuery shortcutTabBindings \
  shortcutTabMaterializer regularTabShortcutConversion \
  shortcutPinToRegularTab shortcutTabPromotion shortcutLiveTabRetirement; do
  eager_shortcut_role_count="$(
    guard_count_matches \
      "let ${eager_shortcut_role} =" \
      Sumi/BrowserRuntime/BrowserCompositionRoot+TabSession.swift
  )"
  guard_exact \
    "eager shortcut composition: ${eager_shortcut_role}" \
    "$eager_shortcut_role_count" \
    1
done
guard_expect_no_matches \
  'TabFolder placement writes outside structural authorities' \
  '\binstallPlacement\s*\(' \
  -g '*.swift' \
  -g '!TabFolder.swift' \
  -g '!SpacePinnedStructureOwner.swift' \
  -g '!TabFolderMutationOwner.swift' \
  -g '!SplitGroupSidebarOrderingService.swift' \
  -g '!TabStructuralMutationTransaction.swift' \
  -g '!TabStoreRecordMutation.swift' \
  -g '!TabLastSessionFolderMaterializer.swift' \
  App FloatingBar SidebarChrome Settings Sumi UI
structural_install_services=(
  Sumi/Managers/TabManager/TabStructuralInstallOwner.swift
  Sumi/Managers/TabManager/TabStructuralInstallPublication.swift
)
guard_expect_no_matches \
  'structural install callback dependencies or manager recovery' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->|\b(TabManager|BrowserManager)\b' \
  "${structural_install_services[@]}"
for structural_install_service in "${structural_install_services[@]}"; do
  structural_install_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$structural_install_service"
  )"
  guard_max \
    "$(basename "$structural_install_service" .swift) stored collaborators" \
    "$structural_install_collaborators" \
    5
done
guard_expect_no_matches \
  'shortcut closure dependency bags' \
  'struct Dependencies\b' \
  "${shortcut_runtime_services[@]}"
shortcut_regular_conversion_services=(
  Sumi/Managers/TabManager/ShortcutPinRegularConversionTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinToRegularTabService.swift
)
sidebar_regular_drag_roles=(
  Sumi/Managers/TabManager/SidebarRegularTabShortcutTransaction.swift
  Sumi/Managers/TabManager/SidebarRegularTabPlacementTransaction.swift
  Sumi/Managers/TabManager/SidebarDraggedTabSplitRetirementTransaction.swift
  Sumi/Managers/TabManager/SidebarRegularTabDragService.swift
)
for role_file in "${sidebar_regular_drag_roles[@]}"; do
  guard_require_file "$role_file"
  role="$(basename "$role_file" .swift)"
  guard_exact \
    "$role stays in its role-exact file" \
    "$(guard_count_matches "^final[[:space:]]+class[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_exact \
    "$role file owns one top-level role" \
    "$(guard_count_matches '^(final[[:space:]]+class|struct|enum)[[:space:]]+' "$role_file")" \
    1
done
folder_transaction_roles=(
  Sumi/Managers/TabManager/TabFolderContainerItem.swift
  Sumi/Managers/TabManager/TabFolderHierarchyMutationService.swift
  Sumi/Managers/TabManager/TabFolderContentMutationTransaction.swift
  Sumi/Managers/TabManager/TabFolderPlacementIntent.swift
  Sumi/Managers/TabManager/TabFolderPlacementAdmission.swift
  Sumi/Managers/TabManager/TabFolderPlacementCommitTransaction.swift
  Sumi/Managers/TabManager/TabFolderPlacementTransaction.swift
  Sumi/Managers/TabManager/TabFolderDeletionPreparation.swift
  Sumi/Managers/TabManager/TabFolderDeletionPreparationService.swift
  Sumi/Managers/TabManager/TabFolderDeletionCommitTransaction.swift
  Sumi/Managers/TabManager/TabFolderUngroupPreparation.swift
  Sumi/Managers/TabManager/TabFolderUngroupPreparationService.swift
  Sumi/Managers/TabManager/TabFolderUngroupCommitTransaction.swift
  Sumi/Managers/TabManager/TabFolderRetirementTransaction.swift
  Sumi/Managers/TabManager/TabFolderTabPlacementTransaction.swift
)
for role_file in "${folder_transaction_roles[@]}"; do
  guard_require_file "$role_file"
  role="$(basename "$role_file" .swift)"
  guard_exact \
    "$role stays in its role-exact file" \
    "$(guard_count_matches "^(final[[:space:]]+class|struct|enum)[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_exact \
    "$role file owns one top-level role" \
    "$(guard_count_matches '^(final[[:space:]]+class|struct|enum)[[:space:]]+' "$role_file")" \
    1
  guard_max \
    "$role stored collaborators" \
    "$(guard_count_matches '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]' "$role_file")" \
    5
done
guard_expect_no_matches \
  'shortcut regular conversion lifetime callbacks' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${shortcut_regular_conversion_services[@]}"
for shortcut_regular_conversion_service in "${shortcut_regular_conversion_services[@]}"; do
  shortcut_regular_conversion_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$shortcut_regular_conversion_service"
  )"
  guard_max \
    "$(basename "$shortcut_regular_conversion_service" .swift) stored collaborators" \
    "$shortcut_regular_conversion_collaborators" \
    5
done
guard_expect_no_matches \
  'structural and drag transactions reached through aggregate shortcut commands' \
  '\bShortcutPinCommandOwner\b' \
  Sumi/Managers/TabManager/TabFolderHierarchyMutationService.swift \
  Sumi/Managers/TabManager/TabFolderContentMutationTransaction.swift \
  Sumi/Managers/TabManager/TabFolderPlacementAdmission.swift \
  Sumi/Managers/TabManager/TabFolderPlacementCommitTransaction.swift \
  Sumi/Managers/TabManager/TabFolderPlacementTransaction.swift \
  Sumi/Managers/TabManager/TabFolderDeletionPreparationService.swift \
  Sumi/Managers/TabManager/TabFolderDeletionCommitTransaction.swift \
  Sumi/Managers/TabManager/TabFolderUngroupPreparationService.swift \
  Sumi/Managers/TabManager/TabFolderUngroupCommitTransaction.swift \
  Sumi/Managers/TabManager/TabFolderRetirementTransaction.swift \
  Sumi/Managers/TabManager/TabFolderTabPlacementTransaction.swift \
  Sumi/Managers/TabManager/SidebarRegularTabDragService.swift \
  Sumi/Managers/TabManager/ShortcutDragOperationOwner.swift
guard_expect_no_matches \
  'shortcut retirement physical-cleanup duplication' \
  'performComprehensiveWebViewCleanup|webViewLifecycle\.(unloadTab|requireRemoveAllWebViews)|\.detach\s*\(' \
  Sumi/Managers/TabManager/ShortcutLiveRetirement*.swift \
  Sumi/Managers/TabManager/ShortcutLiveTabRetirementService*.swift
guard_expect_no_matches \
  'shortcut retirement browser/notification policy' \
  '\bBrowserManager\b|BrowserNotificationPresenting|\bnotifications\b' \
  Sumi/Managers/TabManager/ShortcutLiveTabRetirementService.swift \
  Sumi/Managers/TabManager/ShortcutSelectionReconciler.swift
guard_expect_no_matches \
  'shortcut retirement Bool-mode phase API' \
  '(requiringAttachment|modelClaimed|publishesTabClosure)\s*:' \
  "${shortcut_runtime_services[@]}"

guard_expect_no_matches \
  'raw shortcut-presentation preview mode API' \
  '\bpreviewPins\b|\bpreviewPin\s*:' \
  Sumi/Managers/TabManager/ShortcutPresentationActivationAdmission.swift \
  Sumi/Managers/TabManager/ShortcutPresentationActivationService.swift \
  Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift \
  Sumi/Managers/SplitRuntime/SplitDropPresentationReconciling.swift
guard_expect_no_matches \
  'split presentation regained callback dependency wiring' \
  '@escaping|private let [A-Za-z_][A-Za-z0-9_]*: @MainActor .*->' \
  Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift \
  Sumi/Managers/SplitRuntime/WindowSplitPresentationEffectExecutor.swift
guard_exact \
  'split presentation receives one concrete effect executor' \
  "$(
    guard_count_matches \
      'terminalEffects: WindowSplitPresentationEffectExecutor' \
      Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift
  )" \
  1
guard_expect_no_matches \
  'raw catalog-insertion activation without contributed residence' \
  'case\s+catalogInsertion\(ShortcutPresentationCatalogInsertionPreview\)|prepareActivation\(\s*draft\.activationRequests,\s*preview:' \
  -U \
  Sumi/Managers/TabManager/ShortcutPresentationActivationService.swift \
  Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift \
  Sumi/Managers/SplitRuntime/WindowSplitPresentationResidencePreparer.swift
guard_expect_no_matches \
  'raw insertion-preview activation overload' \
  'func\s+prepareActivation\(\s*_\s+requests:\s*\[Request\],\s*preview:' \
  -U \
  Sumi/Managers/TabManager/ShortcutPresentationActivationService.swift
guard_expect_no_matches \
  'launcher catalog transaction exposed raw stores' \
  '^    let (pinStore|pins):' \
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogTransaction.swift
guard_expect_no_matches \
  'prepared structural aggregate retaining its mutation owner unowned' \
  'unowned let owner: TabStructuralCollectionMutationOwner' \
  Sumi/Managers/TabManager/TabStructuralCollectionPreparedAggregate.swift
guard_expect_no_matches \
  'optional shortcut profile admission' \
  'PreparedTabProfileAssignment\?|compactMap\(\\\.assignment\)' \
  -g '*.swift' Sumi
guard_expect_no_matches \
  'detached shortcut profile batch model-only fallback' \
  '\bProfileTransitionModelOnlySettlement\b' \
  Sumi/Managers/TabManager/ShortcutTabProfileAssignmentBatch.swift
guard_expect_no_matches \
  'imperative live-shortcut residence staging bypass' \
  '^    func (register|relocate|remove)\(' \
  Sumi/Managers/TabManager/LiveShortcutResidenceMutationStaging.swift

guard_expect_no_matches \
  'split-shortcut Actions/Dependencies bags' \
  'struct (Actions|Dependencies)\b' \
  "${split_shortcut_services[@]}"
guard_expect_no_matches \
  'split-shortcut BrowserManager reachback' \
  '\bBrowserManager\b|\bbrowserManager\b' \
  "${split_shortcut_services[@]}"
guard_expect_no_matches \
  'sidebar command manager reachback' \
  '\b(BrowserManager|TabManager|browserManager|tabManager)\b' \
  "${sidebar_command_services[@]}"
guard_expect_no_matches \
  'sidebar command dependency bags' \
  'struct (Actions|Dependencies|Context)\b' \
  "${sidebar_command_services[@]}"
guard_expect_no_matches \
  'sidebar Space transition callback storage' \
  'private let [A-Za-z0-9_]+(Action)?:[[:space:]]*(@MainActor[[:space:]]*)?\(' \
  Sumi/Managers/BrowserManager/BrowserSidebarSpaceTransitionRoutingOwner.swift
guard_expect_no_matches \
  'sidebar browser callback action bags' \
  'struct Sidebar(BrowserPresentationActions|SpaceTransitionActions|BrowserCommandActions)|let (presentationActions|commands):' \
  Sumi/Components/Sidebar/SidebarBrowserContext.swift
guard_expect_no_matches \
  'sidebar browser callback fields' \
  '^[[:space:]]+let [A-Za-z_][A-Za-z0-9_]*:.*->' \
  Sumi/Components/Sidebar/SidebarBrowserContext.swift
guard_expect_no_matches \
  'window Space transition manager-fed initializer or hidden split lookup' \
  'BrowserWindowSpaceTransitionService\(browserManager:|convenience init\(browserManager:|splitComposition' \
  Sumi/Managers/BrowserManager/BrowserWindowSpaceTransitionService+Live.swift
sidebar_extension_action_roles=(
  Sumi/Components/Sidebar/SidebarExtensionActionTabQuery.swift
)
guard_expect_no_matches \
  'sidebar extension-action role manager reachback or generic bag' \
  '\bBrowserManager\b|\bstruct[[:space:]]+(Dependencies|Actions|Context|Capabilities)\b' \
  "${sidebar_extension_action_roles[@]}"
guard_expect_no_matches \
  'sidebar extension-action stored callbacks' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${sidebar_extension_action_roles[@]}"
for sidebar_extension_action_role in "${sidebar_extension_action_roles[@]}"; do
  sidebar_extension_action_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)\b' \
      "$sidebar_extension_action_role"
  )"
  guard_max \
    "$(basename "$sidebar_extension_action_role" .swift) stored collaborators" \
    "$sidebar_extension_action_collaborators" \
    4
done
guard_expect_no_matches \
  'window/sidebar feature contexts reached through TabManager or manager-fed live factories' \
  '\bbrowserManager\.tabManager\b|\bTabManager\b|static func live\b' \
  Sumi/Managers/BrowserManager/BrowserWindowViewContextComposition.swift \
  Sumi/Components/Sidebar/SidebarBrowserContext.swift
guard_expect_no_matches \
  'BrowserManager composition hidden behind a broad tabs alias' \
  'let[[:space:]]+tabs[[:space:]]*=[[:space:]]*self\b' \
  Sumi/Managers/BrowserManager/BrowserManager+WindowSidebarComposition.swift \
  Sumi/Managers/BrowserManager/BrowserManager+SidebarCommandComposition.swift \
  Sumi/Managers/BrowserManager/BrowserManager+SplitComposition.swift
guard_expect_no_matches \
  'launcher placement manager reachback' \
  '\b(TabManager|BrowserManager|tabManager|browserManager)\b' \
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService.swift
guard_expect_no_matches \
  'split services stored runtime managers' \
  '^    private let [A-Za-z_]+: TabManager\b' \
  Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift \
  Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreService.swift \
  Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift
guard_expect_no_matches \
  'split services separate runtime providers' \
  '^    private let [A-Za-z_]+: \(\) -> TabManager\?' \
  Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift \
  Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreService.swift \
  Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift
guard_expect_no_matches \
  'durable window write archive/scheduler reachback' \
  'LastSessionWindowArchive|OpenWindowSessionCatalog|WindowSessionPersistenceScheduler' \
  Sumi/Services/WindowSessionPersistenceService.swift
guard_expect_no_matches \
  'restore service raw persistence dependency' \
  'WindowSessionPersistenceService' \
  Sumi/Services/WindowSessionRestoreService.swift
guard_expect_no_matches \
  'raw durable API outside coordinator' \
  '\.(persistDurableSnapshot|durableWrite)\s*\(' \
  -g '*.swift' -g '!WindowSessionPersistenceCoordinator.swift' \
  App FloatingBar SidebarChrome Settings Sumi UI
guard_expect_no_matches \
  'window-history BrowserManager reachback' \
  '\bbrowserManager\b|\bBrowserManager\b' \
  "${window_history_services[@]}"
guard_expect_no_matches \
  'behavior in WindowSessionHistoryServices capability group' \
  '\bfunc ' \
  Sumi/Managers/BrowserManager/WindowSessionHistoryServices.swift
guard_expect_no_matches \
  'window service BrowserManager reachback' \
  '\bbrowserManager\b|BrowserManager\(' \
  Sumi/Managers/BrowserManager/BrowserWindowTabContext.swift \
  Sumi/Managers/BrowserManager/BrowserWindowVisualCoordinator.swift

guard_expect_no_matches \
  'floating-bar Actions/Dependencies bags' \
  'struct (Actions|Dependencies)' \
  "${floating_bar_services[@]}"
guard_expect_no_matches \
  'floating-bar BrowserManager reachback' \
  '\bbrowserManager\b|BrowserManager\(' \
  "${floating_bar_services[@]}"
guard_expect_no_matches \
  'behavior in FloatingBarServices capability group' \
  '\bfunc ' \
  Sumi/Services/FloatingBarServices.swift

guard_expect_no_matches \
  'active-page Actions/Dependencies bags' \
  'struct (Actions|Dependencies)' \
  "${active_page_services[@]}"
guard_expect_no_matches \
  'active-page BrowserManager reachback' \
  '\bbrowserManager\b|BrowserManager\(' \
  "${active_page_services[@]}"
guard_expect_no_matches \
  'active-page live-composition stored state' \
  '^    (private )?(let|var|lazy var) ' \
  Sumi/Managers/BrowserManager/BrowserShellRuntime+ActivePage.swift
guard_expect_no_matches \
  'URL-bar active-page reach-through' \
  'urlBarBundle\.activePage|activePageRoutingOwner' \
  -g '*.swift' App FloatingBar SidebarChrome Settings Sumi UI SumiTests
guard_expect_no_matches \
  'sidebar drop URL-bar reach-through' \
  'urlBarBundle' \
  Sumi/Components/DragDrop/SidebarDropCoordinator.swift
guard_expect_no_matches \
  'manual URL-bar active-page resolution' \
  'glanceManager\.active(Session|Preview)|ephemeralTabs|tabForID' \
  Sumi/Components/Sidebar/URLBarView.swift
guard_expect_no_matches \
  'external URL runtime strong retention' \
  'private (let|var) (windowRegistry|tabOpening):' \
  Sumi/Services/ExternalURLTabOpeningService.swift

startup_protection_roles=(
  Sumi/Managers/BrowserManager/BrowserStartupProtectionRuntime.swift
  Sumi/Managers/BrowserManager/BrowserStartupProtectionLevelRestoration.swift
  Sumi/Managers/BrowserManager/BrowserStartupDeferredTabMaterialization.swift
  Sumi/Managers/BrowserManager/BrowserStartupVisibleWindowSettlement.swift
)
for startup_protection_role in "${startup_protection_roles[@]}"; do
  guard_require_file "$startup_protection_role"
done
guard_expect_no_matches \
  'startup protection manager/tab-opening reachback' \
  '\bBrowserManager\b|\btabOpening\b' \
  "${startup_protection_roles[@]}"
guard_expect_no_matches \
  'startup protection stored callback graph' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${startup_protection_roles[@]}"
startup_protection_runtime_collaborators="$(
  guard_count_matches \
    '^[[:space:]]*private[[:space:]]+let[[:space:]]+' \
    Sumi/Managers/BrowserManager/BrowserStartupProtectionRuntime.swift
)"
guard_max \
  'startup protection runtime collaborators' \
  "$startup_protection_runtime_collaborators" \
  3

tab_close_roles=(
  Sumi/Managers/BrowserManager/BrowserTabCloseOrchestrationOwner.swift
  Sumi/Managers/BrowserManager/BrowserCurrentTabCloseContext.swift
  Sumi/Managers/BrowserManager/BrowserRegularTabClosePresentation.swift
  Sumi/Managers/BrowserManager/BrowserRegularTabCloseTransaction.swift
  Sumi/Managers/BrowserManager/BrowserIncognitoTabCloseTransaction.swift
  Sumi/Managers/BrowserManager/GlanceTabCloseInterception.swift
  Sumi/Managers/BrowserManager/BrowserTabCloseRouting.swift
)
for tab_close_role in "${tab_close_roles[@]}"; do
  guard_require_file "$tab_close_role"
  tab_close_role_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+let[[:space:]]+' \
      "$tab_close_role"
  )"
  guard_max \
    "$tab_close_role collaborators" \
    "$tab_close_role_collaborators" \
    4
done
guard_expect_no_matches \
  'tab-close orchestration manager reachback or stored callbacks' \
  '\bBrowserManager\b|^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${tab_close_roles[@]}"

tab_opening_roles=(
  Sumi/Managers/BrowserManager/BrowserTabOpeningOwner.swift
  Sumi/Managers/BrowserManager/BrowserTabOpenDestinationResolver.swift
  Sumi/Managers/BrowserManager/BrowserTabOpenActivation.swift
  Sumi/Managers/BrowserManager/BrowserRegularTabOpeningTransaction.swift
  Sumi/Managers/BrowserManager/BrowserEphemeralTabOpeningTransaction.swift
)
for tab_opening_role in "${tab_opening_roles[@]}"; do
  guard_require_file "$tab_opening_role"
  tab_opening_role_collaborators="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+let[[:space:]]+' \
      "$tab_opening_role"
  )"
  guard_max \
    "$tab_opening_role collaborators" \
    "$tab_opening_role_collaborators" \
    4
done
guard_expect_no_matches \
  'tab-opening manager reachback or stored callbacks' \
  '\bBrowserManager\b|^[[:space:]]*private[[:space:]]+let[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:.*->' \
  "${tab_opening_roles[@]}"

guard_finish 'living architecture structural boundaries'
