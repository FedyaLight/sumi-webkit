#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

sources=(
  Sumi/Managers/TabManager/ShortcutPinMovePreparer.swift
  Sumi/Managers/TabManager/ShortcutPinMoveTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinReorderTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinPlacementCommandService.swift
  Sumi/Managers/TabManager/RegularTabShortcutConversionCommand.swift
  Sumi/Managers/TabManager/RegularTabEssentialPinningService.swift
  Sumi/Managers/TabManager/ShortcutPinEssentialCopyPreparer.swift
  Sumi/Managers/TabManager/ShortcutPinEssentialCopyTransaction.swift
  Sumi/Managers/TabManager/EssentialShortcutSpaceRebinder.swift
  Sumi/Managers/TabManager/ShortcutPinSpacePinningTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinRetirementCommitter.swift
  Sumi/Managers/TabManager/ShortcutPinRetirementTransaction.swift
  Sumi/Managers/TabManager/ShortcutLivePagePreservationTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinLivePageMutationService.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationPlan.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationPlanner.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceStructureMutation.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceTopologyMutation.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationApplicator.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceRetirementService.swift
  Sumi/Managers/TabManager/ShortcutSplitLauncherBindingStaging.swift
  Sumi/Managers/TabManager/ShortcutSplitLauncherBindingBatchStaging.swift
  Sumi/Managers/TabManager/ShortcutTabPromotionSourcePlanner.swift
  Sumi/Managers/TabManager/ShortcutTabPromotionPlanner.swift
  Sumi/Managers/TabManager/PreparedDisplayedTabShortcutBinding.swift
  Sumi/Managers/TabManager/DisplayedTabShortcutSourceModelTransaction.swift
  Sumi/Managers/TabManager/DisplayedTabShortcutRuntimeTransaction.swift
  Sumi/Managers/TabManager/ShortcutLiveRuntimeRetirementPublication.swift
  Sumi/Managers/TabManager/DetachedTabShortcutSourcePreparer.swift
  Sumi/Managers/TabManager/PreparedDetachedTabShortcutTransition.swift
  Sumi/Managers/TabManager/DetachedTabShortcutConverter.swift
  Sumi/Managers/TabManager/ShortcutPinPlacementResolver.swift
  Sumi/Managers/TabManager/ShortcutPinCatalogMutationTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinMetadataCommitTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinMetadataMutationService.swift
)
physical_role_files=(
  Sumi/Managers/TabManager/ShortcutPinMovePreparer.swift
  Sumi/Managers/TabManager/ShortcutPinMoveTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinReorderTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinPlacementCommandService.swift
  Sumi/Managers/TabManager/RegularTabShortcutConversionCommand.swift
  Sumi/Managers/TabManager/RegularTabEssentialPinningService.swift
  Sumi/Managers/TabManager/ShortcutPinEssentialCopyPreparer.swift
  Sumi/Managers/TabManager/ShortcutPinEssentialCopyTransaction.swift
  Sumi/Managers/TabManager/EssentialShortcutSpaceRebinder.swift
  Sumi/Managers/TabManager/ShortcutPinSpacePinningTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinRetirementCommitter.swift
  Sumi/Managers/TabManager/ShortcutPinRetirementTransaction.swift
  Sumi/Managers/TabManager/ShortcutLivePagePreservationTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinLivePageMutationService.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationPlan.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationPlanner.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceStructureMutation.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceTopologyMutation.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutationApplicator.swift
  Sumi/Managers/TabManager/ShortcutProfileReferenceRetirementService.swift
  Sumi/Managers/TabManager/ShortcutTabPromotionSourcePlanner.swift
  Sumi/Managers/TabManager/ShortcutTabPromotionPlanner.swift
  Sumi/Managers/TabManager/DisplayedTabShortcutSourceModelTransaction.swift
  Sumi/Managers/TabManager/DisplayedTabShortcutRuntimeTransaction.swift
  Sumi/Managers/TabManager/DetachedTabShortcutSourcePreparer.swift
  Sumi/Managers/TabManager/PreparedDetachedTabShortcutTransition.swift
  Sumi/Managers/TabManager/DetachedTabShortcutConverter.swift
  Sumi/Managers/TabManager/ShortcutPinPlacementResolver.swift
  Sumi/Managers/TabManager/ShortcutPinCatalogMutationTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinMetadataCommitTransaction.swift
  Sumi/Managers/TabManager/ShortcutPinMetadataMutationService.swift
)

for file in "${sources[@]}"; do
  guard_require_file "$file"
done

