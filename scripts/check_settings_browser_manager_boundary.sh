#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

settings_root="Sumi/Components/Settings"
guard_require_directory "$settings_root"

guard_expect_no_matches \
  'Settings UI BrowserManager coupling' \
  '\bBrowserManager\b|\bbrowserManager\b' \
  -g '*.swift' "$settings_root"
guard_finish 'settings BrowserManager boundary audit'
