#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

ui_paths=(App Sumi SidebarChrome CommandPalette Settings UI)

guard_expect_no_matches \
  'direct BrowserManager SwiftUI environment coupling' \
  '@EnvironmentObject.*BrowserManager|@Environment\([^)]*BrowserManager|\.environmentObject[[:space:]]*\([[:space:]]*browserManager[[:space:]]*\)|\.environment[[:space:]]*\([[:space:]]*browserManager[[:space:]]*\)|\.environment[[:space:]]*\([^,)]*,[[:space:]]*browserManager[[:space:]]*\)' \
  -g '*.swift' "${ui_paths[@]}"
guard_finish 'sidebar BrowserManager environment boundary audit'
