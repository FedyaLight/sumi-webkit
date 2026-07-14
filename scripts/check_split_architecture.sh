#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

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
  SumiTests/SplitGroupCollectionStateOwnerTests.swift
  SumiTests/SplitMembershipResolutionOwnerTests.swift
  SumiTests/SplitEmptyPlaceholderOwnerTests.swift
  SumiTests/SplitPreviewStateOwnerTests.swift
  SumiTests/WindowSplitSelectionReconcilerTests.swift
  SumiTests/SplitGroupTestSupport.swift
  SumiTests/SplitGroupTests.swift
)

for file in "${retired_files[@]}"; do
  if [[ -e "$file" ]]; then
    printf 'error: retired split surface returned: %s\n' "$file" >&2
    status=1
  fi
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
  if [[ ! -f "$file" ]]; then
    printf 'error: canonical split domain component missing: %s\n' "$file" >&2
    status=1
  fi
done

required_runtime_components=(
  Sumi/Managers/TabManager/SplitGroupStore.swift
  Sumi/Managers/TabManager/SplitGroupMutationService.swift
  Sumi/Managers/TabManager/SplitGroupMembershipQuery.swift
  Sumi/Managers/SplitRuntime/WindowSplitProjection.swift
  Sumi/Models/Window/WindowSplitPresentation.swift
  Sumi/Managers/BrowserManager/WindowSplitMaterializationService.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherMoveTransaction.swift
  Sumi/Managers/BrowserManager/ShortcutSplitLauncherCatalogAdapter.swift
  Sumi/Managers/SplitRuntime/WindowSplitQuery.swift
  Sumi/Managers/SplitRuntime/WindowSplitPresentationSynchronizer.swift
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
  if [[ ! -f "$file" ]]; then
    printf 'error: decomposed split runtime component missing: %s\n' "$file" >&2
    status=1
  fi
done

duplicate_domain_declarations="$(
  rg -n '\b(struct|class|enum) (SplitGroup|SplitLayoutTree|SplitMemberID|SplitMember)\b' \
    Sumi SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' || true
)"
fail_matches \
  "split durable model escaped the SumiDomain package" \
  "$duplicate_domain_declarations"

retired_type_hits="$(
  rg -n \
    '\b(SplitGroupMember|SplitGroupHost|SplitGroupCollectionStateOwner|SplitGroupIndexStore|TabManagerSplitGroupRepairOwner|TabSplitGroupStructureOwner|SpaceLauncherProjectionOwner|SplitMembershipResolutionOwner|SplitEmptyPlaceholderOwner|SplitPreviewStateOwner)\b' \
    Sumi SumiTests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' \
    -g '!LegacySplitGroupV1Migration.swift' \
    -g '!SplitGroupArchiveMigrationTests.swift' || true
)"
fail_matches "retired split identity or god surface is still referenced" "$retired_type_hits"

new_split_owner_hits="$(
  rg -n '\b(class|struct|actor) [A-Za-z0-9_]*Split[A-Za-z0-9_]*Owner\b' \
    Sumi SumiTests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' || true
)"
fail_matches \
  "split responsibility was hidden behind a new Owner surface" \
  "$new_split_owner_hits"

retired_split_hub_hits="$(
  rg -n '\b(SplitViewManager|SplitViewRuntime)\b' \
    Sumi SumiTests SumiUITests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' || true
)"
fail_matches \
  "retired split composition hub or runtime callback bag is still referenced in production" \
  "$retired_split_hub_hits"

split_runtime_component_capture_hits="$(
  rg -n '\b(SplitDropCaptureView|SplitDropCaptureViewPolicy|SplitDropCaptureHitPolicy)\b' \
    Sumi/Managers/SplitRuntime \
    -g '*.swift' || true
)"
fail_matches \
  "split runtime depends on component-only drop capture behavior" \
  "$split_runtime_component_capture_hits"

split_runtime_ui_framework_hits="$(
  rg -n '^import (AppKit|SwiftUI|WebKit)$' \
    Sumi/Managers/SplitRuntime \
    -g '*.swift' || true
)"
fail_matches \
  "split runtime imported a UI or browser framework" \
  "$split_runtime_ui_framework_hits"

