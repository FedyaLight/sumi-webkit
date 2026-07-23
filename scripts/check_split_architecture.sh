#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

retired_files=(
  Sumi/Managers/SplitViewManager
  Sumi/Models/Tab/SplitGroup.swift
  Sumi/Models/Tab/SplitLayoutFactory.swift
  Sumi/Models/Tab/SplitLayoutReconciler.swift
  Sumi/Models/Tab/SplitLayoutSizing.swift
  Sumi/Models/Tab/SplitLayoutTree.swift
  Sumi/Managers/TabManager/SplitGroupCollectionStateOwner.swift
  Sumi/Managers/TabManager/SplitGroupIndexStore.swift
  Sumi/Managers/TabManager/TabManagerSplitGroupRepairOwner.swift
  Sumi/Managers/TabManager/TabSplitGroupStructureOwner.swift
  Sumi/Managers/TabManager/SpaceLauncherProjectionOwner.swift
  Sumi/Managers/SplitViewManager/SplitMembershipResolutionOwner.swift
  Sumi/Managers/BrowserManager/SidebarSplitShortcutCommands.swift
  Sumi/Managers/SplitViewManager/SplitEmptyPlaceholderOwner.swift
  Sumi/Managers/SplitViewManager/SplitPreviewStateOwner.swift
  Sumi/Managers/SplitViewManager/SplitViewManager.swift
  Sumi/Managers/SplitViewManager/WindowSplitSelectionReconciler.swift
  Sumi/Managers/BrowserManager/BrowserSplitViewRuntimeFactory.swift
  Sumi/Managers/BrowserManager/SplitShortcutRuntimeLease.swift
  Sumi/Managers/BrowserManager/SplitShortcutServices+Live.swift
  Sumi/Managers/BrowserManager/SplitShortcutServices.swift
  Sumi/Managers/BrowserManager/BrowserSplitServices.swift
  Sumi/Components/Sidebar/PinnedButtons/PinnedSplitPlaceholderTile.swift
  Sumi/Components/Sidebar/SpaceSection/ShortcutSplitPlaceholderRow.swift
  Sumi/Components/Sidebar/SpaceSection/SpaceShortcutRestorePlanner.swift
  Sumi/Managers/TabManager/SidebarDragOperationPlanner.swift
  Sumi/Managers/TabManager/SidebarDragPlanExecutor.swift
  Sumi/Managers/BrowserManager/PreparedShortcutSplitLauncherRestorationBatch.swift
  Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreHandoffReceipt.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherRestoration.swift
  Sumi/Managers/BrowserManager/SplitShortcutMemberRestoreService.swift
  SumiTests/SplitGroupCollectionStateOwnerTests.swift
  SumiTests/SplitMembershipResolutionOwnerTests.swift
  SumiTests/SplitEmptyPlaceholderOwnerTests.swift
  SumiTests/SplitPreviewStateOwnerTests.swift
  SumiTests/WindowSplitSelectionReconcilerTests.swift
  SumiTests/SplitGroupTestSupport.swift
  SumiTests/SplitGroupTests.swift
)
for file in "${retired_files[@]}"; do
  guard_expect_absent_path 'retired split surface' "$file"
done

required_domain_files=(
  Packages/SumiDomain/Sources/SumiDomain/Split/SplitMember.swift
  Packages/SumiDomain/Sources/SumiDomain/Split/SplitGroup.swift
  Packages/SumiDomain/Sources/SumiDomain/Split/SplitLayoutTree.swift
  Packages/SumiDomain/Sources/SumiDomain/Split/SplitLayoutFactory.swift
  Packages/SumiDomain/Sources/SumiDomain/Split/SplitLayoutSizing.swift
  Packages/SumiDomain/Sources/SumiDomain/Split/SplitLayoutReconciler.swift
)
for file in "${required_domain_files[@]}"; do
  guard_require_file "$file"
done

