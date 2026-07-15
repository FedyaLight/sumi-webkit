#!/usr/bin/env bash
# Extension action invocation must be one exact fail-closed transaction:
# request evidence captured before runtime resolution, completed with exact
# runtime evidence after its await, and revalidated before every independent
# effect. This guard keeps the
# boundary from regressing to mutable context/Tab/URL inputs, a universal
# action hub, or a stale prompt that can reach persistence or dispatch.
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

admission='Sumi/Managers/ExtensionManager/ExtensionActionInvocationAdmission.swift'
request_admission='Sumi/Managers/ExtensionManager/ExtensionActionRequestAdmission.swift'
service='Sumi/Managers/ExtensionManager/ExtensionActionInvocationService.swift'
dispatch='Sumi/Managers/ExtensionManager/ExtensionActionDispatch.swift'
authorizer='Sumi/Managers/ExtensionManager/ExtensionActionPageAccessAuthorizer.swift'
collection='Sumi/Managers/ExtensionManager/InstalledExtensionCollection.swift'

for file in "$request_admission" "$admission" "$service" "$dispatch" "$authorizer" "$collection"; do
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
request_capture_count="$(guard_count_matches 'requestAdmission\.capture\(' "$service")"
if (( ${request_capture_count:-0} != 1 )); then
  printf 'error: invocation service must capture request evidence exactly once (found %s)\n' \
    "${request_capture_count:-0}" >&2
  status=1
fi
capture_count="$(guard_count_matches 'admission\.capture\(' "$service")"
if (( ${capture_count:-0} != 1 )); then
  printf 'error: invocation service must capture typed evidence exactly once (found %s)\n' \
    "${capture_count:-0}" >&2
  status=1
fi
capture_line="$(
  guard_capture_matches 'admission\.capture\(' "$service" -m 1 | cut -d: -f1
)"
request_capture_line="$(
  guard_capture_matches 'requestAdmission\.capture\(' "$service" -m 1 | cut -d: -f1
)"
runtime_await_line="$(
  guard_capture_matches 'switch await environment\.runtimeResolver\.resolve\(' \
    "$service" -m 1 | cut -d: -f1
)"
if [[ -z "${request_capture_line:-}" || -z "${runtime_await_line:-}" \
   || -z "${capture_line:-}" ]] \
  || (( request_capture_line >= runtime_await_line \
        || runtime_await_line >= capture_line )); then
  printf 'error: request/runtime capture order regressed (request %s, await %s, runtime %s)\n' \
    "$request_capture_line" "$runtime_await_line" "$capture_line" >&2
  status=1
fi
first_effect_line="$(
  guard_capture_matches \
    'registerTab\(|applyConfiguredPolicy\(|authorize\(|updateActionSurfaceState\(|performAction\(|recordRuntimeMetric\(' \
    "$service" -m 1 | cut -d: -f1
)"
if [[ -z "${capture_line:-}" || -z "${first_effect_line:-}" ]] \
  || (( capture_line >= first_effect_line )); then
  printf 'error: invocation service performs effects before evidence capture (capture at %s, first effect at %s)\n' \
    "$capture_line" "$first_effect_line" >&2
  status=1
fi

# Post-await / between-effect revalidation must stay in place.
service_revalidation="$(
  guard_count_matches \
    'admission\.isCurrent\(evidence\)|admission\.admitAdapter\(' "$service"
)"
dispatch_revalidation="$(
  guard_count_matches 'admission\.isCurrent\(evidence\)' "$dispatch"
)"
if (( ${service_revalidation:-0} < 4 || ${dispatch_revalidation:-0} < 3 )); then
  printf 'error: invocation transaction lost staleness revalidation between effects (service %s/4, dispatch %s/3)\n' \
    "${service_revalidation:-0}" "${dispatch_revalidation:-0}" >&2
  status=1
fi
authorizer_revalidation="$(
  guard_count_matches 'admission\.isCurrent\(evidence\)' "$authorizer"
)"
if (( ${authorizer_revalidation:-0} < 10 )); then
  printf 'error: page-access authorizer lost staleness revalidation between effects (%s < 10)\n' \
    "${authorizer_revalidation:-0}" >&2
  status=1
fi

