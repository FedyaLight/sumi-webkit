#!/usr/bin/env bash
# Regular-tab lifecycle is split by structural, admission, runtime and creation
# transaction boundaries. It must not collapse back into a callback bag.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

collection='Sumi/Managers/TabManager/RegularTabCollectionOwner.swift'
structure='Sumi/Managers/TabManager/RegularTabStructuralTransaction.swift'
admission='Sumi/Managers/TabManager/RegularTabPlacementAdmission.swift'
placement='Sumi/Managers/TabManager/RegularTabPlacementTransaction.swift'
prepared='Sumi/Managers/TabManager/PreparedRegularTabPlacement.swift'
residence='Sumi/Managers/TabManager/RegularTabResidencePublication.swift'
visible_runtime='Sumi/Managers/TabManager/RegularTabVisibleRuntimeEffects.swift'
publication='Sumi/Managers/TabManager/RegularTabPublicationTransaction.swift'
glance_committer='Sumi/Managers/TabManager/GlanceTabAdoptionCommitter.swift'
glance_transaction='Sumi/Managers/TabManager/GlanceTabAdoptionTransaction.swift'
creation_candidates='Sumi/Managers/TabManager/RegularTabCreationCandidateFactory.swift'
creation_transaction='Sumi/Managers/TabManager/RegularTabCreationTransaction.swift'
creation_service='Sumi/Managers/TabManager/RegularTabCreationService.swift'
sources=(
  "$collection"
  "$structure"
  "$admission"
  "$placement"
  "$prepared"
  "$residence"
  "$visible_runtime"
  "$publication"
  "$glance_committer"
  "$glance_transaction"
  "$creation_candidates"
  "$creation_transaction"
  "$creation_service"
)

for file in "${sources[@]}"; do
  guard_require_file "$file"
done

guard_expect_no_matches \
  'regular lifecycle defines no replacement dependency bag' \
  '\bstruct[[:space:]]+(Dependencies|Capabilities|Actions|OwnerBag)\b' \
  "${sources[@]}"
guard_expect_no_matches \
  'regular lifecycle stores no callback dependencies' \
  '^[[:space:]]*private[[:space:]]+(let|var)[[:space:]].*->[[:space:]]*' \
  "${sources[@]}"
guard_expect_no_matches \
  'regular lifecycle defines no forwarding protocol surface' \
  '^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|internal[[:space:]]+)?protocol[[:space:]]' \
  "${sources[@]}"
guard_expect_no_matches \
  'regular lifecycle cannot recover a manager root' \
  '\b(browserManager|tabManager)\b|:[[:space:]]*(BrowserManager|TabManager)[?!]?' \
  "${sources[@]}"

declare -a type_limits=(
  'RegularTabCollectionOwner|5'
  'RegularTabStructuralTransaction|3'
  'RegularTabPlacementAdmission|3'
  'RegularTabPlacementTransaction|4'
  'RegularTabResidencePublication|3'
  'RegularTabVisibleRuntimeEffects|3'
  'RegularTabPublicationTransaction|3'
  'GlanceTabAdoptionCommitter|5'
  'GlanceTabAdoptionTransaction|4'
  'RegularTabCreationCandidateFactory|3'
  'RegularTabCreationTransaction|4'
  'RegularTabCreationService|4'
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

guard_finish 'regular-tab lifecycle boundary'
