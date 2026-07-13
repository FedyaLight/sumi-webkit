#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_files=(
  Sumi/Managers/ExtensionManager/ExtensionRuntimeMutationRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionBackgroundRuntimeStateOwner.swift
  Sumi/Managers/ExtensionManager/ExtensionContextErrorObservation.swift
  Sumi/Managers/ExtensionManager/ExtensionContextLoadRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionContextRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextAuthority.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextFinalizer.swift
  Sumi/Managers/ExtensionManager/ExtensionEnabledRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionInstallationRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRecovery.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRollback.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeLoader.swift
  Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeActivityCancellation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeBookkeepingReset.swift
  Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeRelease.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeShutdown.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeTabRebuildPlan.swift
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    printf 'error: extension runtime retirement boundary missing: %s\n' "$file" >&2
    exit 1
  }
done

for retired in \
  Sumi/Managers/ExtensionManager/ExtensionRuntimeStateResetOwner.swift \
  Sumi/Managers/ExtensionManager/ExtensionRuntimeTeardownOwner.swift \
  Sumi/Managers/ExtensionManager/ExtensionErrorObservationOwner.swift; do
  [[ ! -e "$retired" ]] || {
    printf 'error: retired extension runtime god surface returned: %s\n' "$retired" >&2
    exit 1
  }
done

core_files=(
  Sumi/Managers/ExtensionManager/ExtensionContextErrorObservation.swift
  Sumi/Managers/ExtensionManager/ExtensionContextLoadRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionContextRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextAuthority.swift
  Sumi/Managers/ExtensionManager/ExtensionLoadedContextFinalizer.swift
  Sumi/Managers/ExtensionManager/ExtensionEnabledRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionInstallationRuntimeActivation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRecovery.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeRollback.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeLoader.swift
  Sumi/Managers/ExtensionManager/ExtensionScopedRuntimeRetirement.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeActivityCancellation.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeBookkeepingReset.swift
  Sumi/Managers/ExtensionManager/ExtensionControllerRuntimeRelease.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeMutationRegistry.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeShutdown.swift
  Sumi/Managers/ExtensionManager/ExtensionRuntimeTabRebuildPlan.swift
  Sumi/Managers/ExtensionManager/ExtensionBackgroundRuntimeStateOwner.swift
)

if rg -n 'struct (Dependencies|Actions)|\bmanager:[[:space:]]*ExtensionManager\b|init\(manager:' \
    "${core_files[@]}"; then
  printf 'error: extension retirement core regained a manager-root or closure bag\n' >&2
  exit 1
fi

if rg -n 'tearDownExtensionRuntime\(|resetRuntimeState\(|removeUIState:|releaseController:' \
    Sumi SumiTests; then
  printf 'error: retired boolean/reset runtime API returned\n' >&2
  exit 1
fi

for required_symbol in \
  'func beginTerminal() -> ExtensionRuntimeTerminalLease?' \
  'func beginTerminalIfNoScopedMutations()' \
  'func enterIrreversiblePhase(' \
  'func runWhenTerminalAdmissionAvailable(' \
  'func admitsExtensionGlobalRollback(' \
  'func hasCompetingClaim(' \
  'func admitsLoad(' \
  'func hasCompetingScopedMutation(' \
  'case mutation(ExtensionRuntimeMutationLease)' \
  'case terminal(ExtensionRuntimeTerminalLease)' \
  'case retirementInProgress' \
  'case mutationInProgress' \
  'case contextsRemaining' \
  'struct ExtensionRuntimeTransactionFailure' \
  'enum ExactRollbackDisposition' \
  'enum SharedCleanupDisposition' \
  'enum SharedCleanupBlocker' \
  'func cleanUpAfterQuiescentRollback(' \
  'func cancelWakePreservingRuntimeState(' \
  'let tabRebuildPlan: ExtensionRuntimeTabRebuildPlan'; do
  if ! rg -Fq "$required_symbol" "${required_files[@]}"; then
    printf 'error: extension retirement authority missing: %s\n' \
      "$required_symbol" >&2
    exit 1
  fi
