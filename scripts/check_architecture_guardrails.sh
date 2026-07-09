#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

checks=(
  "scripts/check_ddg_vendor_test_boundary.sh"
  "scripts/check_modernization_debt.sh"
  "scripts/check_di_ceremony_debt.sh"
  "scripts/check_domain_isolation_boundary.sh"
  "scripts/check_webruntime_isolation_boundary.sh"
  "scripts/check_import_export_boundaries.sh"
  "scripts/check_prepared_bundle_runtime_boundary.sh"
  "scripts/check_safari_extension_clean_import.sh"
  "scripts/check_settings_browser_manager_boundary.sh"
  "scripts/check_sidebar_browser_manager_boundary.sh"
  "scripts/check_tab_webview_ownership_boundary.sh"
  "scripts/check_startup_persistence_boundary.sh"
  "scripts/check_tracker_radar_import_boundary.sh"
  "scripts/check_updater_sparkle_boundary.sh"
  "scripts/check_userscript_hot_paths.sh"
  "scripts/check_website_compositor_boundaries.sh"
  "scripts/check_webview_runtime_context_boundary.sh"
  "scripts/check_architecture_hub_metrics.sh"
  "scripts/check_no_tab_manager_runtime_context.sh"
  "scripts/check_history_tab_recorder_location.sh"
  "scripts/check_sidebar_chrome_folder_boundary.sh"
  "scripts/check_sidebar_view_coupling.sh"
  "scripts/check_no_exported_domain_webruntime.sh"
  "scripts/check_chrome_package_boundaries.sh"
  "scripts/check_browser_core_package_boundary.sh"
  "scripts/check_test_file_loc.sh"
)

for check in "${checks[@]}"; do
  echo "==> ${check}"
  "${check}"
done

echo "architecture guardrails passed"