required_runtime_components=(
  Sumi/Managers/TabManager/SplitGroupStore.swift
  Sumi/Managers/TabManager/SplitGroupMutationService.swift
  Sumi/Managers/TabManager/SplitGroupMembershipQuery.swift
  Sumi/Managers/TabManager/SidebarVisualOrdering.swift
  Sumi/Managers/TabManager/SplitGroupContainerConversion.swift
  Sumi/Managers/TabManager/SplitGroupShortcutMemberRelocation.swift
  Sumi/Managers/SplitRuntime/WindowSplitProjection.swift
  Sumi/Models/Window/WindowSplitPresentation.swift
  Sumi/Managers/BrowserManager/WindowSplitMaterializationService.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveTransaction.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveBatchStaging.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveBatchCheckpoint.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveBatchParticipant.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveBatchPreparing.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveBatchReceipt.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherPreparedMove.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogMovePlan.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherBindingContribution.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogTransaction.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogSnapshot.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogPinReceipt.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherReleasePlanner.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherReleaseReceipt.swift
  Sumi/Managers/BrowserManager/PreparedShortcutSplitLauncherMoveBatch.swift
  Sumi/Managers/BrowserManager/PreparedShortcutSplitLauncherMoveSettlement.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveAggregateTransaction.swift
  Sumi/Managers/SplitRuntime/WindowSplitQuery.swift
  Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift
  Sumi/Managers/SplitRuntime/WindowSplitPresentationEffectExecutor.swift
  Sumi/Managers/SplitRuntime/WindowSplitPresentationPreparationService.swift
  Sumi/Managers/SplitRuntime/WindowSplitSessionWriteUrgency.swift
  Sumi/Managers/SplitRuntime/SplitLayoutService.swift
  Sumi/Managers/SplitRuntime/SplitDropGroupAlgebra.swift
  Sumi/Managers/SplitRuntime/SplitDropCommitEffect.swift
  Sumi/Managers/SplitRuntime/SplitDropEdgeHitPolicy.swift
  Sumi/Managers/SplitRuntime/SplitDropService.swift
  Sumi/Managers/SplitRuntime/RegularTabShortcutSidebarDropTransaction.swift
  Sumi/Managers/SplitRuntime/SplitDropTargetService.swift
  Sumi/Managers/SplitRuntime/SplitPreviewSession.swift
  Sumi/Managers/SplitRuntime/SplitWindowUpdateStream.swift
  Sumi/Managers/SplitRuntime/EmptySplitSession.swift
  Sumi/Managers/SplitRuntime/EmptySplitService.swift
  Sumi/Managers/SplitRuntime/EmptySplitCreationWorkflow.swift
  Sumi/Managers/SplitRuntime/SplitInsertionTargetResolver.swift
  Sumi/Managers/SplitRuntime/SplitInsertionService.swift
  Sumi/Managers/SplitRuntime/SplitTabClosureService.swift
)
for file in "${required_runtime_components[@]}"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'split durable model escaped the SumiDomain package' \
  '\b(struct|class|enum) (SplitGroup|SplitLayoutTree|SplitMemberID|SplitMember)\b' \
  -g '*.swift' Sumi SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'retired split identity or god surface is still referenced' \
  '\b(SplitGroupMember|SplitGroupHost|SplitGroupCollectionStateOwner|SplitGroupIndexStore|TabManagerSplitGroupRepairOwner|TabSplitGroupStructureOwner|SpaceLauncherProjectionOwner|SplitMembershipResolutionOwner|SplitEmptyPlaceholderOwner|SplitPreviewStateOwner)\b' \
  -g '*.swift' \
  Sumi SumiTests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'split responsibility was hidden behind a new Owner surface' \
  '\b(class|struct|actor) [A-Za-z0-9_]*Split[A-Za-z0-9_]*Owner\b' \
  -g '*.swift' Sumi SumiTests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'retired split composition hub or runtime callback bag is still referenced in production' \
  '\b(SplitViewManager|SplitViewRuntime)\b' \
  -g '*.swift' Sumi SumiTests SumiUITests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'split runtime depends on component-only drop capture behavior' \
  '\b(SplitDropCaptureView|SplitDropCaptureViewPolicy|SplitDropCaptureHitPolicy)\b' \
  -g '*.swift' Sumi/Managers/SplitRuntime

guard_expect_no_matches \
  'split runtime imported a UI or browser framework' \
  '^import (AppKit|SwiftUI|WebKit)$' \
  -g '*.swift' Sumi/Managers/SplitRuntime

guard_expect_no_matches \
  'retired composition-only split storage returned' \
  '\bBrowserSplitServices\b' \
  -g '*.swift' Sumi SumiTests SumiUITests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'retired split composition graph returned' \
  '\bsplitComposition\b' \
  -g '*.swift' Sumi SumiTests SumiUITests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'split composition hid exact roles behind a broad local alias' \
  'let[[:space:]]+split[[:space:]]*=' \
  Sumi/Managers/BrowserManager/BrowserManager+SplitComposition.swift \
  Sumi/Managers/BrowserManager/BrowserManager+SidebarCommandComposition.swift \
  Sumi/Managers/BrowserManager/BrowserManager+SidebarPresentationComposition.swift \
  Sumi/Managers/BrowserManager/BrowserManager+WindowSidebarComposition.swift

for split_field in \
  splitUpdateChannel splitPreviews splitQuery splitMembers splitMaterialization \
  splitPresentations splitLauncherPlacement splitLauncherRelease splitDissolution \
  splitWeightMutations splitDropTargets splitPlaceholderRetirement \
  splitPlaceholderReplacements splitDrops; do
  guard_expect_no_matches \
    "split composition field escaped its owning composition boundary: $split_field" \
    "\\b(browserManager|browserRuntime|manager)\\.${split_field}\\b" \
    -g '*.swift' \
    -g '!BrowserManager.swift' \
    -g '!BrowserManager+SplitComposition.swift' \
    Sumi
done

guard_expect_no_matches \
  'retired live-tab split API is still used outside v1 migration' \
  'SplitGroup\.make\([[:space:]]*tabIds:|\b(maximumTabs|replacingMemberTab|swappingTabs|movingTab)\b|\b(removing|inserting)\(tabId:|\b(splitGroupStructureOwner|splitGroupCollectionStateOwner|splitGroupIndexStore|splitGroupRepairOwner)\b|\b(group|groupId)\(containingMemberId:' \
  -U -g '*.swift' \
  Sumi SumiTests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'retired global split-selection API is still referenced' \
  '\b(updateActiveSplitSide|updateActiveSide|activeSplitGroup|activeSplitGroupID)\b' \
  -g '*.swift' Sumi SumiTests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'decode-only legacy split selection returned' \
  '\bactiveSplitGroupId\b' \
  -g '*.swift' \
  Sumi SumiTests SidebarChrome UI App Settings CommandPalette

guard_expect_no_matches \
  'canonical durable split model regained window-local or parallel identity state' \
  '\b(activeTabId|tabIds|host)[[:space:]]*:' \
  -g '*.swift' Packages/SumiDomain/Sources/SumiDomain/Split

guard_expect_no_matches \
  'window split projection stores or reaches back through browser mechanisms' \
  '\b(Tab|WKWebView|BrowserManager|TabManager)\b' \
  -g '*.swift' \
  Sumi/Models/Window/WindowSplitPresentation.swift \
  Sumi/Managers/SplitRuntime/WindowSplitProjection.swift

guard_finish 'split architecture boundary'
