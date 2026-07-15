#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

old='Sumi/Managers/ExtensionManager/ExtensionRuntimeLifecycleOwner.swift'
demand='Sumi/Managers/ExtensionManager/ExtensionRuntimeDemandCoordinator.swift'
transition='Sumi/Managers/ExtensionManager/ExtensionProfileRuntimeTransition.swift'
attachment='Sumi/Managers/ExtensionManager/ExtensionBrowserAttachmentAuthority.swift'
residency='Sumi/Managers/ExtensionManager/ExtensionContextResidencyOwner.swift'
settlement='Sumi/Managers/ExtensionManager/ExtensionContextSettlementOwner.swift'
installation='Sumi/Managers/ExtensionManager/ExtensionInstallationService.swift'
status=0

if [[ -e "$old" ]]; then
  echo 'error: extension runtime lifecycle god-object returned' >&2
  status=1
fi
for file in "$demand" "$transition" "$attachment" "$settlement"; do
  if [[ ! -f "$file" ]]; then
    echo "error: extension runtime lifecycle boundary missing: $file" >&2
    status=1
  fi
done
if (( status != 0 )); then
  exit "$status"
fi

tombstones="$(
  guard_capture_matches \
    '\bExtensionRuntimeLifecycleOwner\b|\bruntimeLifecycleOwner\b|\brequestExtensionRuntimeAndWait\b|\benabledPersistedExtensionEntities\b' \
    Sumi SumiTests
)"
if [[ -n "$tombstones" ]]; then
  printf 'error: deleted extension lifecycle surface returned:\n%s\n' \
    "$tombstones" >&2
  status=1
fi

mode_flag_hits="$(
  guard_capture_matches \
    '\ballowWithoutEnabledExtensions\b|\ballowWhenExtensionsNotLoaded\b|\bisExtensionSupportAvailable[[:space:]]*:' \
    Sumi SumiTests -g '*.swift'
)"
if [[ -n "$mode_flag_hits" ]]; then
  printf 'error: extension runtime regained a broad Bool mode API:\n%s\n' \
    "$mode_flag_hits" >&2
  status=1
fi
for operation in requestRuntimeIfDemanded requestRuntimeExplicitly; do
  operation_count="$(guard_count_matches "func $operation(" "$demand" -F)"
  if (( operation_count != 1 )); then
    echo "error: demand coordinator lost named operation: $operation" >&2
    status=1
  fi
done

role_bags="$(
  guard_capture_matches \
    '\bstruct (Dependencies|Actions|Environment)\b|\bSwiftData\b|\bBrowserManager\b|\bExtensionManager\s*[?!:]' \
    "$demand" "$transition"
)"
if [[ -n "$role_bags" ]]; then
  printf 'error: lifecycle role regained a root/bag/persistence reach-through:\n%s\n' \
    "$role_bags" >&2
  status=1
fi
fabricated_profile_hits="$(
  guard_capture_matches '\?\? UUID\(\)' "$demand" "$transition"
)"
if [[ -n "$fabricated_profile_hits" ]]; then
  echo 'error: lifecycle role fabricates profile authority' >&2
  status=1
fi
demand_publication_hits="$(
  guard_capture_matches \
    'extensionsLoaded\s*=|markRuntimePublicationReady|reconcile(Profile)?|runtimeReconciler' \
    "$demand"
)"
if [[ -n "$demand_publication_hits" ]]; then
  echo 'error: demand coordinator can publish or reconcile runtime' >&2
  status=1
fi
profile_query_count="$(
  guard_count_matches 'runtimeProfileID: @MainActor () -> UUID?' "$demand" -F
)"
broad_runtime_hits="$(
  guard_capture_matches 'ExtensionManagerRuntime' "$demand" -F
)"
if (( profile_query_count == 0 )) || [[ -n "$broad_runtime_hits" ]]; then
  echo 'error: demand coordinator lacks narrow fallback-profile query' >&2
  status=1
fi

for proof in \
  'pendingReconciliation?.cancel()' \
  'precondition(revision < UInt64.max' \
  'await Task.yield()' \
  'guard isCurrent(receipt) else { return }' \
  'settleImmediately(_ receipt: Receipt)' \
  '.webExtensionController === controller'; do
  transition_proof_count="$(guard_count_matches "$proof" "$transition" -F)"
  if (( transition_proof_count == 0 )); then
    echo "error: profile transition lacks exact deferred authority: $proof" >&2
    status=1
  fi
done
base_rebinding_count="$(
  guard_count_matches \
    'webViewConfiguration.webExtensionController =' "$transition" -F
)"
if (( base_rebinding_count == 0 )); then
  echo 'error: profile transition does not rebind the base WebView configuration' >&2
  status=1
fi

for proof in \
  'context(ifCurrent: receipt)' \
  'controller(ifCurrent: receipt)' \
  'loadedContext.context.isLoaded' \
  '$0.id == receipt.key.extensionId && $0.isEnabled' \
  'markPublicationReady()'; do
  settlement_proof_count="$(guard_count_matches "$proof" "$settlement" -F)"
  if (( settlement_proof_count == 0 )); then
    echo "error: runtime publication settlement lacks exact proof: $proof" >&2
    status=1
  fi
done
commit_line="$(
  guard_capture_matches 'recordTransaction.commitCandidate\(' "$installation" \
    | cut -d: -f1 | head -n1
)"
settle_line="$(
  guard_capture_matches 'runtimeActivation.settlePublication\(' "$installation" \
    | cut -d: -f1 | head -n1
)"
if [[ -z "$commit_line" || -z "$settle_line" ]] \
    || (( settle_line <= commit_line )); then
  echo 'error: install publication can settle before record commit' >&2
  status=1
fi

demand_loc="$(wc -l < "$demand")"
transition_loc="$(wc -l < "$transition")"
demand_fields="$(guard_count_matches '^    private let ' "$demand")"
transition_fields="$(guard_count_matches '^    private let ' "$transition")"
if (( demand_loc > 120 || demand_fields > 7 )); then
  echo "error: runtime demand role grew beyond 120 LOC / 7 fields ($demand_loc / $demand_fields)" >&2
  status=1
fi
if (( transition_loc > 180 || transition_fields > 11 )); then
  echo "error: profile transition grew beyond 180 LOC / 11 fields ($transition_loc / $transition_fields)" >&2
  status=1
fi

if (( status != 0 )); then
  exit "$status"
fi

echo 'extension runtime lifecycle boundary guardrail passed'
