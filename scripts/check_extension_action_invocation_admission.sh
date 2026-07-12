#!/usr/bin/env bash
# Extension action invocation must be one exact fail-closed transaction:
# request evidence captured before runtime resolution, completed with exact
# runtime evidence after its await, and revalidated before every independent
# effect. This guard keeps the
# boundary from regressing to mutable context/Tab/URL inputs, a universal
# action hub, or a stale prompt that can reach persistence or dispatch.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

fail_matches() {
  local message="$1"
  local matches="$2"
  [[ -z "$matches" ]] && return
  printf 'error: %s:\n%s\n' "$message" "$matches" >&2
  status=1
}

admission='Sumi/Managers/ExtensionManager/ExtensionActionInvocationAdmission.swift'
request_admission='Sumi/Managers/ExtensionManager/ExtensionActionRequestAdmission.swift'
service='Sumi/Managers/ExtensionManager/ExtensionActionInvocationService.swift'
authorizer='Sumi/Managers/ExtensionManager/ExtensionActionPageAccessAuthorizer.swift'
collection='Sumi/Managers/ExtensionManager/InstalledExtensionCollection.swift'
tests='SumiTests/ExtensionActionInvocationAdmissionTests.swift'

for file in "$request_admission" "$admission" "$service" "$authorizer" "$collection" "$tests"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: action invocation admission boundary missing: %s\n' "$file" >&2
    status=1
  fi
done
if [[ $status -ne 0 ]]; then
  exit "$status"
fi

# The click request is captured once before runtime resolution suspends, then
# exact invocation evidence is completed once after it settles and before any
# action effect.
request_capture_count="$(rg -c 'requestAdmission\.capture\(' "$service" || true)"
if (( ${request_capture_count:-0} != 1 )); then
  printf 'error: invocation service must capture request evidence exactly once (found %s)\n' \
    "${request_capture_count:-0}" >&2
  status=1
fi
capture_count="$(rg -c 'admission\.capture\(' "$service" || true)"
if (( ${capture_count:-0} != 1 )); then
  printf 'error: invocation service must capture typed evidence exactly once (found %s)\n' \
    "${capture_count:-0}" >&2
  status=1
fi
capture_line="$(rg -n 'admission\.capture\(' "$service" | head -1 | cut -d: -f1)"
request_capture_line="$(rg -n 'requestAdmission\.capture\(' "$service" | head -1 | cut -d: -f1)"
runtime_await_line="$(rg -n 'switch await environment\.runtimeResolver\.resolve\(' "$service" | head -1 | cut -d: -f1)"
if [[ -n "${request_capture_line:-}" && -n "${runtime_await_line:-}" \
   && -n "${capture_line:-}" ]] \
  && (( request_capture_line >= runtime_await_line \
        || runtime_await_line >= capture_line )); then
  printf 'error: request/runtime capture order regressed (request %s, await %s, runtime %s)\n' \
    "$request_capture_line" "$runtime_await_line" "$capture_line" >&2
  status=1
fi
first_effect_line="$(
  rg -n 'grantRequestedPermissions\(|grantRequestedMatchPatterns\(|updateActionSurfaceState\(|performAction\(|recordRuntimeMetric\(' \
    "$service" | head -1 | cut -d: -f1
)"
if [[ -n "${capture_line:-}" && -n "${first_effect_line:-}" ]] \
  && (( capture_line >= first_effect_line )); then
  printf 'error: invocation service performs effects before evidence capture (capture at %s, first effect at %s)\n' \
    "$capture_line" "$first_effect_line" >&2
  status=1
fi

# Post-await / between-effect revalidation must stay in place.
service_revalidation="$(rg -c 'admission\.isCurrent\(evidence\)|admission\.admitAdapter\(' "$service" || true)"
if (( ${service_revalidation:-0} < 5 )); then
  printf 'error: invocation service lost staleness revalidation between effects (%s < 5)\n' \
    "${service_revalidation:-0}" >&2
  status=1
fi
authorizer_revalidation="$(rg -c 'admission\.isCurrent\(evidence\)' "$authorizer" || true)"
if (( ${authorizer_revalidation:-0} < 10 )); then
  printf 'error: page-access authorizer lost staleness revalidation between effects (%s < 10)\n' \
    "${authorizer_revalidation:-0}" >&2
  status=1
fi