done

if rg -n 'ExtensionRuntimeLoader\.Environment|retireRuntimeState\(|finalizeAlreadyLoadedRuntime\(|activateInstalledExtension\(|recoverEnabledRuntime\(' \
    Sumi/Managers/ExtensionManager/ExtensionRuntimeLoader.swift; then
  printf 'error: enabled runtime loader regained install/retirement/recovery god responsibilities\n' >&2
  exit 1
fi

shutdown_file='Sumi/Managers/ExtensionManager/ExtensionRuntimeShutdown.swift'
if ! rg -Uq \
    'func shutDown\([[:space:]]*reason: String,[[:space:]]*runtime capturedRuntime: ExtensionManagerRuntime,[[:space:]]*activityResources: ExtensionRuntimeActivityCancellation\.Resources,[[:space:]]*isExtensionSupportAvailable: Bool,[[:space:]]*admission: Admission = \.forced[[:space:]]*\) -> Result' \
    "$shutdown_file"; then
  printf 'error: exact terminal extension runtime shutdown API missing\n' >&2
  exit 1
fi

installation_publish_body="$(
  sed -n \
    '/private func publish(_ record: InstalledExtension)/,/^    }/p' \
    Sumi/Managers/ExtensionManager/ExtensionInstallationService.swift
)"
lifecycle_publish_body="$(
  sed -n \
    '/private func publish(/,/^    }/p' \
    Sumi/Managers/ExtensionManager/InstalledExtensionLifecycleService.swift
)"
if rg -n 'Task\.yield\(\)' \
    <<<"${installation_publish_body}"$'\n'"${lifecycle_publish_body}"; then
  printf 'error: extension lifecycle catalog publication regained a yielded lost-update window\n' >&2
  exit 1
fi

required_test_classes=(
  'SumiTests/ExtensionContextErrorObservationTests.swift|ExtensionContextErrorObservationTests'
  'SumiTests/ExtensionContextLoadRegistryTests.swift|ExtensionContextLoadRegistryTests'
  'SumiTests/ExtensionContextRetirementTests.swift|ExtensionContextRetirementTests'
  'SumiTests/ExtensionRuntimeMutationRegistryTests.swift|ExtensionRuntimeMutationRegistryTests'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|ExtensionRuntimeRecoveryTests'
  'SumiTests/ExtensionRuntimeTabRebuildPlanTests.swift|ExtensionRuntimeTabRebuildPlanTests'
  'SumiTests/ExtensionRuntimeShutdownTests.swift|ExtensionRuntimeShutdownTests'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|ExtensionScopedRuntimeRetirementTests'
)

for specification in "${required_test_classes[@]}"; do
  test_file="${specification%%|*}"
  test_class="${specification#*|}"
  if [[ ! -f "$test_file" ]] \
      || ! rg -q \
        "^[[:space:]]*final class ${test_class}:" \
        "$test_file"; then
    printf 'error: extension retirement test class missing: %s (%s)\n' \
      "$test_class" "$test_file" >&2
    exit 1
  fi
done

