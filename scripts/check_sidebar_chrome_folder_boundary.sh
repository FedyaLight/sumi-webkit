#!/usr/bin/env bash
# Ensures Sumi sidebar chrome lives under SidebarChrome/, not Navigation/
# (Navigation is the DDG BrowserServicesKit SPM product name).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

guard_require_directory SidebarChrome/Sidebar
guard_expect_absent_path \
  'SpacesSideBarView under the retired Navigation path' \
  Navigation/Sidebar/SpacesSideBarView.swift

# Stale path references in tracked sources (exclude this script, Vendor, docs, baselines).
guard_expect_no_matches \
  'Navigation/Sidebar references outside Vendor/docs' \
  'Navigation/Sidebar' \
  --glob '*.swift' --glob '*.yml' --glob '*.md' --glob '*.pbxproj' --glob '*.sh' \
  --glob '!Vendor/**' \
  --glob '!docs/**' \
  --glob '!.swiftlint-baseline.json' \
  --glob '!scripts/check_sidebar_chrome_folder_boundary.sh' \
  --glob '!scripts/sync_ddg_vendor_snapshot.sh' \
  --glob '!scripts/check_ddg_vendor_test_boundary.sh' \
  .
guard_finish 'sidebar chrome folder boundary'
