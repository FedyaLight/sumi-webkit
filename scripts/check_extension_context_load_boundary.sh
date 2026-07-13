#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

old_loader='Sumi/Managers/ExtensionManager/ExtensionRuntimeContextLoader.swift'
loader='Sumi/Managers/ExtensionManager/ExtensionContextLoader.swift'
transaction='Sumi/Managers/ExtensionManager/ExtensionContextControllerTransaction.swift'
preparation='Sumi/Managers/ExtensionManager/ExtensionContextPreparation.swift'
source_cache='Sumi/Managers/ExtensionManager/WebExtensionRuntimeSourceCache.swift'
storage='Sumi/Managers/ExtensionManager/WebExtensionRuntimeStoragePreparation.swift'
authority='Sumi/Managers/ExtensionManager/ExtensionLoadedContextAuthority.swift'
diagnostics='Sumi/Managers/ExtensionManager/ExtensionRuntimeDiagnostics.swift'
manager='Sumi/Managers/ExtensionManager/ExtensionManager.swift'

required_files=(
  "$loader"
  "$transaction"
  "$preparation"
  "$source_cache"
  "$storage"
  "$authority"
)
for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    printf 'error: extension context-load role missing: %s\n' "$file" >&2
    exit 1
  }
done

if [[ -e "$old_loader" ]] \
    || rg -n '\bExtensionRuntimeContextLoader\b|\bruntimeContextLoader\b' \
      Sumi SumiTests >/dev/null; then
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
if rg -n '\bExtensionManager\b|\bBrowserManager\b|struct (Dependencies|Actions)\b|init\(manager:' \
    "${root_free_roles[@]}"; then
  printf 'error: context-load role regained a manager-root or closure bag\n' >&2
  exit 1
fi

if rg -n -P '^\s*(private\s+)?(weak\s+)?(var|let)\s+\w+\s*:\s*(any\s+)?[A-Za-z0-9_]+Owner\??\s*$' \
    "$loader" "$transaction" "$source_cache" "$storage"; then
  printf 'error: context-load orchestration stores an Owner surface\n' >&2
  exit 1
fi
if rg -n '\b[A-Za-z0-9_]+Owner\b' "$loader" "$transaction"; then
  printf 'error: context load/transaction reached through an Owner surface\n' >&2
  exit 1
fi

if ! rg -Fq 'private let admission: ExtensionContextLoadAdmission' \
    "$source_cache" \
    || rg -n 'ExtensionLoadedContextAuthority' "$source_cache"; then
  printf 'error: source cache regained destructive context rollback authority\n' >&2
  exit 1
fi
if ! rg -Fq 'admission: contextLoadAdmission' "$manager" \
    || ! rg -Fq 'WebExtensionRuntimeSourceCache(admission: contextLoadAdmission)' \
      "$manager"; then
  printf 'error: source publication and loaded-context authority no longer share narrow admission\n' >&2
  exit 1
fi

for required_loader_call in \
  'sourceCache.resolve(' \
  'contextPreparation.prepare(' \
  'storage.prepare()' \
  'controllerTransaction.load('; do
  if ! rg -Fq "$required_loader_call" "$loader"; then
    printf 'error: context loader lost explicit phase: %s\n' \
      "$required_loader_call" >&2
    exit 1
  fi
done

for required_transaction_call in \
  'profileRuntime.setContext(' \
  'controller.load(context)' \
  'rollback.rollBack(' \
  'rollbackResult.externalStateDisposition != .rollbackAllowed'; do
  if ! rg -Fq "$required_transaction_call" "$transaction"; then
    printf 'error: controller transaction lost exact mutation/compensation: %s\n' \
      "$required_transaction_call" >&2
    exit 1
  fi
done

for disposition in \
  rollbackAllowed \
  preserveForExactRuntime \
  preserveForReplacement \
  preserveForActiveBinding \
  preserveForCompetingTransaction \
  preserveUntilSharedCleanup; do
  if ! rg -Fq "case $disposition" "$authority"; then
    printf 'error: typed external rollback disposition missing: %s\n' \
      "$disposition" >&2
    exit 1
  fi
done
if rg -n 'permitsExternalStateRollback' Sumi SumiTests >/dev/null; then
  printf 'error: external rollback authority flattened back to Bool\n' >&2
  exit 1
fi

diagnostic_body="$(
  sed -n '/func traceNativeMessagingContextBinding(/,/^    }/p' "$diagnostics"
)"
if rg -n '\bmanager\b|ExtensionManager' <<<"$diagnostic_body"; then
  printf 'error: native-messaging binding diagnostics regained manager-root lookup\n' >&2
  exit 1
fi

if rg -n 'Timer|Task\.sleep|asyncAfter|DispatchSource' \
    "$loader" "$transaction" "$source_cache" "$storage"; then
  printf 'error: context-load path gained polling/timer idle work\n' >&2
  exit 1
fi
if ! rg -Fq 'capabilitySnapshot: @autoclosure () ->' "$storage"; then
  printf 'error: disabled storage diagnostics regained eager manifest analysis\n' >&2
  exit 1
fi

required_regressions=(
  'SumiTests/WebExtensionRuntimeSourceCacheTests.swift|testConcurrentSameKeyCoalescesOneSourceCreation'
  'SumiTests/WebExtensionRuntimeSourceCacheTests.swift|testCancellingSoleWaiterPromptlyReleasesPendingPublication'
  'SumiTests/WebExtensionRuntimeSourceCacheTests.swift|testRemoveWhileSuspendedCannotAdoptNewSameKeyPublication'
  'SumiTests/ExtensionContextPreparationTests.swift|testStoredDecisionOverridesManifestGrantDuringPreparation'
  'SumiTests/WebExtensionRuntimeStoragePreparationTests.swift|testPrepareUsesExactControllerAndRuntimeIdentifiers'
  'SumiTests/ExtensionRuntimeTransactionFailureTests.swift|testReentrantPolicyPublicationStopsBeforeStorageMutation'
  'SumiTests/ExtensionRuntimeTransactionFailureTests.swift|testReplacementBindingPropagatesExternalPreservationAuthority'
  'SumiTests/ExtensionRuntimeTransactionFailureTests.swift|testSiblingBindingPropagatesActiveBindingPreservationAuthority'
  'SumiTests/ExtensionRuntimeTransactionFailureTests.swift|testCompetingMutationPropagatesTransactionPreservationAuthority'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testFailedEnableWithUnloadFailurePreservesEnabledLiveBinding'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testNonQuiescentPackageReplacementPreservesCandidateAndLiveRuntime'
)
for specification in "${required_regressions[@]}"; do
  test_file="${specification%%|*}"
  test_function="${specification#*|}"
  if [[ ! -f "$test_file" ]] \
      || ! rg -q "^[[:space:]]*func ${test_function}\\(" "$test_file"; then
    printf 'error: context-load regression missing: %s (%s)\n' \
      "$test_function" "$test_file" >&2
    exit 1
  fi
done

printf 'extension context-load boundary guard passed\n'
