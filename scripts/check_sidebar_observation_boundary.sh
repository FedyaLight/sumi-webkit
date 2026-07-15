#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

die() {
  echo "sidebar observation boundary: $1" >&2
  exit 1
}

forbid() {
  local pattern="$1"
  local message="$2"
  local matches
  local status
  shift 2
  if matches="$(rg -n -e "$pattern" "$@")"; then
    printf '%s\n' "$matches"
    die "$message"
  else
    status=$?
  fi
  if [[ "$status" -ne 1 ]]; then
    echo "sidebar observation boundary: rg failed with status $status" >&2
    return "$status"
  fi
}

require() {
  local pattern="$1"
  local message="$2"
  local status
  shift 2
  if rg -q -e "$pattern" "$@"; then
    return 0
  else
    status=$?
  fi
  if [[ "$status" -eq 1 ]]; then
    die "$message"
  fi
  echo "sidebar observation boundary: rg failed with status $status" >&2
  return "$status"
}

require_absent() {
  local path
  for path in "$@"; do
    if [[ -e "$path" ]]; then
      die "retired architecture regrew at $path"
    fi
  done
}

sidebar_root="SidebarChrome/Sidebar/SpacesSideBarView.swift"
sidebar_page="SidebarChrome/Sidebar/SpaceSidebarPageChrome.swift"
pinned_grid="Sumi/Components/Sidebar/PinnedButtons/PinnedGrid.swift"
updates="Sumi/Components/Sidebar/SidebarUpdateStreams.swift"
composition="Sumi/Managers/BrowserManager/BrowserWindowViewContextComposition.swift"
event_bus="Sumi/BrowserRuntime/TabStructureEventBus.swift"
extension_surface="Sumi/Services/BrowserExtensionSurfaceStore.swift"
extension_view="Sumi/Components/Extensions/ExtensionActionView.swift"
url_bar="Sumi/Components/Sidebar/URLBarView.swift"
url_hub="Sumi/Components/Sidebar/URLBarHubPopover.swift"
live_folders="Sumi/LiveFolders/SumiLiveFolderManager.swift"
live_folder_view="Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift"
residence_store="Sumi/Managers/TabManager/LiveShortcutTabResidenceStore.swift"
residence_snapshot="Sumi/Managers/TabManager/LiveShortcutTabSnapshot.swift"
residence_transaction="Sumi/Managers/TabManager/LiveShortcutPresentationResidenceTransaction.swift"
structural_lookup="Sumi/Managers/TabManager/TabStructuralLookupCoordinator.swift"
lifecycle="Sumi/Managers/TabManager/TabManagerWebViewLifecycleService.swift"
empty_split="Sumi/Managers/SplitRuntime/EmptySplitService.swift"
empty_split_session="Sumi/Managers/SplitRuntime/EmptySplitSession.swift"
split_member_resolver="Sumi/Managers/SplitRuntime/SplitRuntimeMemberResolver.swift"
placeholder_planner="Sumi/Managers/SplitRuntime/SplitPlaceholderReplacementPlanner.swift"
regular_tab_cleanup="Sumi/Managers/TabManager/RegularTabClosureRuntimeCleanup.swift"
split_coordination="Sumi/BrowserRuntime/Ports/TabSplitCoordinationPort.swift"
replacement_contract="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebViewReplacementSettlement.swift"
replacement_service="Packages/SumiWebRuntime/Sources/SumiWebRuntime/Transactions/WebViewReplacementSettlementService.swift"

# Broad Sidebar relays and UI-owned manager graphs are architectural
# tombstones. Commands may be injected as capabilities, never rediscovered by
# a mounted rendering root.
forbid '\b(SidebarSpacePageModel|SidebarChromeModel|tabStructuralRevision)\b' \
  "broad Sidebar relay/revision owner regrew" App Sumi SidebarChrome
forbid 'objectWillChange|let _ = .*Revision' \
  "a Sidebar rendering root regained broad invalidation" \
  "$sidebar_root" "$pinned_grid"
