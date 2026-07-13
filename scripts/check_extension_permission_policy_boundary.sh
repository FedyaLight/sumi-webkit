#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

old_owner='Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInstallCapabilityOwner.swift'
preparation='Sumi/Managers/ExtensionManager/ExtensionContextPreparation.swift'
declared='Sumi/Managers/ExtensionManager/ExtensionDeclaredPermissionApplicator.swift'
site_policy='Sumi/Managers/ExtensionManager/ExtensionSiteAccessPolicyApplicator.swift'
status_resolver='Sumi/Managers/ExtensionManager/ExtensionPermissionStatusResolver.swift'
compatibility='Sumi/Managers/ExtensionManager/WebExtensionRuntimeCompatibilityPolicy.swift'
coordinator='Sumi/Managers/ExtensionManager/ExtensionSiteAccessPolicyCoordinator.swift'

for file in "$preparation" "$declared" "$site_policy" "$status_resolver" "$compatibility"; do
  [[ -f "$file" ]] || {
    printf 'error: extension permission-policy role missing: %s\n' "$file" >&2
    exit 1
  }
done

if [[ -e "$old_owner" ]] \
    || rg -n '\bSafariExtensionInstallCapabilityOwner\b|\binstallCapabilityOwner\b' \
      Sumi SumiTests >/dev/null; then
  printf 'error: retired extension install-capability god surface returned\n' >&2
  exit 1
fi

if rg -n '\bExtensionManager\b|\bBrowserManager\b|struct (Dependencies|Actions)\b|\bCapabilities\b|\b[A-Za-z0-9_]+Owner\b' \
    "$declared" "$site_policy" "$status_resolver" "$compatibility"; then
  printf 'error: permission-policy role regained a manager root, bag, or owner facade\n' >&2
  exit 1
fi

if rg -n 'setPermissionStatus\(' "$status_resolver"; then
  printf 'error: permission status resolver must remain query-only\n' >&2
  exit 1
fi

if rg -n 'URLCoverage|grantedCoverage\(' "$status_resolver" \
    Sumi/Managers/ExtensionManager/ExtensionActionPageAccessAuthorizer.swift \
    Sumi/Managers/ExtensionManager/ExtensionPermissionPromptRouting.swift; then
  printf 'error: redundant match-pattern coverage workaround returned\n' >&2
  exit 1
fi

if rg -n 'grantRequestedPermissions\(|grantRequestedMatchPatterns\(|grantActiveTabURLAccess\(' \
    Sumi SumiTests >/dev/null; then
  printf 'error: retired permission facade or manual activeTab grant returned\n' >&2
  exit 1
fi

if rg -n 'prepareExtensionContextForRuntime\(' Sumi SumiTests >/dev/null; then
  printf 'error: retired runtime capability manager facade returned\n' >&2
  exit 1
fi

if rg -n 'ExtensionDeclaredPermissionApplicator|setPermissionStatus\(' \
    Sumi/Managers/ExtensionManager/ExtensionActionInvocationService.swift \
    Sumi/Managers/ExtensionManager/ExtensionActionPopupCoordinator.swift; then
  printf 'error: action/popup path regained permission re-grant mutation\n' >&2
  exit 1
fi

declared_line="$(rg -n 'declaredPermissionApplicator\.apply\(' "$preparation" | cut -d: -f1)"
site_line="$(rg -n 'siteAccessPolicyApplicator\.apply\(' "$preparation" | cut -d: -f1)"
stored_line="$(rg -n 'permissionDecisions\.applyStoredExtensionPermissionDecisions\(' "$preparation" | cut -d: -f1)"
runtime_line="$(rg -n 'context\.unsupportedAPIs = WebExtensionRuntimeCompatibilityPolicy' "$preparation" | cut -d: -f1)"
if [[ -z "$declared_line" || -z "$site_line" || -z "$stored_line" || -z "$runtime_line" ]] \
    || (( declared_line >= site_line || site_line >= stored_line || stored_line >= runtime_line )); then
  printf 'error: context permission preparation order regressed\n' >&2
  exit 1
fi

live_apply_line="$(rg -n 'policyApplicator\.apply\(' "$coordinator" | head -1 | cut -d: -f1)"
live_notify_line="$(rg -n 'notifySiteAccessPoliciesDidChangeIfNeeded\(' "$coordinator" \
  | cut -d: -f1 | awk -v apply="$live_apply_line" '$1 > apply { print; exit }')"
if [[ -z "$live_apply_line" || -z "$live_notify_line" ]] \
    || (( live_apply_line >= live_notify_line )); then
  printf 'error: live site-policy normalization publishes before context mutation\n' >&2
  exit 1
fi

if ! rg -Fq 'storageCleanupPlanner.storeCapabilitySnapshot(' \
      Sumi/Managers/ExtensionManager/WebExtensionStorageCleanupOwner.swift \
    || rg -n 'SafariExtensionInstallCapabilityOwner|installCapabilityOwner' \
      Sumi/Managers/ExtensionManager/WebExtensionStorageCleanupOwner.swift; then
  printf 'error: storage cleanup no longer uses its planner directly\n' >&2
  exit 1
fi

required_regressions=(
  'SumiTests/WebExtensionRuntimeCompatibilityPolicyTests.swift|testEverySupportedWebKitTargetSpellingUsesTheSamePolicy'
  'SumiTests/ExtensionContextPreparationTests.swift|testStoredDecisionOverridesManifestGrantDuringPreparation'
  'SumiTests/SafariExtensionActionPopupRuntimeTests.swift|testURLHubActiveTabUsesWebKitGestureWithoutGlobalGrant'
  'SumiTests/SafariExtensionActionPopupRuntimeTests.swift|testURLHubActiveTabDoesNotOverrideConfiguredDeny'
  'SumiTests/SafariExtensionSiteAccessPolicyTests.swift|testUnchangedPolicyReapplicationEmitsNoPermissionEvents'
)
for entry in "${required_regressions[@]}"; do
  file="${entry%%|*}"
  symbol="${entry#*|}"
  if ! rg -Fq "$symbol" "$file"; then
    printf 'error: required extension permission regression missing: %s\n' "$symbol" >&2
    exit 1
  fi
done

printf 'extension permission-policy boundary passed\n'
