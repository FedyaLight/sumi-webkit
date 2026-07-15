#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

old_loader='Sumi/Managers/ExtensionManager/ExtensionRuntimeContextLoader.swift'
loader='Sumi/Managers/ExtensionManager/ExtensionContextLoader.swift'
transaction='Sumi/Managers/ExtensionManager/ExtensionContextControllerTransaction.swift'
preparation='Sumi/Managers/ExtensionManager/ExtensionContextPreparation.swift'
source_cache='Sumi/Managers/ExtensionManager/WebExtensionRuntimeSourceCache.swift'
storage='Sumi/Managers/ExtensionManager/WebExtensionRuntimeStoragePreparation.swift'
authority='Sumi/Managers/ExtensionManager/ExtensionLoadedContextAuthority.swift'
delegate_readiness='Sumi/Managers/ExtensionManager/ExtensionControllerDelegateReadiness.swift'
controller_provisioning='Sumi/Managers/ExtensionManager/ExtensionControllerProvisioningOwner.swift'
controller_release='Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeRelease.swift'
diagnostics='Sumi/Managers/ExtensionManager/ExtensionRuntimeDiagnostics.swift'
manager='Sumi/Managers/ExtensionManager/ExtensionManagerContextStateAssembly.swift'

required_files=(
  "$loader"
  "$transaction"
  "$preparation"
  "$source_cache"
  "$storage"
  "$authority"
  "$delegate_readiness"
)
for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    printf 'error: extension context-load role missing: %s\n' "$file" >&2
    exit 1
  }
done

retired_loader_hits="$(
  guard_capture_matches \
    '\bExtensionRuntimeContextLoader\b|\bruntimeContextLoader\b' \
    Sumi SumiTests
)"
if [[ -e "$old_loader" || -L "$old_loader" || -n "$retired_loader_hits" ]]; then
  printf 'error: deleted manager-root context loader returned\n' >&2
  exit 1
fi

root_free_roles=(
  "$loader"
  "$transaction"
  "$preparation"
  "$source_cache"
  "$storage"
)
root_reachthrough_hits="$(
  guard_capture_matches \
    '\bExtensionManager\b|\bBrowserManager\b|struct (Dependencies|Actions)\b|init\(manager:' \
    "${root_free_roles[@]}"
)"
if [[ -n "$root_reachthrough_hits" ]]; then
  printf '%s\n' "$root_reachthrough_hits" >&2
  printf 'error: context-load role regained a manager-root or closure bag\n' >&2
  exit 1
fi

owner_storage_hits="$(
  guard_capture_matches \
    '^\s*(private\s+)?(weak\s+)?(var|let)\s+\w+\s*:\s*(any\s+)?[A-Za-z0-9_]+Owner\??\s*$' \
    "$loader" "$transaction" "$source_cache" "$storage" -P
)"
if [[ -n "$owner_storage_hits" ]]; then
  printf '%s\n' "$owner_storage_hits" >&2
  printf 'error: context-load orchestration stores an Owner surface\n' >&2
  exit 1
fi
owner_reachthrough_hits="$(
  guard_capture_matches '\b[A-Za-z0-9_]+Owner\b' "$loader" "$transaction"
)"
if [[ -n "$owner_reachthrough_hits" ]]; then
  printf '%s\n' "$owner_reachthrough_hits" >&2
  printf 'error: context load/transaction reached through an Owner surface\n' >&2
  exit 1
fi

source_cache_admission_count="$(
  guard_count_matches \
    'private let admission: ExtensionContextLoadAdmission' "$source_cache" -F
)"
source_cache_authority_hits="$(
  guard_capture_matches 'ExtensionLoadedContextAuthority' "$source_cache"
)"
if (( source_cache_admission_count == 0 )) \
    || [[ -n "$source_cache_authority_hits" ]]; then
  printf 'error: source cache regained destructive context rollback authority\n' >&2
  exit 1
fi
shared_admission_wiring_count="$(
  guard_count_matches 'admission: admission' "$manager" -F
)"
source_cache_wiring_count="$(
  guard_count_matches \
    'WebExtensionRuntimeSourceCache\([[:space:]]*admission: admission' \
    "$manager" -U
)"
authority_wiring_count="$(
  guard_count_matches \
    'ExtensionLoadedContextAuthority\([^)]*admission: admission' \
    "$manager" -U
)"
if (( shared_admission_wiring_count < 2 \
      || source_cache_wiring_count == 0 \
      || authority_wiring_count == 0 )); then
  printf 'error: source publication and loaded-context authority no longer share narrow admission\n' >&2
  exit 1
fi

for required_loader_call in \
  'sourceCache.resolve(' \
  'contextPreparation.prepare(' \
  'storage.prepare()' \
  'controllerTransaction.load('; do
  required_loader_call_count="$(
    guard_count_matches "$required_loader_call" "$loader" -F
  )"
  if (( required_loader_call_count == 0 )); then
    printf 'error: context loader lost explicit phase: %s\n' \
      "$required_loader_call" >&2
    exit 1
  fi
