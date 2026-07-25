#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

extension_manager_paths=(
  Sumi/Managers/ExtensionManager
)
status=0

record_absent_scan() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches

  matches="$(guard_capture_matches "$pattern" -g '*.swift' "$@")"
  if [[ -n "$matches" ]]; then
    printf 'disallowed %s:\n%s\n' "$label" "$matches" >&2
    status=1
  fi
}

record_absent_scan \
  "manifest patching API" \
  'patchManifestForWebKit|manifestPatchCache|shouldSkipManifestPatch' \
  "${extension_manager_paths[@]}"

record_absent_scan \
  "compat JS bundle loader" \
  'ExtensionRuntimeBundledScript|ExtensionRuntimeResources/' \
  "${extension_manager_paths[@]}"

record_absent_scan \
  "compat JS artifact filenames" \
  'sumi_webkit_runtime_compat|webkit_runtime_compat|sumi_bridge\.js|sumi_external_runtime|sumi_content_guard_' \
  "${extension_manager_paths[@]}"

record_absent_scan \
  "compat JS template assembly" \
  'ExtensionManager\+ExternallyConnectableScripts|pageWorldExternallyConnectableBridgeScript|webKitRuntimeCompatibilityPreludeScript|selectiveContentScriptGuardScript' \
  "${extension_manager_paths[@]}"

record_absent_scan \
  "Safari app-extension copied-resource runtime fallback" \
  'SafariAppExtensionResources\.copyResources|falling back to copied package' \
  Sumi/Managers/ExtensionManager

if [[ -d Sumi/Managers/ExtensionManager/ExtensionRuntimeResources ]]; then
  remaining_js="$(
    find Sumi/Managers/ExtensionManager/ExtensionRuntimeResources \
      -type f -name '*.js' -print
  )"
  if [[ -n "$remaining_js" ]]; then
    printf 'disallowed ExtensionRuntimeResources JS files remain:\n%s\n' "$remaining_js" >&2
    status=1
  fi
fi

record_absent_scan \
  "extension-specific native messaging branches" \
  'if extensionId ==|switch extensionId' \
  Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelayLoopGuard.swift \
  Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingDiagnosticCoalescer.swift \
  Sumi/Managers/ExtensionManager/ExtensionActionPopupAnchorResolver.swift

requested_tab_sources=(
  Sumi/Managers/ExtensionManager/ExtensionCreatedTabRuntimeRegistrar.swift
  Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationEvidence.swift
  Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationReceipt.swift
  Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationValidator.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabContextPreloader.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabOpeningService.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabCreation.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabDisposition.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeAdmission.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabBindingDiagnostics.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeCapabilities.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabTargetResolver.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabInitialTargetResolver.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabResidenceValidator.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedWindowEvidence.swift
  Sumi/Managers/ExtensionManager/ExtensionRequestedTabWebViewMaterializer.swift
)

if [[ -e Sumi/Managers/ExtensionManager/ExtensionRequestedTabLifecycleOwner.swift ]]; then
  printf 'disallowed requested-tab lifecycle god surface still exists\n' >&2
  status=1
fi

record_absent_scan \
  "requested-tab ExtensionManager dependency" \
  'manager:[[:space:]]*ExtensionManager' \
  "${requested_tab_sources[@]}"

record_absent_scan \
  "requested-tab manager facade" \
  'func (prepareExtensionRequestedTabForInitialLoad|prepareContentScriptContextsForExtensionRequestedInitialLoad|openExtensionRequestedTab|materializeExtensionRequestedNormalTabIfNeeded|registerExtensionCreatedTabWithExtensionRuntime)[[:space:]]*\(' \
  Sumi/Managers/ExtensionManager

requested_tab_size_limits=(
  'Sumi/Managers/ExtensionManager/ExtensionCreatedTabRuntimeRegistrar.swift:120'
  'Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationReceipt.swift:150'
  'Sumi/Managers/ExtensionManager/ExtensionCreatedTabPublicationValidator.swift:220'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabContextPreloader.swift:120'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabOpeningService.swift:240'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabCreation.swift:60'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabDisposition.swift:60'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeAdmission.swift:80'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabBindingDiagnostics.swift:80'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabRuntimeCapabilities.swift:80'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabTargetResolver.swift:120'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabInitialTargetResolver.swift:190'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabResidenceValidator.swift:120'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedWindowEvidence.swift:150'
  'Sumi/Managers/ExtensionManager/ExtensionRequestedTabWebViewMaterializer.swift:180'
)
for entry in "${requested_tab_size_limits[@]}"; do
  file="${entry%:*}"
  limit="${entry##*:}"
  lines="$(wc -l < "$file")"
  if (( lines > limit )); then
    printf 'requested-tab component exceeds honest size boundary: %s has %s lines (limit %s)\n' \
      "$file" "$lines" "$limit" >&2
    status=1
  fi
done

if [[ ! -f SumiTests/Fixtures/Extensions/login-form.html ]]; then
  printf 'missing PM autofill manual fixture: SumiTests/Fixtures/Extensions/login-form.html\n' >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  echo "Safari extension clean-import audit failed" >&2
  exit "$status"
fi

echo "Safari extension clean-import audit passed"
