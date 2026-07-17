#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

# These paths are historical product surfaces, not living structure. Keeping
# them here prevents accidental resurrection without pretending that a deleted
# file has a meaningful zero-line architecture budget.
retired_paths=(
  "Sumi/Managers/TabManager/TabStructureOwnerBag.swift"
  "Sumi/Managers/TabManager/TabShortcutOwnerBag.swift"
  "Sumi/Managers/TabManager/TabLifecycleOwnerBag.swift"
  "Sumi/Managers/TabManager/TabManager+OwnerAccessors.swift"
  "Sumi/Managers/TabManager/ShortcutPinCommandTransactions.swift"
  "Sumi/Managers/TabManager/TabFolderMutationTransactions.swift"
  "Sumi/Managers/TabManager/ShortcutProfileReferenceMutation.swift"
  "Sumi/Managers/TabManager/TransientExtensionTabTransactions.swift"
  "Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabsController.swift"
  "Sumi/Managers/BrowserManager/BrowserTabSelectionOwner+Live.swift"
  "Sumi/Managers/BrowserManager/BrowserRecentlyClosedRestoreOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserStartupPolicyOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserWindowSpaceStateOwner.swift"
  "Sumi/Managers/TabManager/TabProfileRuntimeStateOwner.swift"
  "SumiTests/TabProfileRuntimeStateOwnerTests.swift"
  "Sumi/Managers/TabManager/TabSpaceLifecycleOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarSplitShortcutRoutingOwner.swift"
  "SumiTests/BrowserSidebarSplitShortcutRoutingOwnerTests.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarCommandRoutingOwner.swift"
  "SumiTests/BrowserSidebarCommandRoutingOwnerTests.swift"
  "SumiTests/BrowserSidebarSpaceTransitionRoutingOwnerTests.swift"
  "Sumi/Managers/BrowserManager/BrowserShortcutLiveTabCloseOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserWindowHistorySessionOwner.swift"
  "SumiTests/BrowserWindowHistorySessionOwnerTests.swift"
  "Sumi/Managers/BrowserManager/BrowserFloatingBarRoutingOwner.swift"
  "Sumi/Services/FloatingBarNavigationOwner.swift"
  "SumiTests/FloatingBarNavigationOwnerTests.swift"
  "SumiTests/BrowserFloatingBarBrowserContextOwnerTests.swift"
  "Sumi/Managers/BrowserManager/BrowserActivePageRoutingOwner.swift"
  "SumiTests/BrowserActivePageRoutingOwnerTests.swift"
  "Sumi/Managers/BrowserManager/BrowserURLBarCommands.swift"
  "Sumi/Managers/TabManager/ShortcutLiveTabRetirementPlanner.swift"
  "Sumi/Managers/TabManager/ShortcutLiveTabRetirementTransaction.swift"
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogAdapter.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/WebViewReplacementCoordinator.swift"
  "Packages/SumiWebRuntime/Sources/SumiWebRuntime/Session/WebViewReplacementTransactionStore.swift"
  "Sumi/Managers/TabManager/TabTransientWebKitTabLifecycleOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarCommandService.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarChromeCommandOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarFolderCommandOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarTabCommandOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarShortcutPromotionOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarEditorPresentationOwner.swift"
  "Sumi/Components/Sidebar/SidebarExtensionActionContextOwner.swift"
  "Sumi/Managers/BrowserManager/SidebarSplitCommands.swift"
  "Sumi/Managers/BrowserManager/SidebarSplitCommands+Live.swift"
  "Sumi/Components/Sidebar/SidebarPinFolderCommands.swift"
  "SumiTests/BrowserSidebarChromeCommandOwnerTests.swift"
  "SumiTests/BrowserSidebarFolderCommandOwnerTests.swift"
  "SumiTests/BrowserSidebarTabCommandOwnerTests.swift"
  "SumiTests/BrowserSidebarEditorPresentationOwnerTests.swift"
  "SumiTests/BrowserShortcutPinUnloadOwnerTests.swift"
  "SumiTests/BrowserSidebarPresentationOwnerTests.swift"
)

