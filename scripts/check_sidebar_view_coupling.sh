#!/usr/bin/env bash
# Sidebar view coupling freeze (architecture plan R3 / W5-R11).
#
# Soft-fails (exit 1) when SpacesSideBarView ObservedObject fan-out grows,
# any sidebar UI source regains TabManager coupling, or any single View file
# under SidebarChrome/ / Sumi/Components/Sidebar/ exceeds the LOC ceiling.
# Caps are hard ceilings — debt must not grow.
#
# W5/R11 interim ceilings (honest ratchet):
# - ObservedObject: 4 (target ≤2; currently 2)
# - View LOC: 600 (target ≤350 for SpacesSideBarView; large chrome still peeling)
# - TabManager type/reach-through in sidebar UI roots: 0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for sidebar view coupling guardrail\n' >&2
  exit 1
fi

# Freeze baselines tightened 2026-07-09 (W5/R11).
MAX_SPACES_SIDEBAR_OBSERVED_OBJECTS=4
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
tab_manager_coupling_hits="$(
  rg -n --glob '*.swift' \
    '\bTabManager\b|browserContext\.tabManager\b|windowState\.tabManager\b' \
    "${SIDEBAR_TAB_MANAGER_FREE_TREES[@]}" || true
)"
tab_manager_coupling_count=0
if [[ -n "$tab_manager_coupling_hits" ]]; then
  tab_manager_coupling_count="$(printf '%s\n' "$tab_manager_coupling_hits" | wc -l | tr -d ' ')"
  printf 'error: sidebar UI roots regained TabManager coupling:\n%s\n' \
    "$tab_manager_coupling_hits" >&2
  failures=$((failures + 1))
fi

printf '%s\n' 'Sidebar view coupling freeze'
printf '%s\n' '----------------------------'
check_max "SpacesSideBarView @ObservedObject" "$observed_objects" "$MAX_SPACES_SIDEBAR_OBSERVED_OBJECTS"
printf '%-56s %5d / %5d\n' "sidebar UI TabManager coupling matches" \
  "$tab_manager_coupling_count" 0

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