for role_file in "${physical_role_files[@]}"; do
  role="$(basename "$role_file" .swift)"
  guard_exact \
    "$role stays in its role-exact file" \
    "$(guard_count_matches "^(final[[:space:]]+class|struct|enum)[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_exact \
    "$role file owns one top-level role" \
    "$(guard_count_matches '^(final[[:space:]]+class|struct|enum)[[:space:]]+' "$role_file")" \
    1
done

for retired_aggregate in \
  Sumi/Managers/TabManager/ShortcutPinCommandTransactions.swift \
  Sumi/Managers/TabManager/ShortcutPinStoreTransactions.swift \
  Sumi/Managers/TabManager/ShortcutProfileReferenceMutation.swift; do
  guard_expect_absent_path \
    "retired shortcut transaction aggregate $retired_aggregate" \
    "$retired_aggregate"
done

guard_expect_no_matches \
  'shortcut transaction roles store no callback dependencies' \
  '^[[:space:]]*private[[:space:]]+(let|var)[[:space:]].*->[[:space:]]*' \
  "${sources[@]}"
guard_expect_no_matches \
  'shortcut transaction roles define no replacement dependency bag' \
  '\bstruct[[:space:]]+(Dependencies|Capabilities|Actions|OwnerBag)\b' \
  "${sources[@]}"
guard_expect_no_matches \
  'retired shortcut command facades stay absent' \
  '\b(ShortcutPinCommandOwner|ShortcutPinConversionCommandService)\b' \
  App Sumi Settings SidebarChrome CommandPalette UI -g '*.swift'

sidebar_execution_commands=Sumi/Components/Sidebar/SidebarPinExecutionCommands.swift
sidebar_placement_commands=Sumi/Components/Sidebar/SidebarPinPlacementCommands.swift
guard_require_file "$sidebar_execution_commands"
guard_require_file "$sidebar_placement_commands"
guard_exact \
  'sidebar pin execution revalidates exact pin identity' \
  "$(guard_count_matches 'current[[:space:]]*===[[:space:]]*pin' "$sidebar_execution_commands")" \
  1
guard_exact \
  'sidebar pin placement revalidates exact pin identity' \
  "$(guard_count_matches 'current[[:space:]]*===[[:space:]]*pin' "$sidebar_placement_commands")" \
  1

declare -a type_limits=(
  'ShortcutPinMovePreparer|4'
  'ShortcutPinMoveTransaction|5'
  'ShortcutPinReorderTransaction|4'
  'ShortcutPinPlacementCommandService|2'
  'RegularTabShortcutConversionCommand|3'
  'RegularTabEssentialPinningService|4'
  'ShortcutPinEssentialCopyPreparer|3'
  'ShortcutPinEssentialCopyTransaction|4'
  'EssentialShortcutSpaceRebinder|4'
  'ShortcutPinSpacePinningTransaction|5'
  'ShortcutPinRetirementCommitter|4'
  'ShortcutPinRetirementTransaction|3'
  'ShortcutLivePagePreservationTransaction|4'
  'ShortcutPinLivePageMutationService|4'
  'ShortcutProfileReferenceStructureMutation|3'
  'ShortcutProfileReferenceTopologyMutation|2'
  'ShortcutProfileReferenceMutationApplicator|4'
  'ShortcutProfileReferenceRetirementService|5'
  'ShortcutSplitLauncherBindingStaging|3'
  'ShortcutSplitLauncherBindingBatchStaging|3'
  'ShortcutTabPromotionSourcePlanner|3'
  'ShortcutTabPromotionPlanner|4'
  'DisplayedTabShortcutBindingPreflight|4'
  'DisplayedTabShortcutSourceModelTransaction|5'
  'DisplayedTabShortcutRuntimeTransaction|3'
  'ShortcutLiveRuntimeRetirementPublication|4'
  'DetachedTabShortcutSourcePreparer|5'
  'DetachedTabShortcutConverter|3'
  'ShortcutPinPlacementResolver|3'
  'ShortcutPinCatalogMutationTransaction|4'
  'ShortcutPinMetadataCommitTransaction|4'
  'ShortcutPinMetadataMutationService|5'
)

count_type_collaborators() {
  local type="$1"
  awk -v type="$type" '
    $0 ~ "^final class " type "[[:space:]]*\\{" {
      inside = 1
      depth = 1
      next
    }
    inside && /^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]/ {
      count += 1
    }
    inside {
      opens = gsub(/\{/, "{")
      closes = gsub(/\}/, "}")
      depth += opens - closes
      if (depth == 0) { inside = 0 }
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

guard_finish 'shortcut transaction boundaries'
