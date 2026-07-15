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
  "Sumi/Models/Tab/TabCommittedDocumentOwner.swift"
  "Sumi/Models/Tab/TabDocumentSuspensionOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserRecentlyClosedRestoreOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserStartupPolicyOwner.swift"
  "Sumi/Managers/BrowserManager/BrowserWindowSpaceStateOwner.swift"
  "Sumi/Managers/TabManager/TabProfileRuntimeStateOwner.swift"
  "SumiTests/TabProfileRuntimeStateOwnerTests.swift"
  "Sumi/Managers/TabManager/TabSpaceLifecycleOwner.swift"
  "Sumi/Managers/TabManager/TabTargetSpaceResolver.swift"
  "Sumi/Managers/BrowserManager/BrowserSidebarSplitShortcutRoutingOwner.swift"
  "SumiTests/BrowserSidebarSplitShortcutRoutingOwnerTests.swift"
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
)

for retired_path in "${retired_paths[@]}"; do
  guard_expect_absent_path "retired architecture surface $retired_path" "$retired_path"
done

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
  'TabTargetSpaceResolver|\bprofileIdForNewTab\b|\brequestTargetSpaceProfileBackfill\b|\binitialExplicitProfileId\b|\bprofileIdForUnassignedSpace\b|\bcreateNewTabWithWebView\b|\bduplicateAsRegularForSplit\b' \
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
  'ShortcutLiveTabRetirementOwner|ShortcutSelectionReconciliationOwner|ShortcutLiveTabServices' \
  -g '*.swift' "${product_roots[@]}"

guard_expect_no_matches \
  'retired split-shortcut routing hub' \
  'BrowserSidebarSplitShortcutRoutingOwner|BrowserSidebarSplitShortcutRouting|splitShortcutRouting' \
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
