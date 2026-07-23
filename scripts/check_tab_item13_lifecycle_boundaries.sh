#!/usr/bin/env bash
# Startup restore/reset, transient-extension tabs, last-session merge, and tab
# closure stay split at concrete transaction boundaries without callback bags.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

sources=(
  Sumi/Managers/TabManager/TransientExtensionTabResidenceQuery.swift
  Sumi/Managers/TabManager/TransientExtensionTabURLResolver.swift
  Sumi/Managers/TabManager/TransientExtensionTabInstaller.swift
  Sumi/Managers/TabManager/TransientExtensionTabCreationTransaction.swift
  Sumi/Managers/TabManager/TransientExtensionTabRetirementTransaction.swift
  Sumi/Managers/TabManager/TabStartupStateReset.swift
  Sumi/Managers/TabManager/PreparedTabStartupRuntimeReset.swift
  Sumi/Managers/TabManager/TabStartupRuntimeResetTransaction.swift
  Sumi/Managers/TabManager/TabStartupSplitGroupResetTransaction.swift
  Sumi/Managers/TabManager/TabStartupRegularCollectionResetTransaction.swift
  Sumi/Managers/TabManager/TabStartupTransientStateResetTransaction.swift
  Sumi/Managers/TabManager/TabStoreRestoreService.swift
  Sumi/Managers/TabManager/TabStoreRestoreAttemptExecutor.swift
  Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift
  Sumi/Managers/TabManager/PreparedTabLastSessionMerge.swift
  Sumi/Managers/TabManager/TabLastSessionFolderKey.swift
  Sumi/Managers/TabManager/TabLastSessionRegularTabKey.swift
  Sumi/Managers/TabManager/TabLastSessionLiveStateSnapshotter.swift
  Sumi/Managers/TabManager/TabLastSessionMergePlanningService.swift
  Sumi/Managers/TabManager/TabLastSessionProfileAdmissionTransaction.swift
  Sumi/Managers/TabManager/TabLastSessionSpaceMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionFolderMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionShortcutMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionRegularTabMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionSelectionMaterializer.swift
  Sumi/Managers/TabManager/TabLastSessionMergeCommitTransaction.swift
  Sumi/Managers/TabManager/TabLastSessionMergeSettlement.swift
  Sumi/Managers/TabManager/CommittedRegularTabClosures.swift
  Sumi/Managers/TabManager/RegularTabClosureCommitTransaction.swift
  Sumi/Managers/TabManager/RegularTabClosureSelectionRepair.swift
  Sumi/Managers/TabManager/RegularTabClosureTargetQuery.swift
  Sumi/Managers/TabManager/TabClosureService.swift
  Sumi/Managers/TabManager/TabClosureCandidateRetirement.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabResidenceRemovalTransaction.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabSelectionRestoration.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabRuntimeSettlementTransaction.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabDiscardService.swift
)
extension_composition='Sumi/Managers/BrowserManager/BrowserExtensionTabMutationComposition.swift'
extension_root='Sumi/BrowserRuntime/BrowserCompositionRoot+TabSession.swift'
empty_split_session='Sumi/Managers/SplitRuntime/EmptySplitSession.swift'
empty_split_replacement='Sumi/Managers/SplitRuntime/EmptySplitReplacementService.swift'
command_palette_presentation='Sumi/Services/CommandPalettePresentationService.swift'
transient_role_files=(
  Sumi/Managers/TabManager/TransientExtensionTabResidenceQuery.swift
  Sumi/Managers/TabManager/TransientExtensionTabURLResolver.swift
  Sumi/Managers/TabManager/TransientExtensionTabInstaller.swift
  Sumi/Managers/TabManager/TransientExtensionTabCreationTransaction.swift
  Sumi/Managers/TabManager/TransientExtensionTabRetirementTransaction.swift
)
extension_discard_role_files=(
  Sumi/Managers/BrowserManager/ExtensionRequestedTabResidenceRemovalTransaction.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabSelectionRestoration.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabRuntimeSettlementTransaction.swift
  Sumi/Managers/BrowserManager/ExtensionRequestedTabDiscardService.swift
)

for file in "${sources[@]}"; do
  guard_require_file "$file"
done
guard_require_file "$extension_composition"
guard_require_file "$extension_root"
guard_require_file "$empty_split_session"
guard_require_file "$empty_split_replacement"
guard_require_file "$command_palette_presentation"

guard_expect_no_matches \
  'EmptySplit session regained replacement/drop coupling' \
  '\b(SplitPlaceholderReplacementPreparing|SplitDropService)\b' \
  "$empty_split_session"
guard_expect_no_matches \
  'Command Palette regained a placeholder forwarding protocol/provider' \
  '\b(EmptySplitPlaceholderCancelling|CommandPaletteSplitPlaceholderHandling)\b|splitPlaceholders: @escaping' \
  "$empty_split_session" "$command_palette_presentation"
guard_expect_absent_path \
  'retired transient-extension transaction aggregate' \
  Sumi/Managers/TabManager/TransientExtensionTabTransactions.swift
for role_file in "${transient_role_files[@]}"; do
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
for role_file in "${extension_discard_role_files[@]}"; do
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
guard_exact \
  'ExtensionRequestedTabRemoval stays in its role-exact file' \
  "$(
    guard_count_matches \
      '^enum[[:space:]]+ExtensionRequestedTabRemoval\b' \
      Sumi/Managers/BrowserManager/ExtensionRequestedTabRemoval.swift
  )" \
  1

