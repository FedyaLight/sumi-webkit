#!/usr/bin/env bash
# Native-messaging delegate callbacks (sendMessage / connectUsing) must prove
# exact controller/context authority through typed
# ExtensionControllerCallbackEvidence before any counter, wake scheduling,
# relay materialization or port registration, and must revalidate that
# evidence when scheduled tasks start, after awaits, before external effects
# and before reply/completion settlement. This guard keeps the boundary from
# regressing to context-only routing, recomputed identity, fallback wake keys
# or bare ObjectIdentifier port lifetime.
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

bridge='Sumi/Managers/ExtensionManager/ExtensionControllerDelegateBridge.swift'
send_settlement='Sumi/Managers/ExtensionManager/ExtensionNativeMessageSendSettlement.swift'
connect_settlement='Sumi/Managers/ExtensionManager/ExtensionNativePortConnectionSettlement.swift'
port_registry='Sumi/Managers/ExtensionManager/ExtensionNativeMessagingPortRegistry.swift'
wake_coordinator='Sumi/Managers/ExtensionManager/ExtensionBackgroundWakeCoordinator.swift'
wake_owner='Sumi/Managers/ExtensionManager/ExtensionNativeMessagingBackgroundWakeOwner.swift'
background_state='Sumi/Managers/ExtensionManager/ExtensionBackgroundRuntimeStateOwner.swift'
relay_connection='Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingConnection.swift'
send_flow='Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingSendRelayFlow.swift'
connect_flow='Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortConnectRelayFlow.swift'

for file in "$bridge" "$send_settlement" "$connect_settlement" "$port_registry" \
  "$wake_coordinator" "$wake_owner" "$background_state" "$relay_connection" "$send_flow" \
  "$connect_flow"; do
  if [[ ! -f "$file" ]]; then
    printf 'error: native-messaging callback admission boundary missing: %s\n' "$file" >&2
    status=1
  fi
done

# The retired context-only routing owner must not return under any name.
routing_owner_hits="$(
  guard_capture_matches \
    'ExtensionNativeMessagingRoutingOwner|nativeMessagingRoutingOwner' \
    Sumi SumiTests -g '*.swift'
)"
record_scan_matches "retired native-messaging routing owner surface returned" \
  "$routing_owner_hits"

# Both native-messaging delegate callbacks capture typed evidence before any
# effect. The count is scoped to the native-messaging section of the bridge;
# the permission guard owns the permission-prompt section.
capture_count="$(
  awk '
    /\/\/ MARK: - Native Messaging/ { section = 1; next }
    /\/\/ MARK: -/ { section = 0 }
    section && /coreRoutes\.callbackAdmission\.capture\(/ { count += 1 }
    END { print count + 0 }
  ' "$bridge"
)"
if (( ${capture_count:-0} != 2 )); then
  printf 'error: bridge must capture callback evidence in exactly the two native-messaging callbacks (found %s)\n' \
    "${capture_count:-0}" >&2
  status=1
fi

# Settlements accept only typed evidence — the context-only callback API and
# any stored manager root must not return.
context_param_hits="$(
  guard_capture_matches \
    'for extensionContext: WKWebExtensionContext|weak var manager' \
    "$send_settlement" "$connect_settlement"
)"
record_scan_matches \
  "context-only API or stored manager root returned to native-messaging settlement" \
  "$context_param_hits"

evidence_identity_count="$(
  guard_count_matches 'evidence\.extensionID|evidence\.profileID' \
    "$send_settlement" "$connect_settlement"
)"
if (( ${evidence_identity_count:-0} < 4 )); then
  printf 'error: native-messaging settlements no longer derive identity from captured evidence (%s < 4)\n' \
    "${evidence_identity_count:-0}" >&2
  status=1
fi

# Identity must never be recomputed from mutable context/controller state
# after capture, and no ObjectIdentifier fallback identity may appear in the
# settlements.
identity_recompute_hits="$(
  guard_capture_matches \
    'extensionID\(for:|profileId\(for:|contextIdentity\(for:|uniqueIdentifier|ObjectIdentifier\(' \
    "$send_settlement" "$connect_settlement"
)"
record_scan_matches \
  "native-messaging settlement recomputes identity or uses fallback identity" \
  "$identity_recompute_hits"

# The callback-admitted wake derives its key only from captured evidence:
# the evidence-based scheduler must exist, the context-based variant must
# not return, and the ObjectIdentifier fallback key must never reach the
# native-messaging wake path.
evidence_scheduler_count="$(
  guard_count_matches \
    'func scheduleNativeMessagingBackgroundWake\(\s*evidence: ExtensionControllerCallbackEvidence,\s*admission: ExtensionControllerCallbackAdmission' \
    "$wake_coordinator" -U
)"
if (( evidence_scheduler_count == 0 )); then
  printf 'error: evidence-admitted native-messaging wake scheduler is missing\n' >&2
  status=1
fi
context_wake_hits="$(
  guard_capture_matches \
    'scheduleNativeMessagingBackgroundWake\(\s*for' Sumi -g '*.swift' -U
)"
record_scan_matches "context-based native-messaging wake scheduling returned" \
  "$context_wake_hits"
wake_fallback_hits="$(
  guard_capture_matches 'context:\\\(ObjectIdentifier' \
    "$send_settlement" "$connect_settlement" "$wake_owner"
)"
record_scan_matches "ObjectIdentifier fallback wake key reached the callback path" \
  "$wake_fallback_hits"

