#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

session_recovery_services=(
  "Sumi/Managers/BrowserManager/ClosedTabRestoreService.swift"
  "Sumi/Managers/BrowserManager/ClosedShortcutRestoreService.swift"
  "Sumi/Managers/BrowserManager/WindowSessionReopenService.swift"
  "Sumi/Managers/BrowserManager/LastSessionWindowsRestoreService.swift"
  "Sumi/Managers/BrowserManager/RecentlyClosedItemReopenService.swift"
  "Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands.swift"
)
tab_space_services=(
  "Sumi/Managers/TabManager/SpaceCatalogCommands.swift"
  "Sumi/Managers/TabManager/SpaceRemovalService.swift"
  "Sumi/Managers/TabManager/SpaceActivationService.swift"
  "Sumi/Managers/TabManager/TabCreationPlacementService.swift"
  "Sumi/Managers/TabManager/SpaceContentRetirementService.swift"
  "Sumi/Managers/TabManager/SpaceContentRetirementTransaction.swift"
  "Sumi/Managers/TabManager/SpaceSplitGroupRetirementService.swift"
  "Sumi/Managers/TabManager/SpaceTabInventory.swift"
  "Sumi/Managers/TabManager/DeletedSpaceWindowStateReconciler.swift"
  "Sumi/Managers/TabManager/DeletedSpaceWindowReferencePruner.swift"
  "Sumi/Managers/TabManager/TabRuntimeTeardownService.swift"
  "Sumi/Managers/TabManager/TabRuntimeTeardownPreparationService.swift"
)
shortcut_runtime_services=(
  "Sumi/Managers/TabManager/LiveShortcutTabRegistry.swift"
  "Sumi/Managers/TabManager/LiveShortcutTabSnapshot.swift"
  "Sumi/Managers/TabManager/ShortcutTabWindowQuery.swift"
  "Sumi/Managers/TabManager/ShortcutTabBindingSynchronizer.swift"
  "Sumi/Managers/TabManager/ShortcutTabMaterializer.swift"
  "Sumi/Managers/TabManager/RegularTabShortcutConversionService.swift"
  "Sumi/Managers/TabManager/RegularTabShortcutConversionService+Live.swift"
  "Sumi/Managers/TabManager/ShortcutPinToRegularTabService.swift"
  "Sumi/Managers/TabManager/RegularTabShortcutConversionPlanner.swift"
  "Sumi/Managers/TabManager/DisplayedTabShortcutConversionCommitter.swift"
  "Sumi/Managers/TabManager/TabShortcutConversionAuthorizer.swift"
  "Sumi/Managers/TabManager/RegularTabShortcutStructureTransition.swift"
  "Sumi/Managers/TabManager/RegularTabShortcutStructurePlan.swift"
  "Sumi/Managers/TabManager/ShortcutTabPromotionService.swift"
  "Sumi/Managers/TabManager/ShortcutLiveTabRetirementService.swift"
  "Sumi/Managers/TabManager/ShortcutLiveTabRetirementTransaction.swift"
  "Sumi/Managers/TabManager/ShortcutSelectionReconciler.swift"
)
split_shortcut_services=(
  "Sumi/Managers/BrowserManager/SplitShortcutFocusService.swift"
  "Sumi/Managers/BrowserManager/WindowSplitMaterializationService.swift"
  "Sumi/Managers/BrowserManager/SplitShortcutMemberResolver.swift"
  "Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreService.swift"
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherPlacementService.swift"
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherDestinationResolver.swift"
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveTransaction.swift"
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogAdapter.swift"
  "Sumi/Managers/BrowserManager/ShortcutHostedSplitUnloadService.swift"
)
window_history_services=(
  "Sumi/Managers/BrowserManager/OpenWindowSessionCatalog.swift"
  "Sumi/Managers/BrowserManager/LastSessionWindowArchive.swift"
  "Sumi/Managers/BrowserManager/ClosedWindowHistoryRecorder.swift"
  "Sumi/Managers/BrowserManager/WindowSessionHistoryServices.swift"
)
floating_bar_services=(
  "Sumi/Services/FloatingBarPresentationService.swift"
  "Sumi/Services/FloatingBarCommitService.swift"
  "Sumi/Services/FloatingBarPageNavigationService.swift"
  "Sumi/Services/FloatingBarServices.swift"
)
active_page_services=(
  "Sumi/Managers/BrowserManager/ActivePageResolver.swift"
  "Sumi/Managers/BrowserManager/ActivePageCommandService.swift"
  "Sumi/Services/ExternalURLTabOpeningService.swift"
  "Sumi/Components/DragDrop/SidebarURLDropService.swift"
  "Sumi/Components/DragDrop/ShortcutURLInsertionService.swift"
)

required_sources=(
  "${session_recovery_services[@]}"
  "${tab_space_services[@]}"
  "${shortcut_runtime_services[@]}"
  "${split_shortcut_services[@]}"
  "${window_history_services[@]}"
  "${floating_bar_services[@]}"
  "${active_page_services[@]}"
  "Sumi/Managers/BrowserManager/BrowserSessionRecoveryCommands+Live.swift"
  "Sumi/Managers/BrowserManager/SplitShortcutServices.swift"
  "Sumi/Managers/BrowserManager/SplitShortcutServices+Live.swift"
  "Sumi/Managers/BrowserManager/WindowSessionHistoryServices+Live.swift"
  "Sumi/Managers/BrowserManager/BrowserShellRuntime+ActivePage.swift"
  "Sumi/Managers/TabManager/TabSpaceServices.swift"
  "Sumi/Managers/TabManager/TabStructuralPersistenceService.swift"
  "Sumi/Managers/TabManager/SpaceProfileRuntimeStateService.swift"
  "Sumi/Managers/BrowserManager/BrowserWindowSpaceContextReconciler.swift"
)
for source in "${required_sources[@]}"; do
  guard_require_file "$source"
done

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
  'shortcut closure dependency bags' \
  'struct Dependencies\b' \
  "${shortcut_runtime_services[@]}"
guard_expect_no_matches \
  'shortcut retirement physical-cleanup duplication' \
  'performComprehensiveWebViewCleanup|webViewLifecycle\.(unloadTab|requireRemoveAllWebViews)|\.detach\s*\(' \
  "${shortcut_runtime_services[@]}"
guard_expect_no_matches \
  'shortcut retirement browser/notification policy' \
  '\bBrowserManager\b|BrowserNotificationPresenting|\bnotifications\b' \
  Sumi/Managers/TabManager/ShortcutLiveTabRetirementService.swift \
  Sumi/Managers/TabManager/ShortcutSelectionReconciler.swift

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
