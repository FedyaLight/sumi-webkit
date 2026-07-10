#!/usr/bin/env bash
# Architecture hub metrics freeze (plan A0).
# Caps are hard ceilings — god-hub debt must not grow during the 72→100 program.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  printf 'error: ripgrep (rg) is required for architecture hub metrics\n' >&2
  exit 1
fi

failures=0

count_lines() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return
  fi
  wc -l < "$file" | tr -d ' '
}

count_matches() {
  local pattern="$1"
  shift
  local total=0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    total=$((total + ${line##*:}))
  done < <(rg --count-matches "$pattern" -g "*.swift" "$@" 2>/dev/null || true)
  printf '%s\n' "$total"
}

check_max() {
  local label="$1"
  local actual="$2"
  local max="$3"
  printf '%-52s %5d / %5d\n' "$label" "$actual" "$max"
  if (( actual > max )); then
    printf 'error: %s above hub-metrics freeze (%d > %d)\n' "$label" "$actual" "$max" >&2
    failures=$((failures + 1))
  fi
}

# Peer Owners on roots: lazy var *Owner in the façade files themselves.
bm_loc="$(count_lines Sumi/Managers/BrowserManager/BrowserManager.swift)"
tm_loc="$(count_lines Sumi/Managers/TabManager/TabManager.swift)"
bm_peer_owners="$(
  rg --count-matches 'lazy var \w+Owner\b' \
    Sumi/Managers/BrowserManager/BrowserManager.swift 2>/dev/null || true
)"
bm_peer_owners="${bm_peer_owners:-0}"
tm_peer_owners="$(
  rg --count-matches 'lazy var \w+Owner\b' \
    Sumi/Managers/TabManager/TabManager.swift 2>/dev/null || true
)"
tm_peer_owners="${tm_peer_owners:-0}"

live_bm="$(
  count_matches 'static\s+func\s+live\s*\(\s*browserManager' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"
live_tm="$(
  count_matches 'static\s+func\s+live\s*\(\s*tabManager' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"
legacy_runtime_context_handlers="$(
  count_matches \
    '\b(visibleWebViewPreparationRuntime|cleanupScopeRuntime|hiddenCloneEvictionRuntime|deferredProtectedCommandRuntime|trackedCleanupExecutionRuntime|webViewShutdownRuntime)\s*\(' \
    App FloatingBar SidebarChrome Settings Sumi UI
)"

# Folder collision: chrome must not live under Navigation/ (DDG product name).
if [[ -d Navigation ]] && [[ ! -L Navigation ]]; then
  printf 'error: repo folder Navigation/ must be renamed to SidebarChrome/ (DDG product collision)\n' >&2
  failures=$((failures + 1))
fi

printf '%s\n' 'Architecture hub metrics freeze'
printf '%s\n' '--------------------------------'
check_max "BrowserManager.swift LOC" "$bm_loc" 200
check_max "TabManager.swift LOC" "$tm_loc" 220
check_max "BrowserManager peer lazy *Owner" "$bm_peer_owners" 0
check_max "TabManager peer lazy *Owner" "$tm_peer_owners" 5
check_max "static func live(browserManager:)" "$live_bm" 40
check_max "static func live(tabManager:)" "$live_tm" 40
# W1: direct closure-runtime factories were replaced by typed attached contexts.
check_max "Legacy runtime-context handlers" "$legacy_runtime_context_handlers" 0

if (( failures > 0 )); then
  exit 1
fi

printf '\narchitecture hub metrics freeze passed\n'
