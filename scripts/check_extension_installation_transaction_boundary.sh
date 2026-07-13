#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
service="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationService.swift"
record="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationRecordTransaction.swift"
policy="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationFailurePolicy.swift"
settlement="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationFailureSettlement.swift"
identity="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationIdentityResolver.swift"
admission="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationAdmission.swift"
package="$root/Sumi/Managers/ExtensionManager/ExtensionPackageInstallTransaction.swift"
prepared_package="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationPackage.swift"
layout="$root/Sumi/Managers/ExtensionManager/ExtensionPackageLayout.swift"
maintenance="$root/Sumi/Managers/ExtensionManager/ExtensionPackageMaintenance.swift"
legacy_recovery="$root/Sumi/Managers/ExtensionManager/LegacyExtensionBackupRecovery.swift"
metadata_store="$root/Sumi/Managers/ExtensionManager/ExtensionInstallationMetadataStore.swift"

if rg -n 'struct (Environment|Dependencies)|ExtensionInstallationService\.Environment' \
    "$service" "$record" "$policy" "$settlement" "$identity" "$admission"; then
    echo "installation transaction roles must not hide collaborators in dependency bags" >&2
    exit 1
fi

if rg -n 'ExtensionManager|BrowserManager|\bOwner\b' \
    "$service" "$record" "$policy" "$settlement" "$identity" "$admission"; then
    echo "focused installation roles must remain manager-root and Owner-free" >&2
    exit 1
fi

if rg -n 'installDirectoryExtension|installSafariAppExtension|rollbackPersistedRecord' \
    "$service"; then
    echo "duplicated package-specific installation transactions must not return" >&2
    exit 1
fi

service_lines="$(wc -l < "$service" | tr -d ' ')"
if (( service_lines > 430 )); then
    echo "ExtensionInstallationService grew beyond the 430-line transaction ratchet" >&2
    exit 1
fi

claim_line="$(rg -n 'sourceAdmission\.begin' "$service" | head -1 | cut -d: -f1)"
async_install_line="$(rg -n '^    \) async throws -> InstalledExtension' "$service" | head -1 | cut -d: -f1)"
if [[ -z "$claim_line" || -z "$async_install_line" ]] \
    || sed -n "${async_install_line},${claim_line}p" "$service" | rg -q '\bawait\b'; then
    echo "source identity must be claimed before the first runtime await" >&2
    exit 1
fi

rg -q '^actor ExtensionPackageInstallTransaction' "$package"
rg -q 'func rollback\(\) async throws' "$package"
rg -q '^    func commit\(\) async \{$' "$package"
if rg -n 'func commit\(\) async throws' "$package" "$prepared_package"; then
    echo "durable package commit must remain nonthrowing" >&2
    exit 1
fi
if rg -n '@MainActor' "$package"; then
    echo "package filesystem transaction must not run on MainActor" >&2
    exit 1
fi
if rg -n 'Task\.detached' "$package"; then
    echo "blocking package I/O must not occupy Swift's cooperative executor" >&2
    exit 1
fi
rg -q 'DispatchQueue\(label: label, qos: \.utility\)' "$package"
rg -q 'withCheckedThrowingContinuation' "$package"
for operation in prepareStaging copyStagedPackage prepareMaterialization \
    materializePackage inspectMaterializedPackage deleteRollbackArtifacts; do
    rg -q "\\.${operation}" "$package"
done
rg -q 'scanAndMoveStagedPackage' "$package"
rg -q 'rejectSymbolicLinks\(in: destination\)' "$package"
rg -q 'validateCopiedManifest' "$package"
if rg -n 'fingerprint\(fileAt:' "$package" "$prepared_package"; then
    echo "transactional manifest fingerprints must come from throwing Data reads" >&2
    exit 1
fi
final_scan_line="$(rg -n 'rejectSymbolicLinks\(in: stagedPackageRoot\)' "$package" | tail -1 | cut -d: -f1)"
move_line="$(rg -n 'try FileManager\.default\.moveItem' "$package" | head -1 | cut -d: -f1)"
if [[ -z "$final_scan_line" || -z "$move_line" ]] \
    || (( final_scan_line >= move_line )) \
    || sed -n "${final_scan_line},${move_line}p" "$package" | rg -q '\bawait\b'; then
    echo "final package scan and materializing move must share one non-suspending critical operation" >&2
    exit 1
fi
rg -q 'manifestRootFingerprint: materialized\.manifestFingerprint' "$service"
rg -q 'fileExecutor: packageFileExecutor' "$service"
claiming_staging_line="$(rg -n 'phase = \.claimingStaging' "$package" | head -1 | cut -d: -f1)"
begin_staging_line="$(rg -n 'activeGenerations\.begin\(stagedPackageRoot\)' "$package" | head -1 | cut -d: -f1)"
claiming_generation_line="$(rg -n 'phase = \.claimingGeneration' "$package" | head -1 | cut -d: -f1)"
begin_generation_line="$(rg -n 'activeGenerations\.begin\(destination\)' "$package" | head -1 | cut -d: -f1)"
if (( claiming_staging_line >= begin_staging_line )) \
    || (( claiming_generation_line >= begin_generation_line )); then
    echo "transaction phase must become non-reentrant before generation registry hops" >&2
    exit 1