split_composition_escape_hits="$(
  rg -n '\bBrowserSplitServices\b' \
    Sumi SumiTests SumiUITests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' \
    -g '!BrowserSplitServices.swift' \
    -g '!BrowserManager.swift' || true
)"
fail_matches \
  "composition-only split storage escaped into feature code" \
  "$split_composition_escape_hits"

# Access to the graph itself is limited to explicit construction edges. Each
# allowed file must immediately inject one concrete field into feature code.
split_composition_access_hits="$(
  rg -n '\bsplitComposition\b' \
    Sumi SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' \
    -g '!BrowserManager.swift' \
    -g '!BrowserWindowViewContextComposition.swift' \
    -g '!BrowserTabManagerRuntimePortsFactory.swift' \
    -g '!BrowserTabRuntimeCompositionService.swift' \
    -g '!BrowserManager+WebViewRuntimeComposition.swift' \
    -g '!BrowserKeyboardShortcutCommandOwner.swift' \
    -g '!BrowserGlanceRuntimeService.swift' \
    -g '!BrowserURLBarBundle+Live.swift' \
    -g '!SplitShortcutServices+Live.swift' \
    -g '!SidebarBrowserContext.swift' \
    -g '!BrowserAppOrchestrationOwner.swift' || true
)"
fail_matches \
  "split composition graph was accessed outside an approved construction edge" \
  "$split_composition_access_hits"

split_composition_behavior_hits="$(
  rg -n '^    ((private|fileprivate|internal|public)[[:space:]]+)?(mutating[[:space:]]+)?(func|var|subscript)\b' \
    Sumi/Managers/BrowserManager/BrowserSplitServices.swift || true
)"
fail_matches \
  "composition-only split storage gained forwarding behavior or mutable state" \
  "$split_composition_behavior_hits"

retired_api_hits="$(
  rg -n -U \
    'SplitGroup\.make\([[:space:]]*tabIds:|\b(maximumTabs|replacingMemberTab|swappingTabs|movingTab)\b|\b(removing|inserting)\(tabId:|\b(splitGroupStructureOwner|splitGroupCollectionStateOwner|splitGroupIndexStore|splitGroupRepairOwner)\b|\b(group|groupId)\(containingMemberId:' \
    Sumi SumiTests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' \
    -g '!LegacySplitGroupV1Migration.swift' \
    -g '!SplitGroupArchiveMigrationTests.swift' || true
)"
fail_matches \
  "retired live-tab split API is still used outside v1 migration" \
  "$retired_api_hits"

retired_window_selection_hits="$(
  rg -n \
    '\b(updateActiveSplitSide|updateActiveSide|activeSplitGroup|activeSplitGroupID)\b' \
    Sumi SumiTests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' || true
)"
fail_matches \
  "retired global split-selection API is still referenced" \
  "$retired_window_selection_hits"

legacy_session_selection_hits="$(
  rg -n '\bactiveSplitGroupId\b' \
    Sumi SumiTests SidebarChrome UI App Settings FloatingBar \
    -g '*.swift' \
    -g '!WindowSessionModels.swift' \
    -g '!WindowSplitSessionCodingTests.swift' || true
)"
fail_matches \
  "decode-only legacy split selection escaped its migration seam" \
  "$legacy_session_selection_hits"

durable_window_state_hits="$(
  rg -n '\b(activeTabId|tabIds|host)[[:space:]]*:' \
    Packages/SumiDomain/Sources/SumiDomain/Split \
    -g '*.swift' || true
)"
fail_matches \
  "canonical durable split model regained window-local or parallel identity state" \
  "$durable_window_state_hits"

presentation_mechanism_hits="$(
  rg -n '\b(Tab|WKWebView|BrowserManager|TabManager)\b' \
    Sumi/Models/Window/WindowSplitPresentation.swift \
    Sumi/Managers/SplitRuntime/WindowSplitProjection.swift \
    -g '*.swift' || true
)"
fail_matches \
  "window split projection stores or reaches back through browser mechanisms" \
  "$presentation_mechanism_hits"

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "split architecture boundary passed"
