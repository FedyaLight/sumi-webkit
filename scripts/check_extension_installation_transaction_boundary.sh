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

rg -q 'func rollback\(\) throws' "$package"
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

echo "extension installation transaction boundary passed"