# The authorizer accepts only typed evidence — the mutable
# context/installedExtension/tab parameter API must not return.
if ! rg -A 2 'func authorize\(' "$authorizer" \
  | rg -q 'evidence: ExtensionActionInvocationEvidence'; then
  printf 'error: page-access authorizer lost its typed evidence API\n' >&2
  status=1
fi
mutable_authorize_hits="$(
  rg -n 'func authorize\(\s*$' -A 3 "$authorizer" \
    | rg 'context: WKWebExtensionContext|tab: Tab\b|installedExtension: InstalledExtension' || true
)"
fail_matches \
  "mutable context/record/tab inputs returned to page-access authorization" \
  "$mutable_authorize_hits"

# Identity comes from evidence after request capture; the service and effect
# settlement never recompute it from mutable global state. RequestAdmission
# is the only layer allowed to resolve and then revalidate fallback identity.
identity_recompute_hits="$(
  rg -n 'extensionID\(for:|extensionId\(for:|profileId\(for:|contextIdentity\(for:|resolvedProfileId\(|currentProfileId\b' \
    "$service" "$authorizer" || true
)"
fail_matches \
  "action invocation recomputes identity from mutable state after capture" \
  "$identity_recompute_hits"
url_fallback_hits="$(
  rg -n 'baseURL\s*==' "$admission" "$service" "$authorizer" || true
)"
fail_matches "URL-equality fallback admission appeared" "$url_fallback_hits"

# The evidence/admission/settlement layer must not hold a manager root or a
# closure bag.
manager_root_hits="$(
  rg -n 'manager\s*:\s*ExtensionManager|extensionManager\s*:\s*ExtensionManager|weak var manager' \
    "$admission" || true
)"
fail_matches "manager root appeared in action invocation admission" "$manager_root_hits"
closure_bag_hits="$(
  rg -n 'struct Dependencies|struct Actions\b' "$request_admission" "$admission" "$service" "$authorizer" || true
)"
fail_matches "closure-bag DI appeared in the action invocation boundary" "$closure_bag_hits"

# Explicit composition records may carry only the narrow live seams required
# at the framework boundary. This prevents Environment from becoming a hidden
# action god-object made mostly of arbitrary closures.
service_closure_count="$(rg -c 'let .*: @MainActor .*->' "$service" || true)"
authorizer_closure_count="$(rg -c 'let .*: @MainActor .*->' "$authorizer" || true)"
if (( ${service_closure_count:-0} > 4 || ${authorizer_closure_count:-0} > 2 )); then
  printf 'error: action composition grew into a closure bag (service %s/4, authorizer %s/2)\n' \
    "${service_closure_count:-0}" "${authorizer_closure_count:-0}" >&2
  status=1
fi

# No universal action hub may replace the narrow admission capability.
action_hub_hits="$(
  rg -n 'ActionInvocationHub|ActionCoordinator|ActionCallbackHub|UniversalActionDispatcher' \
    Sumi -g '*.swift' || true
)"
fail_matches "universal extension action hub appeared" "$action_hub_hits"

# A stale prompt result must pass an exact admission barrier before every
# WebKit mutation, durable persistence step and diagnostic in the prompt
# settlement, and before action dispatch in the service.
for effect in 'grantSiteAccess[(]' 'denySiteAccess[(]' 'setConfiguredSiteAccess[(]' \
  'persistExtensionPermissionDecision[(]' 'recordHostPermission[(]'; do
  unguarded="$(
    awk -v pattern="$effect" '
      /admission\.isCurrent\(evidence\)/ { guard_line = NR }
      $0 ~ pattern {
        if (guard_line == 0 || NR - guard_line > 12) {
          printf "%d:%s\n", NR, $0
        }
      }
    ' "$authorizer"
  )"
  fail_matches \
    "page-access effect ${effect} lost its preceding admission barrier" \
    "$unguarded"
done
unguarded_dispatch="$(
  awk '
    /admission\.isCurrent\(evidence\)/ { guard_line = NR }
    /performAction\(for:/ {
      if (guard_line == 0 || NR - guard_line > 30) {
        printf "%d:%s\n", NR, $0
      }
    }
  ' "$service"
)"
fail_matches "performAction lost its preceding admission barrier" "$unguarded_dispatch"
unguarded_metric="$(
  awk '
    /admission\.isCurrent\(evidence\)/ { guard_line = NR }
    /recordRuntimeMetric\(/ {
      if (guard_line == 0 || NR - guard_line > 8) {
        printf "%d:%s\n", NR, $0
      }
    }
  ' "$service"
)"
fail_matches "runtime metric mutation lost its preceding admission barrier" "$unguarded_metric"