required_regressions=(
  'SumiTests/ExtensionContextRetirementTests.swift|testReentrantRetirementDoesNotUnloadSameBindingTwice'
  'SumiTests/ExtensionContextRetirementTests.swift|testBoundContextNotYetLoadedRetiresWithoutCallingUnload'
  'SumiTests/ExtensionContextRetirementTests.swift|testUnloadFailurePreservesAuthoritativeBinding'
  'SumiTests/ExtensionContextRetirementTests.swift|testExactRollbackReportsReplacementSeparatelyFromUnloadFailure'
  'SumiTests/ExtensionContextRetirementTests.swift|testExactRollbackReportsContextStillLoadedAfterUnloadFailure'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testPartialDisableRecoversMissingAndStillBoundProfiles'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testRecoveryFailureIsReturnedByLifecycleInsteadOfBeingSwallowed'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testFailedEnabledPackageReplacementRestoresBothRuntimeProfiles'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testFailedEnableWithUnloadFailurePreservesEnabledLiveBinding'
  'SumiTests/ExtensionRuntimeRecoveryTests.swift|testNonQuiescentPackageReplacementPreservesCandidateAndLiveRuntime'
  'SumiTests/ExtensionRuntimeShutdownTests.swift|testIncompleteShutdownKeepsTerminalAdmissionSealedUntilSuccessfulRetry'
  'SumiTests/ExtensionRuntimeShutdownTests.swift|testIrreversibleMutationDefersShutdownWithoutCancellingRuntime'
  'SumiTests/ExtensionRuntimeShutdownTests.swift|testSupersededShutdownPreservesBookkeepingControllerAndNewTerminalSeal'
  'SumiTests/ExtensionRuntimeMutationRegistryTests.swift|testSupersededTerminalLeaseCannotReopenCurrentTerminalSeal'
  'SumiTests/ExtensionRuntimeMutationRegistryTests.swift|testIrreversibleMutationBlocksForcedAndIdleTerminalAdmission'
  'SumiTests/ExtensionRuntimeMutationRegistryTests.swift|testIdleTerminalAdmissionDoesNotSupersedeUnrelatedMutation'
  'SumiTests/ExtensionRuntimeMutationRegistryTests.swift|testTerminalAdmissionWaiterRunsAfterLastIrreversibleLease'
  'SumiTests/SumiExtensionsModuleResidentDemandTests.swift|testDisabledModuleRetriesShutdownAfterIrreversibleMutationFinishes'
  'SumiTests/ExtensionContextLoadRegistryTests.swift|testExtensionGlobalRollbackRejectsConcurrentOtherProfileClaim'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testRetirementRejectsWrongAndStaleMutationOrTerminalAdmission'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testRollbackRejectsConcurrentOtherProfileLoadBeforeSharedCleanup'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testExactRollbackSucceedsWhileSiblingProfilePreservesSharedState'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testTerminalSupersessionWithoutCandidateAuthorityPermitsExternalRollback'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testCompetingMutationWithoutBindingBlocksExternalRollback'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testPartialMultiProfileRetirementReportsContextsRemainingWithoutSharedCleanup'
  'SumiTests/ExtensionScopedRuntimeRetirementTests.swift|testTerminalAdmissionDuringUnloadSupersedesOuterMutationWithoutSharedCleanup'
)

for specification in "${required_regressions[@]}"; do
  test_file="${specification%%|*}"
  test_function="${specification#*|}"
  if ! rg -q "^[[:space:]]*func ${test_function}\\(" "$test_file"; then
    printf 'error: extension retirement regression missing: %s (%s)\n' \
      "$test_function" "$test_file" >&2
    exit 1
  fi
done

deferred_shutdown_body="$(
  sed -n \
    '/private func scheduleRuntimeTeardownRetry(/,/^    }/p' \
    Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift
)"
if rg -n 'Timer|asyncAfter|Task\.sleep' <<<"$deferred_shutdown_body"; then
  printf 'error: deferred extension shutdown regained polling or timers\n' >&2
  exit 1
fi

options_window_tests='SumiTests/ExtensionOptionsWindowServiceTests.swift'
for replacement_cleanup_test in \
  'testCleanupOfStaleWindowPreservesRegisteredReplacementForSameExtension' \
  'testStaleWebViewCloseWithoutWindowPreservesRegisteredReplacement'; do
  if ! rg -q \
      "^[[:space:]]*func ${replacement_cleanup_test}\(" \
      "$options_window_tests"; then
    printf 'error: extension retirement regression missing: %s (%s)\n' \
      "$replacement_cleanup_test" "$options_window_tests" >&2
    exit 1
  fi
done

echo 'extension runtime retirement boundary passed'
