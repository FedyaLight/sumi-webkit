#!/usr/bin/env bash
# Sidebar view coupling freeze (architecture plan R3 / W5-R11).
#
# Soft-fails (exit 1) when SpacesSideBarView ObservedObject fan-out grows,
# SpaceSection *View.swift browserContext.tabManager. coupling grows, or any
# single View file under SidebarChrome/ / Sumi/Components/Sidebar/ exceeds the
# LOC ceiling. Caps are hard ceilings — debt must not grow.
#
# W5/R11 interim ceilings (honest ratchet):
# - ObservedObject: 4 (target ≤2; currently 2)
# - View LOC: 600 (target ≤350 for SpacesSideBarView; large chrome still peeling)
# - tabManager dotted refs in SpaceSection *View.swift: 4 (target 0)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for sidebar view coupling guardrail\n' >&2
  exit 1
fi

# Freeze baselines tightened 2026-07-09 (W5/R11).
MAX_SPACES_SIDEBAR_OBSERVED_OBJECTS=4
MAX_SPACE_SECTION_TAB_MANAGER_COUPLING=4
MAX_SIDEBAR_VIEW_LOC=600

SPACES_SIDEBAR_VIEW="SidebarChrome/Sidebar/SpacesSideBarView.swift"
SIDEBAR_TREES=(
  "SidebarChrome"
  "Sumi/Components/Sidebar"
)
SPACE_SECTION_DIR="Sumi/Components/Sidebar/SpaceSection"

failures=0

count_matches_in_file() {
  local pattern="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return
  fi
  local count
  count="$(rg --count-matches "$pattern" "$file" 2>/dev/null || true)"
  printf '%s\n' "${count:-0}"
}

count_matches_in_glob() {
  local pattern="$1"
  local dir="$2"
  local glob="$3"
  local total=0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    total=$((total + ${line##*:}))
  done < <(rg --count-matches "$pattern" -g "$glob" "$dir" 2>/dev/null || true)
  printf '%s\n' "$total"
}

count_lines() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return
  fi
  wc -l < "$file" | tr -d ' '
}

check_max() {
  local label="$1"
  local actual="$2"
  local max="$3"
  printf '%-56s %5d / %5d\n' "$label" "$actual" "$max"
  if (( actual > max )); then
    printf 'error: %s above sidebar coupling freeze (%d > %d)\n' "$label" "$actual" "$max" >&2
    failures=$((failures + 1))
  fi
}

observed_objects="$(
  count_matches_in_file '@ObservedObject' "$SPACES_SIDEBAR_VIEW"
)"
tab_manager_coupling="$(
  count_matches_in_glob 'browserContext\.tabManager\.' "$SPACE_SECTION_DIR" '*View.swift'
)"

shortcut_split_row_manager_hits="$(
  rg -n '\bTabManager\b|browserContext\.tabManager' \
    "$SPACE_SECTION_DIR/ShortcutHostedSplitGroupRow.swift" || true
)"
if [[ -n "$shortcut_split_row_manager_hits" ]]; then
  printf 'error: shortcut-hosted split row regained TabManager coupling:\n%s\n' \
    "$shortcut_split_row_manager_hits" >&2
  failures=$((failures + 1))
fi

printf '%s\n' 'Sidebar view coupling freeze'
printf '%s\n' '----------------------------'
check_max "SpacesSideBarView @ObservedObject" "$observed_objects" "$MAX_SPACES_SIDEBAR_OBSERVED_OBJECTS"
check_max "SpaceSection *View browserContext.tabManager." "$tab_manager_coupling" "$MAX_SPACE_SECTION_TAB_MANAGER_COUPLING"

oversized=0
while IFS= read -r -d '' file; do
  loc="$(count_lines "$file")"
  if (( loc > MAX_SIDEBAR_VIEW_LOC )); then
    printf 'error: %s exceeds sidebar View LOC freeze (%d > %d)\n' "$file" "$loc" "$MAX_SIDEBAR_VIEW_LOC" >&2
    oversized=$((oversized + 1))
    failures=$((failures + 1))
  fi
done < <(
  find "${SIDEBAR_TREES[@]}" -type f -name '*View.swift' -print0 2>/dev/null
)

printf '%-56s %5d / %5d\n' "sidebar *View.swift files over ${MAX_SIDEBAR_VIEW_LOC} LOC" "$oversized" 0

if (( failures > 0 )); then
  exit 1
fi

echo "sidebar view coupling freeze passed"
