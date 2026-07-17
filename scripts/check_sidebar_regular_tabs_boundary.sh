#!/usr/bin/env bash
# Regular-tab sidebar views receive exact read, target-query and command roles.
# A forwarding facade must not recombine them.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

retired_controller='Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabsController.swift'
composition='Sumi/Managers/BrowserManager/BrowserManager+SidebarRegularTabsComposition.swift'
root_composition='Sumi/BrowserRuntime/BrowserCompositionRoot+TabSession.swift'
production_roots=(App Sumi Settings SidebarChrome FloatingBar UI)
role_budgets=(
  'SidebarRegularTabCatalog|Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabCatalog.swift|3'
  'SidebarRegularTabTargetQuery|Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabTargetQuery.swift|5'
  'SidebarRegularTabLifecycleCommands|Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabLifecycleCommands.swift|1'
  'SidebarRegularTabShortcutCommands|Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabShortcutCommands.swift|2'
  'SidebarRegularTabPlacementCommands|Sumi/Components/Sidebar/SpaceSection/SidebarRegularTabPlacementCommands.swift|3'
)
role_files=()
for role_budget in "${role_budgets[@]}"; do
  IFS='|' read -r _ file _ <<< "$role_budget"
  role_files+=("$file")
done

guard_require_file "$composition"
guard_require_file "$root_composition"
for file in "${role_files[@]}"; do
  guard_require_file "$file"
done
if [[ -e "$retired_controller" ]]; then
  guard_record_failure "retired regular-tabs aggregate file returned: $retired_controller"
fi

guard_expect_no_matches \
  'retired regular-tabs protocol remains absent' \
  '\bSidebarRegularTabsControlling\b' \
  "${production_roots[@]}" SumiTests -g '*.swift'
guard_expect_no_matches \
  'regular-tabs Dependencies mirror remains absent' \
  '\bSidebarRegularTabsController\.Dependencies\b|\bstruct[[:space:]]+Dependencies\b' \
  "${role_files[@]}" "$composition"
guard_expect_no_matches \
  'regular-tabs roles store no callbacks' \
  '^[[:space:]]*private[[:space:]]+let[[:space:]].*->[[:space:]]*' \
  "${role_files[@]}"
guard_expect_no_matches \
  'regular-tabs roles cannot recover a manager root' \
  '\bBrowserManager\b|\bTabManager\b|\bbrowserManager\b|\btabManager\b' \
  "${role_files[@]}"

guard_expect_no_matches \
  'retired regular-tabs forwarding facade remains absent' \
  '\bSidebarRegularTabsController\b' \
  "${production_roots[@]}" -g '*.swift'

for role_budget in "${role_budgets[@]}"; do
  IFS='|' read -r type file maximum <<< "$role_budget"
  count="$(
    guard_count_matches "^(final[[:space:]]+class|struct)[[:space:]]+${type}\b" \
      "$file"
  )"
  guard_exact "one concrete ${type}" "$count" 1
  top_level_count="$(
    guard_count_matches '^(final[[:space:]]+class|class|struct|enum|actor|protocol)[[:space:]]+' \
      "$file"
  )"
  guard_exact "${type} file owns one top-level role" "$top_level_count" 1
  collaborator_count="$(
    guard_count_matches \
      '^[[:space:]]*private[[:space:]]+(let|weak[[:space:]]+var)[[:space:]]+' \
      "$file"
  )"
  guard_max "${type} collaborators" "$collaborator_count" "$maximum"
done

for construction in \
  SidebarRegularTabCatalog \
  SidebarRegularTabTargetQuery; do
  count="$(
    guard_count_matches \
      "^[[:space:]]*([[:alnum:]_]+:[[:space:]]*)?${construction}\\(" \
      "$composition"
  )"
  guard_exact "composition constructs ${construction}" "$count" 1
done

for construction in \
  SidebarRegularTabLifecycleCommands \
  SidebarRegularTabShortcutCommands \
  SidebarRegularTabPlacementCommands; do
  count="$(
    guard_count_matches \
      "^[[:space:]]*([[:alnum:]_]+:[[:space:]]*)?${construction}\\(" \
      "$root_composition"
  )"
  guard_exact "composition constructs ${construction}" "$count" 1
done

guard_finish 'sidebar regular-tabs boundary'
