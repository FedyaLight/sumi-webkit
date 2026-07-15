#!/usr/bin/env bash
# Permission delegate callbacks must prove exact controller/context authority
# through typed ExtensionControllerCallbackEvidence and revalidate it before
# every observable or persistent effect. This guard keeps the boundary from
# regressing to manager/context-only callbacks or a universal callback hub.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

status=0

record_scan_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

admission='Sumi/Managers/ExtensionManager/ExtensionControllerCallbackAdmission.swift'
bridge='Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift'
callback_settlement='Sumi/Managers/ExtensionManager/ExtensionPermissionCallbackSettlement.swift'
url_settlement='Sumi/Managers/ExtensionManager/ExtensionURLPermissionCallbackSettlement.swift'
routing='Sumi/Managers/ExtensionManager/ExtensionPermissionPromptRouting.swift'

for file in "$admission" "$bridge" "$callback_settlement" "$url_settlement" "$routing"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: permission callback admission boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

# Every permission prompt delegate callback captures typed evidence before
# routing anything to callback settlement. The count is scoped to the
# permission-prompt section of the bridge so other callback families
# (native messaging) can hold their own captures without weakening this
# guard.
capture_count="$(
  awk '
    /\/\/ MARK: - Permission Prompts/ { section = 1; next }
    /\/\/ MARK: -/ { section = 0 }
    section && /controllerCallbackAdmission\.capture\(/ { count += 1 }
    END { print count + 0 }
  ' "$bridge"
)"
if (( ${capture_count:-0} != 3 )); then
  printf 'error: bridge must capture callback evidence in exactly the three permission callbacks (found %s)\n' \
    "${capture_count:-0}" >&2
  status=1
fi

# Callback settlement accepts only typed evidence — the manager/context-only
# callback API must not return.
evidence_param_count="$(
  guard_count_matches 'evidence: ExtensionControllerCallbackEvidence' \
    "$callback_settlement" "$url_settlement"
)"
if (( ${evidence_param_count:-0} < 3 )); then
  printf 'error: permission callback settlement lost its typed evidence parameters (found %s)\n' \
    "${evidence_param_count:-0}" >&2
  status=1
fi

context_param_hits="$(
  guard_capture_matches 'for extensionContext: WKWebExtensionContext' \
    "$callback_settlement" "$url_settlement"
)"
record_scan_matches \
  "context-only permission callback API returned to the callback owner" \
  "$context_param_hits"

# Identity must come from evidence, never be recomputed from the context
# after capture.
identity_recompute_hits="$(
  guard_capture_matches \
    'extensionID\(for:|profileId\(for:|contextIdentity\(for:' \
    "$callback_settlement" "$url_settlement" "$routing"
)"
record_scan_matches \
  "permission callback flow recomputes identity from the context after capture" \
  "$identity_recompute_hits"

# Post-await and between-effect revalidation must stay in place across all
# three callback families.
revalidation_count="$(
  guard_count_matches 'admission\.isCurrent\(evidence\)' \
    "$callback_settlement" "$url_settlement"
)"
if (( ${revalidation_count:-0} < 12 )); then
    printf 'error: permission callback settlement lost staleness revalidation between effects (%s < 12)\n' \
    "${revalidation_count:-0}" >&2
  status=1
fi

# Routing steps stay per-target so no bulk helper can hide multiple observable
# mutations behind a single staleness check.
bulk_helper_hits="$(
  guard_capture_matches \
    'applyStoredPermissionDecisions\(|applyConfiguredSiteAccessDecisions\(|resolveURLPermissionsBeforePrompt\(' \
    Sumi -g '*.swift'
)"
record_scan_matches \
  "bulk multi-target permission routing helper returned" \
  "$bulk_helper_hits"

hidden_url_effects="$(
  guard_capture_matches \
    'grantSiteAccess\(|denySiteAccess\(|explicitlyGrantURLIfCoveredByGrantedMatchPattern\(' \
    "$routing" "$callback_settlement" "$url_settlement"
)"
record_scan_matches \
  "permission callback routing hides URL effects behind a compound helper" \
  "$hidden_url_effects"

# No universal callback hub may replace the narrow admission capability.
callback_hub_hits="$(
  guard_capture_matches \
    'CallbackCoordinator|CallbackHub|CallbackFacade|CallbackDependencies|CallbackActions' \
    Sumi -g '*.swift'
)"
record_scan_matches "universal extension callback hub appeared" "$callback_hub_hits"

# Admission stays a narrow capture/isCurrent capability without repair or
# fallback resolution.
admission_lines="$(wc -l < "$admission" | tr -d ' ')"
if (( admission_lines > 95 )); then
  printf 'error: callback admission grew beyond capture/revalidation (%s > 95 LOC)\n' \
    "$admission_lines" >&2
  status=1
fi

callback_settlement_lines="$(wc -l < "$callback_settlement" | tr -d ' ')"
if (( callback_settlement_lines > 350 )); then
  printf 'error: named permission callback settlement grew beyond its two families (%s > 350 LOC)\n' \
    "$callback_settlement_lines" >&2
  status=1
fi

url_settlement_lines="$(wc -l < "$url_settlement" | tr -d ' ')"
if (( url_settlement_lines > 350 )); then
  printf 'error: URL permission callback settlement grew beyond one family (%s > 350 LOC)\n' \
    "$url_settlement_lines" >&2
  status=1
fi

routing_lines="$(wc -l < "$routing" | tr -d ' ')"
if (( routing_lines > 200 )); then
  printf 'error: permission prompt routing grew beyond per-target steps (%s > 200 LOC)\n' \
    "$routing_lines" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "extension permission callback admission boundary passed"
