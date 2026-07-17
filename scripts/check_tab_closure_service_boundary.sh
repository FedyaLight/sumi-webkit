#!/usr/bin/env bash
# Tab closing remains an explicit candidate-retirement, durable commit,
# selection-repair, and target-query transaction without a broad live factory.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

service='Sumi/Managers/TabManager/TabClosureService.swift'
retirement='Sumi/Managers/TabManager/TabClosureCandidateRetirement.swift'
cleanup='Sumi/Managers/TabManager/RegularTabClosureRuntimeCleanup.swift'
policy='Sumi/Managers/TabManager/SelectionAfterClosurePolicy.swift'
composition_root='Sumi/BrowserRuntime/BrowserCompositionRoot+TabSession.swift'
role_files=(
  Sumi/Managers/TabManager/CommittedRegularTabClosures.swift
  Sumi/Managers/TabManager/RegularTabClosureCommitTransaction.swift
  Sumi/Managers/TabManager/RegularTabClosureSelectionRepair.swift
  Sumi/Managers/TabManager/RegularTabClosureTargetQuery.swift
  "$service"
)
sources=("${role_files[@]}" "$retirement" "$cleanup" "$policy")

for file in "${sources[@]}" "$composition_root"; do
  guard_require_file "$file"
done

for role_file in "${role_files[@]}"; do
  role="$(basename "$role_file" .swift)"
  guard_exact \
    "$role stays in its role-exact file" \
    "$(guard_count_matches "^(final[[:space:]]+class|struct)[[:space:]]+${role}\\b" "$role_file")" \
    1
  guard_exact \
    "$role file owns one top-level role" \
    "$(guard_count_matches '^(final[[:space:]]+class|struct|enum)[[:space:]]+' "$role_file")" \
    1
done

if [[ -e Sumi/Managers/TabManager/TabRemovalOwner.swift ]]; then
  guard_record_failure 'TabRemovalOwner.swift must stay deleted'
fi
if [[ -e Sumi/Managers/TabManager/TabClosureService+Live.swift ]]; then
  guard_record_failure \
    'TabClosureService+Live.swift must stay deleted; root composes exact roles'
fi

guard_expect_no_matches \
  'tab closure defines no replacement dependency bag' \
  '\bstruct[[:space:]]+(Dependencies|Capabilities|Actions|OwnerBag)\b' \
  "${sources[@]}"
guard_expect_no_matches \
  'tab closure stores no callback dependencies' \
  '^[[:space:]]*private[[:space:]]+(let|var)[[:space:]].*->[[:space:]]*' \
  "${sources[@]}"
guard_expect_no_matches \
  'tab closure defines no forwarding protocol surface' \
  '^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|internal[[:space:]]+)?protocol[[:space:]]' \
  "${sources[@]}"
guard_expect_no_matches \
  'tab closure cannot recover a manager root' \
  '\b(browserManager|tabManager)\b|:[[:space:]]*(BrowserManager|TabManager)[?!]?' \
  "${sources[@]}"
guard_expect_no_matches \
  'retired broad closure factory stays absent' \
  'TabClosureService\.(compose|live)\(' \
  App FloatingBar SidebarChrome Settings Sumi UI

declare -a type_limits=(
  'RegularTabClosureCommitTransaction|5'
  'RegularTabClosureSelectionRepair|4'
  'RegularTabClosureTargetQuery|2'
  'TabClosureService|5'
  'TabClosureCandidateRetirement|4'
  'RegularTabClosureRuntimeCleanup|1'
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

guard_exact \
  'root composes closure commit once' \
  "$(guard_count_matches 'RegularTabClosureCommitTransaction\(' "$composition_root")" \
  1
guard_exact \
  'root composes closure selection repair once' \
  "$(guard_count_matches 'RegularTabClosureSelectionRepair\(' "$composition_root")" \
  1
guard_exact \
  'root composes closure target query once' \
  "$(guard_count_matches 'RegularTabClosureTargetQuery\(' "$composition_root")" \
  1
guard_exact \
  'root composes closure service once' \
  "$(guard_count_matches 'let tabClosureService = TabClosureService\(' "$composition_root")" \
  1

guard_finish 'tab closure service boundary'
