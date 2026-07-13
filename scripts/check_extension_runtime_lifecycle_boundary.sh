#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

old='Sumi/Managers/ExtensionManager/ExtensionRuntimeLifecycleOwner.swift'
demand='Sumi/Managers/ExtensionManager/ExtensionRuntimeDemandCoordinator.swift'
transition='Sumi/Managers/ExtensionManager/ExtensionProfileRuntimeTransition.swift'
attachment='Sumi/Managers/ExtensionManager/ExtensionManager+BrowserRuntimeAttachment.swift'
residency='Sumi/Managers/ExtensionManager/ExtensionContextResidencyOwner.swift'
installation='Sumi/Managers/ExtensionManager/ExtensionInstallationService.swift'
tests='SumiTests/ExtensionRuntimeLifecycleBoundaryTests.swift'
status=0

if [[ -e "$old" ]]; then
  echo 'error: extension runtime lifecycle god-object returned' >&2
  status=1
fi
for file in "$demand" "$transition" "$attachment" "$tests"; do
  if [[ ! -f "$file" ]]; then
    echo "error: extension runtime lifecycle boundary missing: $file" >&2
    status=1
  fi
done
if (( status != 0 )); then
  exit "$status"
fi

tombstones="$(
  rg -n '\bExtensionRuntimeLifecycleOwner\b|\bruntimeLifecycleOwner\b|\brequestExtensionRuntimeAndWait\b|\benabledPersistedExtensionEntities\b' \
    Sumi SumiTests || true
)"
if [[ -n "$tombstones" ]]; then
  printf 'error: deleted extension lifecycle surface returned:\n%s\n' \
    "$tombstones" >&2
  status=1
fi

role_bags="$(
  rg -n '\bstruct (Dependencies|Actions|Environment)\b|\bSwiftData\b|\bBrowserManager\b|\bExtensionManager\s*[?!:]' \
    "$demand" "$transition" || true
)"
if [[ -n "$role_bags" ]]; then
  printf 'error: lifecycle role regained a root/bag/persistence reach-through:\n%s\n' \
    "$role_bags" >&2
  status=1
fi
if rg -n '\?\? UUID\(\)' "$demand" "$transition" >/dev/null; then
  echo 'error: lifecycle role fabricates profile authority' >&2
  status=1
fi
if rg -n 'extensionsLoaded\s*=|markRuntimePublicationReady|reconcile(Profile)?|runtimeReconciler' \
    "$demand" >/dev/null; then
  echo 'error: demand coordinator can publish or reconcile runtime' >&2
  status=1
fi
if ! rg -Fq 'runtimeProfileID: @MainActor () -> UUID?' "$demand" \
    || rg -Fq 'ExtensionManagerRuntime' "$demand"; then
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
  if ! rg -Fq "$proof" "$transition"; then
    echo "error: profile transition lacks exact deferred authority: $proof" >&2
    status=1
  fi
done
if ! rg -Fq 'webViewConfiguration.webExtensionController =' "$transition"; then
  echo 'error: profile transition does not rebind the base WebView configuration' >&2
  status=1
fi

for proof in \
  'context(ifCurrent: receipt)' \
  'controller(ifCurrent: receipt)' \
  'loadedContext.context.isLoaded' \
  '$0.id == receipt.key.extensionId && $0.isEnabled' \
  'dependencies.markRuntimePublicationReady()'; do
  if ! rg -Fq "$proof" "$residency"; then
    echo "error: runtime publication settlement lacks exact proof: $proof" >&2
    status=1
  fi
done
commit_line="$(rg -n 'recordTransaction.commitCandidate\(' "$installation" | cut -d: -f1 | head -n1)"
settle_line="$(rg -n 'runtimeActivation.settlePublication\(' "$installation" | cut -d: -f1 | head -n1)"
if [[ -z "$commit_line" || -z "$settle_line" ]] \
    || (( settle_line <= commit_line )); then
  echo 'error: install publication can settle before record commit' >&2
  status=1
fi

for test_name in \
  testNoDemandDoesNotProvisionControllerOrPublishRuntime \
  testNoDemandDoesNotSuspendExistingRuntimePublication \
  testUnsupportedDemandDoesNotProvisionOrPublishRuntime \
  testDemandWithoutAnyProfilePreservesFailedStateAndDoesNotProvision \
  testExplicitDemandIsStickyAndReusesLoadingController \
  testABATransitionRejectsStaleImmediateSettlementAndRebindsBaseConfiguration \
  testReadyRuntimeBecomesLoadingWhenTargetProfileLacksEnabledContext \
  testDeferredTransitionDoesNotRetainTransitionRole \
  testImmediateSettlementCancelsDeferredDuplicate \
  testCurrentEnabledLoadedContextPublishesRuntime \
  testSupersededLoadedContextDoesNotPublishRuntime; do
  if ! rg -Fq "func $test_name" "$tests"; then
    echo "error: lifecycle focused regression missing: $test_name" >&2
    status=1
  fi
done

demand_loc="$(wc -l < "$demand")"
transition_loc="$(wc -l < "$transition")"
demand_fields="$(rg -c '^    private let ' "$demand" || true)"
transition_fields="$(rg -c '^    private let ' "$transition" || true)"
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