forbid ':\s*TabManager\b|\(\)\s*->\s*TabManager\??|\btabManager\.' \
  "Sidebar UI regained direct TabManager reach-through" \
  SidebarChrome/Sidebar Sumi/Components/Sidebar
forbid 'structureChangedPublisher|AnyPublisher<Void, Never>' \
  "Sidebar composition regained a global Void structure stream" \
  "$composition" "$updates"

# The stable observation contract is typed scopes plus demand-scoped readers.
require 'scopedStructureChangesPublisher' \
  "composition no longer injects the scoped structure stream" "$composition"
require 'AnyPublisher<TabStructureChangeScope, Never>' \
  "Sidebar inventory updates lost their typed scope" "$updates"
require 'func pageChanges' "page-scoped update stream is missing" "$updates"
require '\.affectsPage\(' "page stream no longer filters before recompute" "$updates"
require '\.filter\(\\\.affectsSpaceCatalog\)' \
  "catalog stream no longer filters catalog changes" "$updates"
require 'guard cancellable == nil' \
  "scoped reader lost inactive/duplicate subscription gating" "$updates"
require 'cancellable = nil' \
  "scoped reader no longer releases inactive subscriptions" "$updates"
require 'cancellable = changes' \
  "scoped reader no longer subscribes before its demand-time read" "$updates"
require 'snapshot = current\(\)' \
  "scoped reader lost its fresh demand-time snapshot" "$updates"
require 'SidebarScopedSnapshotReader' \
  "Space catalog root no longer uses a demand-scoped reader" "$sidebar_root"
require 'SidebarScopedSnapshotReader' \
  "live-folder leaf no longer uses a demand-scoped reader" "$live_folder_view"
require 'struct TabStructurePageScope' \
  "structure events lost physical window/page identity" "$event_bus"
require 'affectedPages: Set<TabStructurePageScope>' \
  "structure events lost exact page membership" "$event_bus"

# Disabled/offscreen extension and folder surfaces must remain zero-cost and
# leaf-scoped. Direct observation of the broad extension store is forbidden.
forbid '@(ObservedObject|EnvironmentObject).*BrowserExtensionSurfaceStore|@ObservedObject var surfaceStore' \
  "rendered extension UI regained broad store observation" \
  SidebarChrome Sumi/Components/Sidebar "$extension_view"
forbid '\.environmentObject\([^)]*(extensionSurfaceStore|surfaceStore)' \
  "broad extension store injection regrew" App SidebarChrome Sumi/Components/Sidebar
forbid 'extensionSurfaceStore|toolbarDisplaySnapshot' \
  "URL/Hub root regained an unsubscribed extension-store read" \
  "$url_bar" "$url_hub"
require 'setDemanded\(' "URL bar lost explicit display demand" "$url_bar"
require 'setDemanded\(' "Hub lost explicit display demand" "$url_hub"
require 'guard isDemanded, moduleEnabled' \
  "extension display work is no longer gated by demand and enablement" \
  "$extension_surface"
require 'surfaceCancellable = changes\(profileID\)' \
  "extension display lost scoped subscribe-before-read" "$extension_surface"
require 'publish\(current\(profileID\)\)' \
  "extension display lost its fresh demand-time read" "$extension_surface"
require 'toolbarLayoutChanges\(for: profileId\)' \
  "rendered page lost profile-scoped toolbar updates" "$sidebar_page"
forbid 'CombineLatest|\$sourcesByFolderId|\$itemsBySourceId' \
  "live-folder leaf regained global dictionary remapping" "$live_folders"
require 'filter \{ \$0 == folderId \}' \
  "live-folder updates are no longer folder-scoped" "$live_folders"

# A live shortcut slot owns Tab + immutable presentation page atomically. All
# same-pin relocations share one rollback-capable transaction and publish the
# exact mounted page.
require 'entriesByWindow: \[UUID: \[UUID: LiveShortcutTabEntry\]\]' \
  "live shortcut store lost atomic entry slots" \
  "$residence_store" "$residence_snapshot"
forbid 'presentationPagesByWindow' \
  "parallel live-shortcut Tab/page maps regrew" \
  "$residence_store" "$residence_snapshot"