done

for required_transaction_call in \
  'profileRuntime.setContext(' \
  'controller.load(context)' \
  'controllerDelegateReadiness.controllerDidBecomeReady(' \
  'rollback.rollBack(' \
  'rollbackResult.externalStateDisposition != .rollbackAllowed'; do
  required_transaction_call_count="$(
    guard_count_matches "$required_transaction_call" "$transaction" -F
  )"
  if (( required_transaction_call_count == 0 )); then
    printf 'error: controller transaction lost exact mutation/compensation: %s\n' \
      "$required_transaction_call" >&2
    exit 1
  fi
done

load_line="$(
  guard_capture_matches 'try controller.load(context)' "$transaction" -F \
    | cut -d: -f1
)"
readiness_line="$(
  guard_capture_matches \
    'controllerDelegateReadiness.controllerDidBecomeReady(' "$transaction" -F \
    | cut -d: -f1
)"
if [[ -z "$load_line" || -z "$readiness_line" ]] \
    || (( readiness_line <= load_line )); then
  printf 'error: controller delegate receipt is not consumed after successful WebKit load\n' >&2
  exit 1
fi
for readiness_proof in \
  'pendingByProfile[receipt.profileID] = receipt' \
  'lhs.revision == rhs.revision' \
  'lhs.controller === rhs.controller' \
  'profileRuntime.isCurrent(receipt)' \
  'pendingByProfile.removeAll()'; do
  readiness_proof_count="$(
    guard_count_matches "$readiness_proof" "$delegate_readiness" -F
  )"
  if (( readiness_proof_count == 0 )); then
    printf 'error: controller delegate readiness lost exact proof: %s\n' \
      "$readiness_proof" >&2
    exit 1
  fi
done
installed_receipt_count="$(
  guard_count_matches \
    'controllerDelegateReadiness.controllerInstalled(' "$controller_provisioning" -F
)"
cancel_receipt_count="$(
  guard_count_matches \
    'controllerDelegateReadiness.cancelAll()' "$controller_release" -F
)"
if (( installed_receipt_count == 0 || cancel_receipt_count == 0 )); then
  printf 'error: controller delegate receipt lost provisioning/release boundary\n' >&2
  exit 1
fi
cancel_line="$(
  guard_capture_matches \
    'controllerDelegateReadiness.cancelAll()' "$controller_release" -F \
    | cut -d: -f1
)"
release_line="$(
  guard_capture_matches 'webExtensionController = nil' "$controller_release" -F \
    | cut -d: -f1
)"
if [[ -z "$cancel_line" || -z "$release_line" ]] \
    || (( cancel_line >= release_line )); then
  printf 'error: pending delegate receipts are not cancelled before controller release\n' >&2
  exit 1
fi

for disposition in \
  rollbackAllowed \
  preserveForExactRuntime \
  preserveForReplacement \
  preserveForActiveBinding \
  preserveForCompetingTransaction \
  preserveUntilSharedCleanup; do
  disposition_count="$(
    guard_count_matches "case $disposition" "$authority" -F
  )"
  if (( disposition_count == 0 )); then
    printf 'error: typed external rollback disposition missing: %s\n' \
      "$disposition" >&2
    exit 1
  fi
done
flattened_authority_hits="$(
  guard_capture_matches 'permitsExternalStateRollback' Sumi SumiTests
)"
if [[ -n "$flattened_authority_hits" ]]; then
  printf 'error: external rollback authority flattened back to Bool\n' >&2
  exit 1
fi

diagnostic_body="$(
  sed -n '/func traceNativeMessagingContextBinding(/,/^    }/p' "$diagnostics"
)"
diagnostic_root_hits="$(
  guard_capture_matches '\bmanager\b|ExtensionManager' - <<<"$diagnostic_body"
)"
if [[ -n "$diagnostic_root_hits" ]]; then
  printf '%s\n' "$diagnostic_root_hits" >&2
  printf 'error: native-messaging binding diagnostics regained manager-root lookup\n' >&2
  exit 1
fi

idle_work_hits="$(
  guard_capture_matches 'Timer|Task\.sleep|asyncAfter|DispatchSource' \
    "$loader" "$transaction" "$source_cache" "$storage" \
    "$delegate_readiness" "$controller_provisioning"
)"
if [[ -n "$idle_work_hits" ]]; then
  printf '%s\n' "$idle_work_hits" >&2
  printf 'error: context-load path gained polling/timer idle work\n' >&2
  exit 1
fi
lazy_snapshot_count="$(
  guard_count_matches 'capabilitySnapshot: @autoclosure () ->' "$storage" -F
)"
if (( lazy_snapshot_count == 0 )); then
  printf 'error: disabled storage diagnostics regained eager manifest analysis\n' >&2
  exit 1
fi

printf 'extension context-load boundary guard passed\n'