# The authorizer accepts only typed evidence — the mutable
# context/installedExtension/tab parameter API must not return.
typed_authorize_count="$(
  guard_capture_matches 'func authorize\(' "$authorizer" -A 2 \
    | guard_count_matches 'evidence: ExtensionActionInvocationEvidence' -
)"
if (( typed_authorize_count == 0 )); then
  printf 'error: page-access authorizer lost its typed evidence API\n' >&2
  status=1
fi
mutable_authorize_hits="$(
  guard_capture_matches 'func authorize\(\s*$' "$authorizer" -A 3 \
    | guard_capture_matches \
      'context: WKWebExtensionContext|tab: Tab\b|installedExtension: InstalledExtension' -
)"
record_scan_matches \
  "mutable context/record/tab inputs returned to page-access authorization" \
  "$mutable_authorize_hits"

# Identity comes from evidence after request capture; the service and effect
# settlement never recompute it from mutable global state. RequestAdmission
# is the only layer allowed to resolve and then revalidate fallback identity.
identity_recompute_hits="$(
  guard_capture_matches \
    'extensionID\(for:|extensionId\(for:|profileId\(for:|contextIdentity\(for:|resolvedProfileId\(|currentProfileId\b' \
    "$service" "$authorizer"
)"
record_scan_matches \
  "action invocation recomputes identity from mutable state after capture" \
  "$identity_recompute_hits"
url_fallback_hits="$(
  guard_capture_matches 'baseURL\s*==' \
    "$admission" "$service" "$authorizer"
)"
record_scan_matches "URL-equality fallback admission appeared" "$url_fallback_hits"

# The evidence/admission/settlement layer must not hold a manager root or a
# closure bag.
manager_root_hits="$(
  guard_capture_matches \
    'manager\s*:\s*ExtensionManager|extensionManager\s*:\s*ExtensionManager|weak var manager' \
    "$admission" "$dispatch"
)"
record_scan_matches "manager root appeared in action invocation admission" "$manager_root_hits"
closure_bag_hits="$(
  guard_capture_matches 'struct Dependencies|struct Actions\b' \
    "$request_admission" "$admission" "$service" "$dispatch" "$authorizer"
)"
record_scan_matches "closure-bag DI appeared in the action invocation boundary" "$closure_bag_hits"

# Explicit composition records may carry only the narrow live seams required
# at the framework boundary. This prevents Environment from becoming a hidden
# action god-object made mostly of arbitrary closures.
service_closure_count="$(guard_count_matches 'let .*: @MainActor .*->' "$service")"
authorizer_closure_count="$(
  guard_count_matches 'let .*: @MainActor .*->' "$authorizer"
)"
if (( ${service_closure_count:-0} > 4 || ${authorizer_closure_count:-0} > 2 )); then
  printf 'error: action composition grew into a closure bag (service %s/4, authorizer %s/2)\n' \
    "${service_closure_count:-0}" "${authorizer_closure_count:-0}" >&2
  status=1
fi

# No universal action hub may replace the narrow admission capability.
action_hub_hits="$(
  guard_capture_matches \
    'ActionInvocationHub|ActionCoordinator|ActionCallbackHub|UniversalActionDispatcher' \
    Sumi -g '*.swift'
)"
record_scan_matches "universal extension action hub appeared" "$action_hub_hits"

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
  record_scan_matches \
    "page-access effect ${effect} lost its preceding admission barrier" \
    "$unguarded"
done
unguarded_dispatch="$(
  awk '
    /admission\.isCurrent\(evidence\)/ { guard_line = NR }
    /performAction\(for:/ {
      if (guard_line == 0 || NR - guard_line > 8) {
        printf "%d:%s\n", NR, $0
      }
    }
  ' "$dispatch"
)"
record_scan_matches "performAction lost its preceding admission barrier" "$unguarded_dispatch"
direct_dispatch_count="$(guard_count_matches 'performAction\(for:' "$dispatch")"
service_direct_dispatch_count="$(guard_count_matches 'performAction\(for:' "$service")"
if (( ${direct_dispatch_count:-0} != 1 || ${service_direct_dispatch_count:-0} != 0 )); then
  printf 'error: exact dispatch boundary must own the only WebKit action call (dispatch %s, service %s)\n' \
    "${direct_dispatch_count:-0}" "${service_direct_dispatch_count:-0}" >&2
  status=1
fi
perform_action_line="$(
  guard_capture_matches 'performAction\(for:' "$dispatch" -m 1 | cut -d: -f1
)"
pre_dispatch_guard_line="$(awk -v call="$perform_action_line" '
  NR < call && /admission\.isCurrent\(evidence\)/ { line = NR }
  END { if (line) print line }