for retired_path in "${retired_paths[@]}"; do
  guard_expect_absent_path "retired architecture surface $retired_path" "$retired_path"
done

guard_expect_no_matches \
  'retired item-15 role symbols' \
  '\b(ShortcutSplitLauncherCatalogAdapter|ShortcutSplitLauncherStagedMove)\b' \
  -g '*.swift' App FloatingBar SidebarChrome Settings Sumi UI SumiTests

guard_expect_no_matches \
  'retired session-manager aggregate or manager-fed selection composition' \
  '\bAssembledSessionManagers\b|\bmakeSessionManagers\s*\(|BrowserTabSelectionOwner\.live\s*\(' \
  -g '*.swift' App FloatingBar SidebarChrome Settings Sumi UI

guard_expect_no_matches \
  'retired structural collection closure bag' \
  'TabStructuralCollectionMutationOwner\.Dependencies|extension TabStructuralCollectionMutationOwner\.Dependencies|struct Dependencies' \
  Sumi/Managers/TabManager/TabStructuralCollectionMutationOwner.swift \
  SumiTests/TabStructuralCollectionMutationOwnerTests.swift

guard_expect_no_matches \
  'retired SumiWebRuntime replacement role symbols' \
  '\b(WebViewReplacementCoordinator|WebViewReplacementTransactionStore)\b' \
  -g '*.swift' Packages/SumiWebRuntime Sumi SumiTests

guard_expect_no_matches \
  'retired sidebar aggregate and forwarding symbols' \
  '\b(BrowserSidebarCommandService|BrowserSidebarChromeCommandOwner|BrowserSidebarFolderCommandOwner|BrowserSidebarTabCommandOwner|BrowserSidebarShortcutPromotionOwner|BrowserSidebarEditorPresentationOwner|SidebarExtensionActionContextOwner|SidebarSplitCommands|SidebarPinFolderCommands|SidebarInventoryProjection|SidebarRegularTabsController|TabTransientWebKitTabLifecycleOwner)\b' \
  -g '*.swift' App FloatingBar SidebarChrome Settings Sumi UI SumiTests

product_roots=(App FloatingBar SidebarChrome Settings Sumi UI SumiTests)

guard_expect_no_matches \
  'retired terminal-finish choreography' \
  'claimAuthorityForTerminalSuccess|claimSharedFinishEffects|reserveTerminalSuccess|finishLifecycle|TabMainFrameCheckpointSettlement' \
  -g '*.swift' Sumi SumiTests

guard_expect_no_matches \
  'retired Tab profile-assignment façade' \
  'beginProfileAssignmentIntent|isCurrentProfileAssignmentIntent|hasPendingProfileAssignment|hasUnsettledProfileAssignment|cancelPendingProfileAssignment|commitProfileAssignmentIntent|stageProfileAssignmentIntent|isCurrentStagedProfileAssignmentIntent|finishStagedProfileAssignmentIntent|rollbackStagedProfileAssignmentIntent|abortProfileAssignmentIntent' \
  -g '*.swift' Sumi SumiTests

guard_expect_no_matches \
  'retired application command hubs' \
  'BrowserLifecycleBundle|BrowserAppCommandRouter|\bappCommandRouter\b' \
  -g '*.swift' App Sumi UI