dispatch_line="$(rg -n 'performAction\(for:' "$service" | head -1 | cut -d: -f1)"
dispatch_probe_line="$(rg -n 'actionDispatchProbe\(extensionID\)' "$service" | head -1 | cut -d: -f1)"
if [[ -n "${dispatch_line:-}" && -n "${dispatch_probe_line:-}" ]] \
  && (( dispatch_probe_line <= dispatch_line )); then
  printf 'error: action dispatch probe runs before WebKit performAction (%s <= %s)\n' \
    "$dispatch_probe_line" "$dispatch_line" >&2
  status=1
fi

# Evidence covers every authority dimension: runtime binding, catalog record
# revision, Tab profile revision, committed-document proof, exact adapter.
for required_dimension in \
  'ExtensionControllerCallbackEvidence' \
  'recordRevision\(' \
  'profileAssignment\.changeRevision' \
  'committedDocumentRuntime\.authorityProof' \
  'existingTabAdapter\(for:'; do
  if ! rg -q "$required_dimension" "$request_admission" "$admission"; then
    printf 'error: action invocation evidence lost the %s authority dimension\n' \
      "$required_dimension" >&2
    status=1
  fi
done
for request_dimension in 'runtimeBindingAtClick' 'resolvedProfileId\(' \
  'request\.resolvedProfileID == profileID' \
  'browserRuntime\.allTabs\(\)\.contains.*==='; do
  if ! rg -Uq "$request_dimension" "$request_admission" "$admission"; then
    printf 'error: pre-resolution request lost exact %s validation\n' \
      "$request_dimension" >&2
    status=1
  fi
done

# The catalog keeps tombstoned per-record revisions.
if ! rg -q 'func recordRevision\(for id: String\) -> UInt64' "$collection"; then
  printf 'error: installed-extension catalog lost its per-record revision authority\n' >&2
  status=1
fi

# Focused production types keep justified LOC caps.
check_loc() {
  local file="$1"
  local cap="$2"
  local label="$3"
  local lines
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > cap )); then
    printf 'error: %s grew beyond its focused responsibility (%s > %s LOC)\n' \
      "$label" "$lines" "$cap" >&2
    status=1
  fi
}
check_loc "$request_admission" 130 "action request admission"
check_loc "$admission" 210 "action invocation admission"
check_loc "$service" 240 "action invocation service"
check_loc "$authorizer" 320 "page-access authorizer"
check_loc "$collection" 160 "installed-extension collection"

for required_regression in \
  testExactCurrentInvocationReachesActionDispatchOnce \
  testContextReplacementDuringAuthorizationFailsClosed \
  testSameContextRebindDuringAuthorizationInvalidatesInvocation \
  testControllerABADuringAuthorizationCannotReviveInvocation \
  testExtensionLoadGenerationChangeDuringAuthorizationInvalidatesInvocation \
  testInstalledRecordRemovalDuringAuthorizationInvalidatesInvocation \
  testInstalledRecordDisableDuringAuthorizationInvalidatesInvocation \
  testUnrelatedExtensionMutationDoesNotInvalidateInvocation \
  testTabProfileChangeDuringAuthorizationFailsClosed \
  testMainFrameDocumentReplacementDuringAuthorizationFailsClosed \
  testStalePromptAllowPerformsNoMutationPersistenceActionOrMetric \
  testStalePromptDenyPerformsNoStaleMutationPersistenceOrAction \
  testReentrantInvalidationBetweenPermissionMutationAndPersistenceStopsTail \
  testReentrantInvalidationBetweenActionPublicationAndDispatchPreventsPerformAction \
  testStaleInvocationSettlesDeterministicallyOnceWithoutLateEffects \
  testUntrackedTabIsRejectedBeforeRuntimeResolution \
  testNoTabFallbackProfileChangeDuringRuntimeResolutionInvalidatesRequest \
  testExistingRuntimeRebindDuringRuntimeResolutionInvalidatesRequest \
  testDocumentReplacementDuringRuntimeResolutionInvalidatesRequest \
  testAdapterAbsenceIsExactAuthority \
  testRejectedInvocationDoesNotMaterializeLazyRuntimeSystems; do
  if ! rg -Fq "func $required_regression" "$tests"; then
    printf 'error: action invocation admission regression missing: %s\n' \
      "$required_regression" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "extension action invocation admission boundary passed"
