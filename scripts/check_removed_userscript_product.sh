#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

removed_path="Sumi/Managers/SumiScripts"
remaining_files="$(rg --files "$removed_path" 2>/dev/null || true)"
if [[ -n "$remaining_files" ]]; then
  printf 'Removed userscript product path must not exist: %s\n' "$removed_path" >&2
  printf '%s\n' "$remaining_files" >&2
  exit 1
fi

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

failed=0
for symbol in "${removed_symbols[@]}"; do
  matches="$(rg -n -w --glob '*.swift' --glob '*.h' --glob '*.m' --glob '*.mm' \
    "$symbol" "${production_roots[@]}" || [[ $? -eq 1 ]])"
  if [[ -n "$matches" ]]; then
    printf 'Removed userscript product symbol returned (%s):\n%s\n' \
      "$symbol" "$matches" >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "removed userscript product audit passed"
