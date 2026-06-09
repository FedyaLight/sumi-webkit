#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

extension_manager_paths=(
  Sumi/Managers/ExtensionManager
)
status=0

check_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches

  matches="$(rg -n --glob '*.swift' -e "$pattern" "$@" || true)"
  if [[ -n "$matches" ]]; then
    printf 'disallowed %s:\n%s\n' "$label" "$matches" >&2
    status=1
  fi
}

check_absent \
  "manifest patching API" \
  'patchManifestForWebKit|manifestPatchCache|shouldSkipManifestPatch' \
  "${extension_manager_paths[@]}"

check_absent \
  "compat JS bundle loader" \
  'ExtensionRuntimeBundledScript|ExtensionRuntimeResources/' \
  "${extension_manager_paths[@]}"

check_absent \
  "compat JS artifact filenames" \
  'sumi_webkit_runtime_compat|webkit_runtime_compat|sumi_bridge\.js|sumi_external_runtime|sumi_content_guard_' \
  "${extension_manager_paths[@]}"

check_absent \
  "compat JS template assembly" \
  'ExtensionManager\+ExternallyConnectableScripts|pageWorldExternallyConnectableBridgeScript|webKitRuntimeCompatibilityPreludeScript|selectiveContentScriptGuardScript' \
  "${extension_manager_paths[@]}"

if [[ -d Sumi/Managers/ExtensionManager/ExtensionRuntimeResources ]]; then
  remaining_js="$(find Sumi/Managers/ExtensionManager/ExtensionRuntimeResources -name '*.js' 2>/dev/null || true)"
  if [[ -n "$remaining_js" ]]; then
    printf 'disallowed ExtensionRuntimeResources JS files remain:\n%s\n' "$remaining_js" >&2
    status=1
  fi
fi

if [[ "$status" -ne 0 ]]; then
  echo "Safari extension clean-import audit failed" >&2
  exit "$status"
fi

echo "Safari extension clean-import audit passed"
