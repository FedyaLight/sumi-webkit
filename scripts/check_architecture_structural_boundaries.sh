#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

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
guard_require_discovered_sources 'window history' "${window_history_services[@]}"
guard_require_discovered_sources 'floating bar' "${floating_bar_services[@]}"
guard_require_discovered_sources 'active page' "${active_page_services[@]}"

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
  'BrowserManager TabManager reassignment' \
  '\bbrowserManager\.tabManager\s*=' \
  -g '*.swift' SumiTests
guard_expect_no_matches \
  'behavior in TabSpaceServices capability group' \
  '\bfunc ' \
  Sumi/Managers/TabManager/TabSpaceServices.swift

guard_expect_no_matches \
  'unsafe shortcut conversion phase API' \
  '^    func (authorize|canConvert)\(' \
  Sumi/Managers/TabManager/RegularTabShortcutConversionService.swift
guard_expect_no_matches \
  'shortcut runtime hidden in Owner bags' \
  '\b(liveShortcutTabs|shortcutTabWindowQuery|shortcutTabBindings|shortcutTabMaterializer|regularTabShortcutConversion|shortcutPinToRegularTab|shortcutTabPromotion|shortcutLiveTabRetirement)\b' \
  Sumi/Managers/TabManager/TabShortcutOwnerBag.swift \
  Sumi/Managers/TabManager/TabManager+OwnerAccessors.swift
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
  -g '!TabLastSessionMergeMaterializer.swift' \
  App FloatingBar SidebarChrome Settings Sumi UI
guard_expect_no_matches \
  'shortcut closure dependency bags' \
  'struct Dependencies\b' \
  "${shortcut_runtime_services[@]}"
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
  'launcher placement manager reachback' \
  '\b(TabManager|BrowserManager|tabManager|browserManager)\b' \
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService.swift
guard_expect_no_matches \
  'split-shortcut composition stored state' \
  '^    (private )?(let|var|lazy var) ' \
  Sumi/Managers/BrowserManager/SplitShortcutServices+Live.swift
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
  'behavior in SplitShortcutServices capability group' \
  '\bfunc ' \
  Sumi/Managers/BrowserManager/SplitShortcutServices.swift

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

guard_finish 'living architecture structural boundaries'
