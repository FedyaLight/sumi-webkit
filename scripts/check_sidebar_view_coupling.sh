#!/usr/bin/env bash
# Sidebar view coupling freeze (architecture plan R3 / W5-R11).
#
# Fails when sidebar UI regains TabManager coupling or any single View file
# under SidebarChrome/ / Sumi/Components/Sidebar/ exceeds the LOC ceiling.
# Caps are hard ceilings — debt must not grow.
#
# W5/R11 structural ceilings:
# - View LOC: 600 (target ≤350 for SpacesSideBarView; large chrome still peeling)
# - TabManager type/reach-through in sidebar UI roots: 0
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

MAX_SIDEBAR_VIEW_LOC=600

SPACES_SIDEBAR_VIEW="SidebarChrome/Sidebar/SpacesSideBarView.swift"
SIDEBAR_TREES=(
  "SidebarChrome"
  "Sumi/Components/Sidebar"
)
SIDEBAR_TAB_MANAGER_FREE_TREES=(
  "SidebarChrome/Sidebar"
  "Sumi/Components/Sidebar"
  "Sumi/Components/DragDrop"
)

guard_require_file "$SPACES_SIDEBAR_VIEW"
for tree in "${SIDEBAR_TREES[@]}" "${SIDEBAR_TAB_MANAGER_FREE_TREES[@]}"; do
  guard_require_directory "$tree"
done

tab_manager_coupling_hits="$(
  guard_capture_matches \
    '\bTabManager\b|browserContext\.tabManager\b|windowState\.tabManager\b' \
    --glob '*.swift' "${SIDEBAR_TAB_MANAGER_FREE_TREES[@]}"
)"
tab_manager_coupling_count="$(
  guard_count_swift_matches \
    '\bTabManager\b|browserContext\.tabManager\b|windowState\.tabManager\b' \
    "${SIDEBAR_TAB_MANAGER_FREE_TREES[@]}"
)"
if [[ -n "$tab_manager_coupling_hits" ]]; then
  guard_record_failure \
    "sidebar UI roots regained TabManager coupling: $tab_manager_coupling_hits"
fi

printf '%s\n' 'Sidebar view coupling boundary'
printf '%s\n' '------------------------------'
guard_exact 'sidebar UI TabManager coupling matches' "$tab_manager_coupling_count" 0

oversized=0
sidebar_view_files="$(
  find "${SIDEBAR_TREES[@]}" -type f -name '*View.swift' -print
)"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  loc="$(guard_count_lines "$file")"
  if (( loc > MAX_SIDEBAR_VIEW_LOC )); then
    guard_record_failure \
      "$file exceeds sidebar View LOC freeze ($loc > $MAX_SIDEBAR_VIEW_LOC)"
    oversized=$((oversized + 1))
  fi
done <<< "$sidebar_view_files"

guard_exact \
  "sidebar *View.swift files over ${MAX_SIDEBAR_VIEW_LOC} LOC" \
  "$oversized" \
  0

guard_finish 'sidebar view coupling boundary'
