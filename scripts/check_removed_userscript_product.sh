#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

removed_path="Sumi/Managers/SumiScripts"
guard_expect_absent_path 'removed userscript product path' "$removed_path"

production_roots=(
  App
  Settings
  FloatingBar
  SidebarChrome
  UI
  Sumi
  Packages
)

removed_symbols=(
  SumiUserscriptsModule
  UserScriptStore
  UserScriptGMBridge
  UserScriptEntity
  UserScriptResourceEntity
  SumiScriptsManager
  SumiScriptsToolbarConstants
  BrowserUserscriptRuntimeFactory
)

for symbol in "${removed_symbols[@]}"; do
  matches="$(
    guard_capture_matches \
      "\\b${symbol}\\b" \
      --glob '*.swift' --glob '*.h' --glob '*.m' --glob '*.mm' \
      "${production_roots[@]}"
  )"
  if [[ -n "$matches" ]]; then
    guard_record_failure "removed userscript product symbol returned ($symbol): $matches"
  fi
done

guard_finish 'removed userscript product audit'