fi
rg -q 'UUID\(\)\.uuidString' "$layout"
rg -q 'ExtensionPackageLayout' "$package"
rg -q 'activePackageGenerations' "$service"
rg -q 'quarantineOrphans' "$maintenance"
rg -q 'case volatileCandidatePublished' "$record"
rg -q 'case volatileExactRuntime' "$root/Sumi/Managers/ExtensionManager/InstalledExtensionCollection.swift"
rg -q 'try persistence\.persist' "$record"
rg -q 'installedRecords\.upsert' "$record"
rg -q 'changed its declared extension identity' "$identity"
rg -q 'ExtensionInstallationFailurePolicy\.resolve' "$settlement"
rg -q 'failureSettlement\.settle' "$service"
rg -q 'legacyBackupRecovery\.recover' "$metadata_store"
rg -q '\.union\(deferredPackagePaths\)' "$metadata_store"
if rg -n 'try\?' "$legacy_recovery"; then
    echo "legacy package recovery must not silently discard filesystem failures" >&2
    exit 1
fi

tests="$root/SumiTests"
for symbol in \
    testEveryPackageAndRollbackDispositionHasExactCompensation \
    testExactRuntimePersistenceFailurePublishesTypedVolatileCandidate \
    testExistingSourceCannotSilentlyChangeDeclaredIdentity \
    testDeclaredIdentityCannotTakeOverDifferentPackageKind \
    testMovedSafariSourceRequiresSameSigningIdentity \
    testSourceAdmissionRejectsOverlapAndReleasesExactClaim \
    testExternalSafariRollbackNeverPretendsToRecoverOldBytes \
    testExactRuntimePersistenceFailurePublishesObservableVolatileRecord \
    testActivationRollbackAuthorityOverridesOriginalErrorDisposition \
    testRecordRestorationFailureIsReportedAsIndeterminateMetadata \
    testVolatileRecordMustPersistBeforeBecomingDurable \
    testReconcileAllPersistsEveryVolatileCandidate \
    testDurableCommitKeepsCandidateWithoutMutatingSupersededPackage \
    testPreservedCandidateNeverOverwritesSupersededPackage \
    testFreshRollbackDeletesUncommittedCandidate \
    testStagingRejectsSymlinkedRuntimeResources \
    testMaterializationRechecksSymlinksInjectedAfterStaging \
    testFailedRollbackCanRetryWithoutDeletingSupersededPackage \
    testRollbackDeletesCandidateWithoutTouchingSupersededPackage \
    testExistingQuarantineIsReturnedForRetryDeletion \
    testNonUUIDLegacyPackageIsQuarantinedWhenUnreferenced \
    testLegacyPackageClassificationDoesNotRequireGenerationDirectories \
    testManagedSymlinkToAnotherGenerationIsRejected \
    testReservedGenerationRootSymlinkIsRejected \
    testCopiedManifestDriftBeforeMaterializationIsRejectedAndReversible \
    testMaterializeBeforeStageFailsWithoutChangingPhase \
    testCancellationAfterStagingClaimRollsBackBytesAndReleasesExactClaim \
    testCancellationAfterGenerationClaimRollsBackMovedBytesAndReleasesClaim \
    testTerminalOperationsAreIdempotentAndCommittedRollbackIsRejected \
    testExactClaimsBlockMaintenanceUntilTransactionSettles \
    testBlockedFileQueueKeepsMainActorResponsiveAndRejectsReentry \
    testCatalogDropsDirectoryRecordOutsideBrowserStorage \
    testCatalogDropsSymlinkEscapeWithoutTouchingTarget \
    testMissingDurableRootRestoresOnlyMatchingBackup \
    testMismatchedDurableRootIsQuarantinedBeforeBackupRestore \
    testMatchingDurableRootQuarantinesAllStaleBackups \
    testAmbiguousMatchingBackupsPreserveFilesystemAndDeferValidation \
    testNoMatchingBackupDoesNotReplaceMismatchedCurrentRoot \
    testSymlinkBackupIsIgnoredWithoutTouchingItsTarget \
    testMetadataLoadRecoversBeforeRejectingMissingLegacyRoot \
    testAmbiguousRecoveryPreservesDurableMetadataWithoutPublication \
    testNoMatchPreservesMismatchedRootAndMetadataWithoutPublication; do
    if ! rg -q "func $symbol" "$tests"; then
        echo "missing installation transaction regression: $symbol" >&2
        exit 1
    fi
done

transaction_tests="$tests/ExtensionPackageInstallTransactionTests.swift"
for symbol in \
    testCancellationAfterStagingClaimRollsBackBytesAndReleasesExactClaim \
    testCancellationAfterGenerationClaimRollsBackMovedBytesAndReleasesClaim \
    testBlockedFileQueueKeepsMainActorResponsiveAndRejectsReentry; do
    if ! rg -q "func $symbol" "$transaction_tests"; then
        echo "missing package actor regression in focused test file: $symbol" >&2
        exit 1
    fi
done

echo "extension installation transaction boundary passed"
