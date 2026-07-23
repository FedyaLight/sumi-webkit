#!/usr/bin/env bash
# DI ceremony / god-wiring debt baseline.
#
# Caps are hard ceilings. Related boundaries:
# - scripts/check_tab_webview_ownership_boundary.sh
# - scripts/check_domain_isolation_boundary.sh
# - scripts/check_webruntime_isolation_boundary.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

production_roots=(
  "App"
  "CommandPalette"
  "SidebarChrome"
  "Settings"
  "Sumi"
  "UI"
)

count_matches() {
  guard_count_swift_matches "$@"
}

check_max() {
  guard_max "$@"
}

dependencies_structs="$(
  count_matches 'struct\s+Dependencies\b' "${production_roots[@]}"
)"
live_factories="$(
  count_matches 'static\s+func\s+live\b' "${production_roots[@]}"
)"
browser_manager_lazy_owners="$(
  guard_count_matches \
    'lazy var \w+Owner\b' \
    Sumi/Managers/BrowserManager/BrowserManager.swift
)"

printf '%s\n' 'DI ceremony debt baseline guardrail'
printf '%s\n' '-----------------------------------'
check_max "production struct Dependencies" "$dependencies_structs" 40
check_max "production static func live" "$live_factories" 44
check_max "BrowserManager lazy var *Owner" "$browser_manager_lazy_owners" 3

guard_finish 'DI ceremony debt guardrail'
