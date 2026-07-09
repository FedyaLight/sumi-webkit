#!/usr/bin/env bash
# Ensures Sumi sidebar chrome lives under SidebarChrome/, not Navigation/
# (Navigation is the DDG BrowserServicesKit SPM product name).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failures=0

if [[ ! -d SidebarChrome/Sidebar ]]; then
  printf 'error: expected SidebarChrome/Sidebar/ after Navigation rename\n' >&2
  failures=$((failures + 1))
fi

if [[ -f Navigation/Sidebar/SpacesSideBarView.swift ]]; then
  printf 'error: SpacesSideBarView still under Navigation/ — move to SidebarChrome/\n' >&2
  failures=$((failures + 1))
fi

# Stale path references in tracked sources (exclude this script, Vendor, docs, baselines).
stale="$(
  rg -n --glob '*.swift' --glob '*.yml' --glob '*.md' --glob '*.pbxproj' --glob '*.sh' \
    --glob '!Vendor/**' \
    --glob '!docs/**' \
    --glob '!.swiftlint-baseline.json' \
    --glob '!scripts/check_sidebar_chrome_folder_boundary.sh' \
    --glob '!scripts/sync_ddg_vendor_snapshot.sh' \
    --glob '!scripts/check_ddg_vendor_test_boundary.sh' \
    -e 'Navigation/Sidebar' . 2>/dev/null || true
)"

if [[ -n "$stale" ]]; then
  printf 'error: references to Navigation/Sidebar remain outside Vendor/docs:\n%s\n' "$stale" >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  exit 1
fi

echo "sidebar chrome folder boundary passed"