guard_expect_no_matches \
  'retired window-session reach-through' \
  'windowSessionBundle\.(tabContextOwner|visualMutationOwner|scopedNavigationOwner|commands|windowStateValidationOwner|spaceStateOwner)|BrowserWindow(TabContextOwner|VisualMutationOwner|ScopedNavigationOwner|SessionCommands|StateValidationOwner|SpaceStateOwner)' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired stateless routing objects' \
  'SumiProfileRouter|\bsumiProfileRouter\b|BrowserPermissionSiteSettingsRoutingOwner|\bpermissionSiteSettingsRoutingOwner\b' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired recently-closed restore hub' \
  'BrowserRecentlyClosedRestoreOwner|recentlyClosedRestoreOwner|BrowserHistoryMenuOwner|historyMenuOwner' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired window Space-state owner' \
  'BrowserWindowSpaceStateOwner|windowSpaceStateOwner' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired profile-runtime owner' \
  'TabProfileRuntimeStateOwner|updateProfileRuntimeStates' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired Tab Space lifecycle owner' \
  'TabSpaceLifecycleOwner|\bspaceLifecycleOwner\b' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired embedded Space-creation follower state' \
  'InFlightCreationFollower|creationFollowersBySpaceID|inheritCommittedCreationFollowers|discardCreationFollowers|takeCreationFollowers' \
  Sumi/Managers/TabManager/SpaceProfileTransitionService.swift

guard_expect_no_matches \
  'retired tab-creation resolver API' \
  '\bprofileIdForNewTab\b|\brequestTargetSpaceProfileBackfill\b|\binitialExplicitProfileId\b|\bprofileIdForUnassignedSpace\b|\bcreateNewTabWithWebView\b|\bduplicateAsRegularForSplit\b' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired shortcut conversion hubs' \
  '\b(DisplayedTabShortcutConverter|DisplayedTabShortcutConversionPlanner|ShortcutPinConversionOwner|TabShortcutConversionService)\b' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired shortcut live-tab hub' \
  'ShortcutLiveTabOwner|ShortcutLiveTabWindowQueryOwner|\bshortcutLiveTabOwner\b|ShortcutLiveTabServices' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired shortcut retirement surface' \
  'deactivateShortcutLiveTab|userInitiatedUnload|removeLiveShortcutTabs|clearDeletedShortcutPinSelectionReferences|persistWindowSessionsForShortcutSelectionCleanup|ShortcutPinSelectionCleanupResult' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired shortcut retirement owners' \
  'ShortcutLiveTabRetirementOwner|ShortcutLiveTabRetirementAdmission|ShortcutSelectionReconciliationOwner|ShortcutLiveTabServices' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired direct shortcut retirement pipeline' \
  'ShortcutLiveTabRetirementPlanner|ShortcutLiveTabRetirementTransaction' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired deleted-Space selection-history wrapper' \
  'DeletedSpaceWindowSelectionHistoryPruner' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired split-shortcut routing hub' \
  'BrowserSidebarSplitShortcutRoutingOwner|BrowserSidebarSplitShortcutRouting|splitShortcutRouting' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired sidebar callback action bags' \
  'SidebarBrowserPresentationActions|SidebarSpaceTransitionActions|SidebarBrowserCommandActions|BrowserSidebarCommandRoutingOwner|makeCommandActions|makeSpaceTransitionActions' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired live-shortcut close owner' \
  'BrowserShortcutLiveTabCloseOwner' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired window-session pending-write API' \
  'WindowSessionPendingWrite|commitWhileRuntimeIsLive|commitDurableSnapshotOnly|\bpendingWrite\s*\(' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired window-history session owner' \
  'BrowserWindowHistorySessionOwner|\bhistorySessionOwner\b' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired floating-bar forwarding hubs' \
  'BrowserFloatingBarRoutingOwner|FloatingBarNavigationOwner|BrowserFloatingBarBrowserContextOwner|floatingBarRoutingOwner|floatingBarBrowserContextOwner' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired active-page routing hubs' \
  'BrowserActivePageRoutingOwner|activePageRoutingOwner|BrowserURLBarCommands' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired closure runtime-context handlers' \
  '\b(visibleWebViewPreparationRuntime|cleanupScopeRuntime|hiddenCloneEvictionRuntime|deferredProtectedCommandRuntime|trackedCleanupExecutionRuntime|webViewShutdownRuntime)\s*\(' \
  -g '*.swift' App FloatingBar SidebarChrome Settings Sumi UI

guard_finish 'architecture tombstones'
