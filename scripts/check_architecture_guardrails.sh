#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

checks=(
  "scripts/check_ddg_vendor_test_boundary.sh"
  "scripts/check_prepared_bundle_runtime_boundary.sh"
  "scripts/check_safari_extension_clean_import.sh"
  "scripts/check_tracker_radar_import_boundary.sh"
  "scripts/check_userscript_hot_paths.sh"
)

for check in "${checks[@]}"; do
  echo "==> ${check}"
  "${check}"
done

echo "architecture guardrails passed"