# Scheduled wakes revalidate evidence at task start and before the load
# effect, and stale scheduled entries are superseded without letting the
# stale task remove the newer wake.
wake_revalidation_count="$(
  guard_count_matches 'admission\.isCurrent\(evidence\)' "$wake_coordinator"
)"
if (( ${wake_revalidation_count:-0} < 3 )); then
  printf 'error: callback-admitted wake lost pre-task/pre-load revalidation (%s < 3)\n' \
    "${wake_revalidation_count:-0}" >&2
  status=1
fi
wake_currency_count="$(
  guard_count_matches 'isCurrent: @escaping @MainActor \(\) -> Bool' "$wake_owner"
)"
if (( wake_currency_count == 0 )); then
  printf 'error: wake owner lost currency-aware scheduled-entry supersession\n' >&2
  status=1
fi
post_await_validation_count="$(
  guard_count_matches \
    'try await loadBackgroundContent\(\)[\s\S]{0,300}guard isCurrent\(\), self\.wakeTasks\[wakeKey\]\?\.token == token' \
    "$background_state" -U
)"
if (( post_await_validation_count == 0 )); then
  printf 'error: background state machine lost post-await authority/token validation\n' >&2
  status=1
fi

# Settlement-level admission: each settlement revalidates evidence in its
# reply/completion path and threads the execution-admission seam into the
# relay so delayed external effects revalidate before they run.
for settlement in "$send_settlement" "$connect_settlement"; do
  settlement_revalidation="$(
    guard_count_matches 'admission\.isCurrent\(evidence\)' "$settlement"
  )"
  if (( ${settlement_revalidation:-0} < 2 )); then
    printf 'error: %s lost evidence revalidation (%s < 2)\n' \
      "$settlement" "${settlement_revalidation:-0}" >&2
    status=1
  fi
  execution_admission_count="$(
    guard_count_matches \
      'executionAdmission: \{ \[admission\] in admission\.isCurrent\(evidence\) \}' \
      "$settlement"
  )"
  if (( execution_admission_count == 0 )); then
    printf 'error: %s no longer passes exact execution admission into the relay\n' \
      "$settlement" >&2
    status=1
  fi
done

# The relay checks execution admission at the delayed-task start, before the
# adapter reply settles, around companion routing, before session creation,
# around registration and in the adapter connect completion.
relay_admission_count="$(
  guard_count_matches 'executionAdmission\(\)' \
    "$relay_connection" "$send_flow" "$connect_flow"
)"
if (( ${relay_admission_count:-0} < 6 )); then
  printf 'error: relay flows lost execution-admission checks before external effects (%s < 6)\n' \
    "${relay_admission_count:-0}" >&2
  status=1
fi

# The registration claim must be able to refuse a stale callback and stop
# the connect tail.
registration_claim_count="$(
  guard_count_matches \
    'registerHandler: \(SumiNativeMessagingPortSession\) -> Bool' "$connect_flow"
)"
if (( registration_claim_count == 0 )); then
  printf 'error: port registration lost its refusable claim boundary\n' >&2
  status=1
fi

# Port registry entries carry a weak physical-port witness plus a monotonic
# claim token, and unregister validates both before mutating.
for required_registry_shape in \
  'weak var portWitness: AnyObject\?' \
  'claimToken: UInt64' \
  'entry\.claimToken == claimToken' \
  'entry\.portWitness === port' \
  'entry\.handler === handler'; do
  registry_shape_count="$(
    guard_count_matches "$required_registry_shape" "$port_registry"
  )"
  if (( registry_shape_count == 0 )); then
    printf 'error: port registry lost exact lifetime shape: %s\n' \
      "$required_registry_shape" >&2
    status=1
  fi
done
duplicate_port_rejection_count="$(
  guard_count_matches \
    'if let existing = entriesByPortKey\[portKey\],\s*existing\.portWitness === port \{\s*return nil' \
    "$port_registry" -U
)"
if (( duplicate_port_rejection_count == 0 )); then
  printf 'error: port registry no longer rejects a second session for one physical port\n' >&2
  status=1
fi

# No universal callback hub, closure-bag or manager-root wrapper may replace
# the two narrow settlements.
# Scoped to the extension surface this guard governs: "CallbackCoordinator" is
# also the SwiftUI NSViewRepresentable idiom, unrelated to native messaging.
callback_hub_hits="$(
  guard_capture_matches \
    'NativeMessagingCallbackHub|NativeMessagingDependencies|NativeMessagingActions|CallbackCoordinator' \
    Sumi/Managers/ExtensionManager -g '*.swift'
)"
record_scan_matches "universal native-messaging callback hub appeared" "$callback_hub_hits"

# Size ratchets: the settlements stay narrow single-callback boundaries.
send_settlement_lines="$(wc -l < "$send_settlement" | tr -d ' ')"
if (( send_settlement_lines > 170 )); then
  printf 'error: send settlement grew beyond one callback family (%s > 170 LOC)\n' \
    "$send_settlement_lines" >&2
  status=1
fi
connect_settlement_lines="$(wc -l < "$connect_settlement" | tr -d ' ')"
if (( connect_settlement_lines > 190 )); then
  printf 'error: connect settlement grew beyond one callback family (%s > 190 LOC)\n' \
    "$connect_settlement_lines" >&2
  status=1
fi
port_registry_lines="$(wc -l < "$port_registry" | tr -d ' ')"
if (( port_registry_lines > 150 )); then
  printf 'error: port registry grew beyond exact claim bookkeeping (%s > 150 LOC)\n' \
    "$port_registry_lines" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  exit "$status"
fi

echo "extension native messaging callback admission boundary passed"