require 'final class LiveShortcutPresentationResidenceTransaction' \
  "shared presentation residence transaction is missing" "$residence_transaction"
require 'requestPublish\(scope: entry.pageScope\)' \
  "live shortcut mutation lost exact page publication" "$structural_lookup"
forbid '\.runtimeOnly' \
  "live shortcut mutation is filtered from mounted pages" \
  Sumi/Managers/TabManager/LiveShortcutTabRegistry.swift \
  Sumi/Managers/TabManager/LiveShortcutPresentationRefreshService.swift \
  Sumi/Managers/TabManager/ShortcutTabBindingSynchronizer.swift \
  Sumi/Managers/TabManager/ShortcutTabBindingRuntimeMutation.swift

# Direct transaction paths use typed participants. Independently injectable
# effect callbacks and fail-open model defaults are forbidden here.
forbid 'private let .*: \(' \
  "WebView lifecycle facade regained stored effect callbacks" "$lifecycle"
require 'any TabWebViewRetirementParticipant' \
  "WebView lifecycle lost its cohesive retirement participant" "$lifecycle"
forbid '\(\)\s*->\s*TabManager\??|\btabManager\.' \
  "EmptySplit regained a TabManager locator" "$empty_split"
require 'placeholderByWindowID: \[UUID: Tab\]' \
  "EmptySplit session lost exact placeholder identity" "$empty_split_session"
require 'structuralTransactions\.withTransaction' \
  "EmptySplit discard publishes before exact runtime retirement" "$empty_split"
require 'structuralTransactions\.withTransaction' \
  "EmptySplit cancellation publishes before exact runtime retirement" \
  "$empty_split_session"
forbid 'placeholderTabIDByWindowID|removeTab\(placeholder\.id\)' \
  "EmptySplit regained UUID-only placeholder settlement" \
  "$empty_split" "$empty_split_session"
require 'candidate == nil \|\| candidate === canonical' \
  "split resolution can adopt a same-ID replacement for a stale candidate" \
  "$split_member_resolver"
require 'regularTabs\.tab\(for: placeholderTabID\) === placeholder' \
  "placeholder replacement planning lost exact physical admission" \
  "$placeholder_planner"
require 'let splitSettlement = runtime\.stageTabClosures' \
  "regular Tab cleanup lost staged split presentation" "$regular_tab_cleanup"
require 'splitSettlement\?\.publish\(\)' \
  "split presentation no longer waits for terminal runtime cleanup" \
  "$regular_tab_cleanup"
forbid 'func handleTabClosures\(' \
  "split closure regained immediate pre-cleanup presentation" \
  "$split_coordination" "$regular_tab_cleanup"
require 'protocol WebViewReplacementModelTransaction' \
  "replacement settlement lost its typed model transaction" "$replacement_contract"
require 'model: WebViewReplacementModelParticipant' \
  "replacement settlement no longer requires an explicit model participant" \
  "$replacement_service"
forbid 'stagedModelIsExact:.*= \{ true \}|canClaimTerminalModel:.*= \{ true \}|claimTerminalModel:.*=|modelRollbackPublication:.*=' \
  "replacement settlement regained fail-open model defaults" \
  "$replacement_service"

require_absent \
  "Sumi/Managers/TabManager/LiveShortcutPresentationResidences.swift" \
  "Sumi/Managers/TabManager/TabStructuralMutationEffectBuffer.swift" \
  "Sumi/Managers/TabManager/DisplayedTabShortcutSourceTransition.swift" \
  "Sumi/Managers/TabManager/DeletedSpaceWindowCurrentSelectionPruner.swift" \
  "Sumi/Managers/TabManager/SpaceProfileMutationPublicationOwner.swift" \
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogAdapter.swift" \
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherReleaseAdmission.swift" \
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveBatchCheckpointStaging.swift" \
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherDestinationSettlement.swift" \
  "Sumi/Managers/BrowserManager/ShortcutSplitLauncherStagedMoveSettlement.swift"

echo "sidebar observation boundary passed"
