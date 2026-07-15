#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

old_owner='Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInstallCapabilityOwner.swift'
preparation='Sumi/Managers/ExtensionManager/ExtensionContextPreparation.swift'
declared='Sumi/Managers/ExtensionManager/ExtensionDeclaredPermissionApplicator.swift'
site_policy='Sumi/Managers/ExtensionManager/ExtensionSiteAccessPolicyApplicator.swift'
status_resolver='Sumi/Managers/ExtensionManager/ExtensionPermissionStatusResolver.swift'
compatibility='Sumi/Managers/ExtensionManager/WebExtensionRuntimeCompatibilityPolicy.swift'
coordinator='Sumi/Managers/ExtensionManager/ExtensionSiteAccessPolicyCoordinator.swift'
storage_cleanup='Sumi/Managers/ExtensionManager/WebExtensionStorageCleanupOwner.swift'

reject_production_pattern() {
  local message="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(guard_capture_matches "$pattern" "$@")" || return
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    printf 'error: %s\n' "$message" >&2
    return 1
  fi
}

require_production_pattern() {
  local message="$1"
  local pattern="$2"
  shift 2
  local count
  count="$(guard_count_matches "$pattern" "$@")" || return
  if (( count == 0 )); then
    printf 'error: %s\n' "$message" >&2
    return 1
  fi
}

for file in "$preparation" "$declared" "$site_policy" "$status_resolver" \
  "$compatibility" "$coordinator" "$storage_cleanup"; do
  guard_require_file "$file"
done

if [[ -e "$old_owner" || -L "$old_owner" ]]; then
  printf 'error: retired extension install-capability god surface returned\n' >&2
  exit 1
fi
reject_production_pattern \
  'retired extension install-capability god surface returned' \
  '\bSafariExtensionInstallCapabilityOwner\b|\binstallCapabilityOwner\b' Sumi

reject_production_pattern \
  'permission-policy role regained a manager root, bag, or owner facade' \
  '\bExtensionManager\b|\bBrowserManager\b|struct (Dependencies|Actions)\b|\bCapabilities\b|\b[A-Za-z0-9_]+Owner\b' \
  "$declared" "$site_policy" "$status_resolver" "$compatibility"
reject_production_pattern \
  'permission status resolver must remain query-only' \
  'setPermissionStatus\(' "$status_resolver"
reject_production_pattern \
  'redundant match-pattern coverage workaround returned' \
  'URLCoverage|grantedCoverage\(' "$status_resolver" \
  Sumi/Managers/ExtensionManager/ExtensionActionPageAccessAuthorizer.swift \
  Sumi/Managers/ExtensionManager/ExtensionPermissionPromptRouting.swift
reject_production_pattern \
  'retired permission facade or manual activeTab grant returned' \
  'grantRequestedPermissions\(|grantRequestedMatchPatterns\(|grantActiveTabURLAccess\(' Sumi
reject_production_pattern \
  'retired runtime capability manager facade returned' \
  'prepareExtensionContextForRuntime\(' Sumi
reject_production_pattern \
  'action/popup path regained permission re-grant mutation' \
  'ExtensionDeclaredPermissionApplicator|setPermissionStatus\(' \
  Sumi/Managers/ExtensionManager/ExtensionActionInvocationService.swift \
  Sumi/Managers/ExtensionManager/ExtensionActionPopupCoordinator.swift

declared_line="$(guard_capture_matches 'declaredPermissionApplicator\.apply\(' "$preparation" | cut -d: -f1)"
site_line="$(guard_capture_matches 'siteAccessPolicyApplicator\.apply\(' "$preparation" | cut -d: -f1)"
stored_line="$(guard_capture_matches 'permissionDecisions\.applyStoredExtensionPermissionDecisions\(' "$preparation" | cut -d: -f1)"
runtime_line="$(guard_capture_matches 'context\.unsupportedAPIs = WebExtensionRuntimeCompatibilityPolicy' "$preparation" | cut -d: -f1)"
if [[ -z "$declared_line" || -z "$site_line" || -z "$stored_line" || -z "$runtime_line" ]] \
    || (( declared_line >= site_line || site_line >= stored_line || stored_line >= runtime_line )); then
  printf 'error: context permission preparation order regressed\n' >&2
  exit 1
fi

live_apply_line="$(guard_capture_matches 'policyApplicator\.apply\(' "$coordinator" -m 1 | cut -d: -f1)"
live_notify_line="$(guard_capture_matches 'notifySiteAccessPoliciesDidChangeIfNeeded\(' "$coordinator" \
  | cut -d: -f1 | awk -v apply="$live_apply_line" '$1 > apply { print; exit }')"
if [[ -z "$live_apply_line" || -z "$live_notify_line" ]] \
    || (( live_apply_line >= live_notify_line )); then
  printf 'error: live site-policy normalization publishes before context mutation\n' >&2
  exit 1
fi

require_production_pattern \
  'storage cleanup no longer uses its planner directly' \
  'storageCleanupPlanner\.storeCapabilitySnapshot\(' "$storage_cleanup"
reject_production_pattern \
  'storage cleanup no longer uses its planner directly' \
  'SafariExtensionInstallCapabilityOwner|installCapabilityOwner' "$storage_cleanup"

printf 'extension permission-policy boundary passed\n'