' "$dispatch")"
post_dispatch_guard_line="$(awk -v call="$perform_action_line" '
  NR > call && /admission\.isCurrent\(evidence\)/ { print NR; exit }
' "$dispatch")"
if [[ -z "$pre_dispatch_guard_line" || -z "$post_dispatch_guard_line" ]] \
  || (( perform_action_line - pre_dispatch_guard_line > 8 \
        || post_dispatch_guard_line - perform_action_line > 8 )); then
  printf 'error: WebKit action call lost its immediate before/after admission barriers\n' >&2
  status=1
fi
registration_line="$(
  guard_capture_matches 'popupInvocations\.register\(' \
    "$dispatch" -m 1 | cut -d: -f1
)"
cancel_count="$(guard_count_matches '^\s+cancel\(registration\)' "$dispatch")"
if [[ -z "$registration_line" ]] || (( registration_line >= perform_action_line \
    || ${cancel_count:-0} != 2 )); then
  printf 'error: dispatch lost popup registration-before-call or two stale cancellation paths\n' >&2
  status=1
fi
unguarded_metric="$(
  awk '
    /admission\.isCurrent\(evidence\)/ { guard_line = NR }
    /runtimeMetrics\.recordBackgroundWakeInvocation\(/ {
      if (guard_line == 0 || NR - guard_line > 8) {
        printf "%d:%s\n", NR, $0
      }
    }
  ' "$service"
)"
record_scan_matches "runtime metric mutation lost its preceding admission barrier" "$unguarded_metric"

dispatch_line="$(
  guard_capture_matches 'actionDispatch\.perform\(' "$service" -m 1 | cut -d: -f1
)"
dispatch_probe_line="$(
  guard_capture_matches 'actionDispatchProbe\(extensionID\)' \
    "$service" -m 1 | cut -d: -f1
)"
post_dispatch_admission_line="$(awk -v probe="$dispatch_probe_line" '
  NR > probe && /admission\.isCurrent\(evidence\)/ { print NR; exit }
' "$service")"
metric_line="$(
  guard_capture_matches 'runtimeMetrics\.recordBackgroundWakeInvocation\(' \
    "$service" -m 1 | cut -d: -f1
)"
if [[ -z "${dispatch_line:-}" || -z "${dispatch_probe_line:-}" \
   || -z "${post_dispatch_admission_line:-}" || -z "${metric_line:-}" ]] \
  || (( dispatch_line >= dispatch_probe_line \
        || dispatch_probe_line >= post_dispatch_admission_line \
        || post_dispatch_admission_line >= metric_line )); then
  printf 'error: service lost dispatch -> probe -> admission -> metric order\n' >&2
  status=1
fi
recovery_retry_count="$(
  guard_count_matches 'bindingRecovery: \.consumed' "$service"
)"
if (( ${recovery_retry_count:-0} != 1 )); then
  printf 'error: popup binding recovery must retry the full transaction exactly once\n' >&2
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
  dimension_count="$(
    guard_count_matches "$required_dimension" "$request_admission" "$admission"
  )"
  if (( dimension_count == 0 )); then
    printf 'error: action invocation evidence lost the %s authority dimension\n' \
      "$required_dimension" >&2
    status=1
  fi
done
for request_dimension in 'runtimeBindingAtClick' 'profileID\(page\.tab\) == page\.resolvedProfileID' \
  'request\.resolvedProfileID == profileID' \
  'allTabs\(\)\.contains[[:space:]]*\{[[:space:]]*\$0 === page\.tab'; do
  dimension_count="$(
    guard_count_matches "$request_dimension" \
      "$request_admission" "$admission" -U
  )"
  if (( dimension_count == 0 )); then
    printf 'error: pre-resolution request lost exact %s validation\n' \
      "$request_dimension" >&2
    status=1
  fi
done

# The catalog keeps tombstoned per-record revisions.
record_revision_count="$(
  guard_count_matches 'func recordRevision\(for id: String\) -> UInt64' \
    "$collection"
)"
if (( record_revision_count == 0 )); then
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
check_loc "$dispatch" 100 "exact action dispatch"
check_loc "$authorizer" 320 "page-access authorizer"
check_loc "$collection" 160 "installed-extension collection"

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "extension action invocation admission boundary passed"
