#!/usr/bin/env bash
# DI ceremony / god-wiring debt baseline.
#
# Caps ratchet downward as Phases 4–5 collapse thin Owners and capability bags.
# Trajectory (Dependencies): 147 → 144 → 139 → 104 → 84 → ~70 → 51 (target → 40)
# Trajectory (live factories): 170 → 167 → 162 → 130 → 110 → ~100 → 59 (target → 50)
# Trajectory (BM lazy *Owner): 35 → 34 → 28 → 17 → 10 → 8 → 7 → 6 → 3 (target → ≤3)
#
# Tab WebView accessors outside Models/Tab + WebViewCoordinator remain forbidden
# by scripts/check_tab_webview_ownership_boundary.sh (Phase 6B session-first writers).
# Domain Foundation-only files: scripts/check_domain_isolation_boundary.sh
# Module-split roadmap: docs/architecture-module-split.md
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for DI ceremony debt guardrail\n' >&2
  exit 1
fi

production_roots=(
  "App"
  "FloatingBar"
  "Navigation"
  "Settings"
  "Sumi"
  "UI"
)

failures=0

count_matches() {
  local pattern="$1"
  shift

  local total=0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    total=$((total + ${line##*:}))
  done < <(rg --count-matches "$pattern" -g "*.swift" "$@" || true)

  printf '%s\n' "$total"
}

check_max() {
  local label="$1"
  local actual="$2"
  local max="$3"

  printf '%-46s %4d / %4d\n' "$label" "$actual" "$max"
  if (( actual > max )); then
    printf 'error: %s increased above DI ceremony baseline (%d > %d)\n' "$label" "$actual" "$max" >&2
    failures=$((failures + 1))
  fi
}

dependencies_structs="$(
  count_matches 'struct\s+Dependencies\b' "${production_roots[@]}"
)"
live_factories="$(
  count_matches 'static\s+func\s+live\b' "${production_roots[@]}"
)"
browser_manager_lazy_owners="$(
  rg --count-matches 'lazy var \w+Owner\b' \
    Sumi/Managers/BrowserManager/BrowserManager.swift 2>/dev/null || true
)"
browser_manager_lazy_owners="${browser_manager_lazy_owners:-0}"

printf '%s\n' 'DI ceremony debt baseline guardrail'
printf '%s\n' '-----------------------------------'
# Phase 0 baseline. Lower after each DI-collapse / capability-bag PR.
# V3: WVC/EM thin + factory live→make. Caps ratcheted to actual; BM owners stay ≤3.
check_max "production struct Dependencies" "$dependencies_structs" 51
check_max "production static func live" "$live_factories" 59
# Phase 5A / N2 / T3 / T6–T8: thin Owners folded into Privacy / URLBar / WindowSession / Chrome / History / Bookmark / Profile / Extension bags; remaining BM lazy Owners are boot/shutdown/keyboard only.
check_max "BrowserManager lazy var *Owner" "$browser_manager_lazy_owners" 3

if (( failures > 0 )); then
  exit 1
fi

printf '\nDI ceremony debt guardrail passed\n'
