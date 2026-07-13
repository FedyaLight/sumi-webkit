#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
catalog="$root/Sumi/Managers/ExtensionManager/InstalledExtensionCatalog.swift"
tests="$root/SumiTests/InstalledExtensionCatalogTests.swift"

publish_line="$(rg -n '^    func publish\(' "$catalog" | head -1 | cut -d: -f1)"
fetch_guard_line="$(rg -n 'guard result\.didFetchPersistedMetadata else' "$catalog" | head -1 | cut -d: -f1)"
set_all_line="$(rg -n 'environment\.installedRecords\.setAll' "$catalog" | head -1 | cut -d: -f1)"
loaded_line="$(rg -n 'environment\.markCatalogLoaded\(\)' "$catalog" | head -1 | cut -d: -f1)"

if [[ -z "$publish_line" || -z "$fetch_guard_line" \
    || -z "$set_all_line" || -z "$loaded_line" ]] \
    || (( publish_line >= fetch_guard_line )) \
    || (( fetch_guard_line >= set_all_line )) \
    || (( set_all_line >= loaded_line )); then
    echo "failed metadata fetch must be rejected before catalog and readiness publication" >&2
    exit 1
fi

for symbol in \
    testFailedFetchPreservesAuthoritativeCatalogReadinessToolbarPinsRevisionAndDurability \
    testFailedInitialFetchDoesNotPublishReadiness \
    testVolatileReconciliationFailurePreservesExactLiveSnapshotAndDefersPublication \
    testSuccessfulEmptySnapshotClearsCatalogPublishesReadinessAndReconcilesPins \
    testSuccessfulNonemptySnapshotPublishesAllRecordsAndReturnsOnlyEnabledEntities; do
    if ! rg -q "func $symbol" "$tests"; then
        echo "missing installed-extension catalog regression: $symbol" >&2
        exit 1
    fi
done

echo "installed-extension catalog boundary passed"