guard_expect_no_matches \
  'item 13 lifecycle defines no replacement dependency bag' \
  '\bstruct[[:space:]]+(Dependencies|Capabilities|Actions|OwnerBag)\b' \
  "${sources[@]}"
guard_expect_no_matches \
  'item 13 lifecycle stores no callback dependencies' \
  '^[[:space:]]*private[[:space:]]+(let|var)[[:space:]].*->[[:space:]]*' \
  "${sources[@]}"
guard_expect_no_matches \
  'item 13 lifecycle defines no forwarding protocol surface' \
  '^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|internal[[:space:]]+)?protocol[[:space:]]' \
  "${sources[@]}"
guard_expect_no_matches \
  'item 13 lifecycle cannot recover a manager root' \
  '\b(browserManager|tabManager)\b|:[[:space:]]*(BrowserManager|TabManager)[?!]?' \
  "${sources[@]}"

declare -a last_session_value_roles=(
  PreparedTabLastSessionMerge
  TabLastSessionFolderKey
  TabLastSessionRegularTabKey
)
for role in "${last_session_value_roles[@]}"; do
  role_file="Sumi/Managers/TabManager/${role}.swift"
  guard_require_file "$role_file"
  guard_exact \
    "${role} stays in its role-exact file" \
    "$(guard_count_matches "^struct[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_expect_no_matches \
    "${role} is not repacked into last-session orchestration" \
    "^struct[[:space:]]+${role}\\b" \
    Sumi/Managers/TabManager/TabLastSessionMergeMaterializer.swift
done
guard_expect_no_matches \
  'transient extension umbrella lifecycle stays deleted' \
  '\bTransientExtensionTabLifecycleTransaction\b' \
  App CommandPalette SidebarChrome Settings Sumi UI SumiTests
guard_expect_no_matches \
  'extension discard stores no runtime provider callback' \
  'runtimePorts:|->[[:space:]]*RuntimePortRegistry' \
  Sumi/Managers/BrowserManager/ExtensionRequestedTabDiscardService.swift
guard_expect_no_matches \
  'extension mutation composition does not pull raw selection state' \
  'selectionStateOwner|TabSelectionStateOwner' \
  "$extension_composition"
guard_expect_no_matches \
  'extension mutation composition does not assemble discard internals' \
  'ExtensionRequestedTab(ResidenceRemovalTransaction|RuntimeSettlementTransaction|SelectionRestoration)\(' \
  "$extension_composition"
guard_exact \
  'extension mutation root receives ready discard service' \
  "$(guard_count_matches 'requestedDiscard:[[:space:]]+extensionRequestedTabDiscard' "$extension_root")" \
  1

if [[ -e Sumi/Managers/TabManager/TabClosureService+Live.swift ]]; then
  guard_record_failure \
    'TabClosureService+Live.swift must stay deleted; root composes exact roles'
fi

declare -a type_limits=(
  'TransientExtensionTabResidenceQuery|1'
  'TransientExtensionTabURLResolver|1'
  'TransientExtensionTabInstaller|4'
  'TransientExtensionTabCreationTransaction|4'
  'TransientExtensionTabRetirementTransaction|2'
  'TabStartupRuntimeResetTransaction|4'
  'TabStartupSplitGroupResetTransaction|2'
  'TabStartupRegularCollectionResetTransaction|3'
  'TabStartupTransientStateResetTransaction|2'
  'TabStartupStateReset|5'
  'TabStoreRestoreAttemptExecutor|5'
  'TabStoreRestoreService|4'
  'TabLastSessionLiveStateSnapshotter|4'
  'TabLastSessionMergePlanningService|2'
  'TabLastSessionProfileAdmissionTransaction|1'
  'TabLastSessionSpaceMaterializer|3'
  'TabLastSessionFolderMaterializer|1'
  'TabLastSessionShortcutMaterializer|2'
  'TabLastSessionRegularTabMaterializer|3'
  'TabLastSessionSelectionMaterializer|2'
  'TabLastSessionMergeCommitTransaction|5'
  'TabLastSessionMergeSettlement|2'
  'TabLastSessionMergeMaterializer|5'
  'RegularTabClosureCommitTransaction|5'
  'RegularTabClosureSelectionRepair|4'
  'RegularTabClosureTargetQuery|2'
  'TabClosureService|5'
  'TabClosureCandidateRetirement|4'
  'ExtensionRequestedTabResidenceRemovalTransaction|5'
  'ExtensionRequestedTabSelectionRestoration|2'
  'ExtensionRequestedTabRuntimeSettlementTransaction|3'
  'ExtensionRequestedTabDiscardService|4'
)

count_type_collaborators() {
  local type="$1"
  awk -v type="$type" '
    $0 ~ "^final class " type "[[:space:]]*\\{" {
      inside = 1
      next
    }
    inside && /^final class / { exit }
    inside && /^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]/ {
      count += 1
    }
    END { print count + 0 }
  ' "${sources[@]}"
}

for type_limit in "${type_limits[@]}"; do
  IFS='|' read -r type maximum <<< "$type_limit"
  guard_exact \
    "one concrete ${type}" \
    "$(guard_count_matches "^final[[:space:]]+class[[:space:]]+${type}\\b" "${sources[@]}")" \
    1
  guard_max \
    "${type} collaborators" \
    "$(count_type_collaborators "$type")" \
    "$maximum"
done

guard_finish 'item 13 tab lifecycle boundaries'
