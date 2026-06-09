//
//  ChromeMV3ServiceWorkerLocalStorageMirror.swift
//  Sumi
//
//  Generic chrome.storage.local mirroring between a service-worker JavaScript
//  harness and a host-backed popup/options storage broker for one extension and
//  profile namespace. No Bitwarden-specific behavior is implemented here.
//

import Foundation

struct ChromeMV3ServiceWorkerLocalStorageMirrorCallbackResult:
    Equatable,
    Sendable
{
    var onChangedPayload: ChromeMV3StorageOnChangedEventPayload?
    var exportedValueCount: Int
    var hostBackedChangedKeyCount: Int
    var hostBackedPreMirrorValueCount: Int
    var popupBrokerPreMirrorValueCount: Int
    var popupBrokerMissingExportedValueCount: Int
    var popupBrokerImportedExportedValueCount: Int
    var popupBrokerPostMirrorValueCount: Int
    var hostBackedImportCategory: String
    var popupHydrationCategory: String

    static let empty = ChromeMV3ServiceWorkerLocalStorageMirrorCallbackResult(
        onChangedPayload: nil,
        exportedValueCount: 0,
        hostBackedChangedKeyCount: 0,
        hostBackedPreMirrorValueCount: 0,
        popupBrokerPreMirrorValueCount: 0,
        popupBrokerMissingExportedValueCount: 0,
        popupBrokerImportedExportedValueCount: 0,
        popupBrokerPostMirrorValueCount: 0,
        hostBackedImportCategory: "notObserved",
        popupHydrationCategory: "notObserved"
    )
}

struct ChromeMV3ServiceWorkerLocalStorageMirrorResult:
    Codable,
    Equatable,
    Sendable
{
    var succeeded: Bool
    var persisted: Bool
    var changedKeyCount: Int
    var writerContextCategory: String
    var readerContextCategory: String
    var storageArea: String
    var namespaceHash: String
    var snapshotCategory: String
    var onChangedDeliveryCategory: String
    var diagnostics: [String]

    static let empty = ChromeMV3ServiceWorkerLocalStorageMirrorResult(
        succeeded: true,
        persisted: false,
        changedKeyCount: 0,
        writerContextCategory: "unknown",
        readerContextCategory: "popup",
        storageArea: ChromeMV3StorageAreaKind.local.chromeAreaName,
        namespaceHash: "none",
        snapshotCategory: "noChanges",
        onChangedDeliveryCategory: "notApplicable",
        diagnostics: [
            "No service-worker storage.local mirror changes were produced.",
        ]
    )
}

enum ChromeMV3ServiceWorkerLocalStorageMirror {
    /// Drains bounded Promise/microtask generations and manually queued
    /// service-worker timer callbacks so deferred startup work (for example async
    /// storage writes) can complete before export/mirror.
    /// Chrome documents `storage.local` as shared extension state; MV3 service
    /// workers may schedule follow-up work after listener dispatch.
    @discardableResult
    static func flushDeferredServiceWorkerWork(
        in harness: ChromeMV3ServiceWorkerJSExecutionHarness,
        maxDrainPasses: Int = 8,
        maxCallbacksPerPass: Int = 200,
        maxElapsedMilliseconds: Int = 50
    ) -> ChromeMV3ServiceWorkerAsyncFlushResult {
        harness.flushBoundedAsyncContinuations(
            maxDrainPasses: maxDrainPasses,
            maxCallbacksPerPass: maxCallbacksPerPass,
            maxElapsedMilliseconds: maxElapsedMilliseconds
        )
    }

    static func mirrorExportedValues(
        _ exportedValues: [String: ChromeMV3StorageValue],
        into broker: inout ChromeMV3StorageBroker,
        writerContextCategory: String,
        readerContextCategory: String = "popup",
        fileManager: FileManager = .default
    ) -> (
        result: ChromeMV3ServiceWorkerLocalStorageMirrorResult,
        onChangedPayload: ChromeMV3StorageOnChangedEventPayload?
    ) {
        let oldValues = broker.exportSnapshot().values
        let namespace = broker.namespace
        let changeSet = ChromeMV3StorageChangeSet.make(
            namespace: namespace,
            oldValues: oldValues,
            newValues: exportedValues
        )
        guard changeSet.changedKeys.isEmpty == false else {
            return (
                .empty,
                nil
            )
        }

        let snapshot = ChromeMV3StorageSnapshot(
            namespace: namespace,
            values: exportedValues
        )
        let importResult = broker.importSnapshot(
            snapshot,
            fileManager: fileManager
        )
        let persisted =
            importResult.succeeded
            && broker.snapshotURL != nil
        let onChangedPayload = importResult.succeeded
            ? popupOnChangedPayload(
                from: changeSet,
                writerContextCategory: writerContextCategory
            )
            : nil
        let onChangedDeliveryCategory =
            onChangedPayload == nil
                ? "mirrorFailed"
                : "pendingPopupDispatch"
        let snapshotCategory =
            persisted ? "hostSnapshotPersisted" : "inMemoryOnly"
        let result = ChromeMV3ServiceWorkerLocalStorageMirrorResult(
            succeeded: importResult.succeeded,
            persisted: persisted,
            changedKeyCount: changeSet.changedKeys.count,
            writerContextCategory: writerContextCategory,
            readerContextCategory: readerContextCategory,
            storageArea: namespace.area.chromeAreaName,
            namespaceHash: namespace.namespaceID,
            snapshotCategory: snapshotCategory,
            onChangedDeliveryCategory: onChangedDeliveryCategory,
            diagnostics: uniqueSortedServiceWorkerLocalStorageMirror(
                importResult.errorDiagnostics.map(\.message)
                    + [
                        "writerContextCategory=\(writerContextCategory)",
                        "readerContextCategory=\(readerContextCategory)",
                        "storageArea=\(namespace.area.chromeAreaName)",
                        "namespaceHash=\(namespace.namespaceID)",
                        "changedKeyCount=\(changeSet.changedKeys.count)",
                        "snapshotCategory=\(snapshotCategory)",
                        "onChangedDeliveryCategory=\(onChangedDeliveryCategory)",
                        "No raw storage keys or values are logged.",
                    ]
            )
        )
        return (result, onChangedPayload)
    }

    /// Merges exported service-worker `storage.local` values into a popup-owned
    /// bridge broker without requiring host-backed import to report changed keys.
    /// Hydration preserves existing popup broker keys and overlays exported
    /// values on top. `storage.onChanged` is not produced here; callers should
    /// emit it only for extension-level host-backed changes.
    static func hydratePopupBrokerFromExportedValues(
        _ exportedValues: [String: ChromeMV3StorageValue],
        into broker: inout ChromeMV3StorageBroker,
        writerContextCategory: String,
        readerContextCategory: String = "popup",
        fileManager: FileManager = .default
    ) -> (
        missingExportedValueCount: Int,
        importedExportedValueCount: Int,
        succeeded: Bool
    ) {
        let popupPreValues = broker.exportSnapshot().values
        let missingKeys = exportedValues.keys.filter { key in
            popupPreValues[key] != exportedValues[key]
        }
        guard missingKeys.isEmpty == false else {
            return (0, 0, true)
        }
        var mergedValues = popupPreValues
        for (key, value) in exportedValues {
            mergedValues[key] = value
        }
        let snapshot = ChromeMV3StorageSnapshot(
            namespace: broker.namespace,
            values: mergedValues
        )
        let importResult = broker.importSnapshot(
            snapshot,
            fileManager: fileManager
        )
        let importedCount = importResult.succeeded ? missingKeys.count : 0
        _ = writerContextCategory
        _ = readerContextCategory
        return (missingKeys.count, importedCount, importResult.succeeded)
    }

    static func reconcileServiceWorkerExportIntoBrokers(
        _ exportedValues: [String: ChromeMV3StorageValue],
        hostBackedBroker: inout ChromeMV3StorageBroker,
        popupBroker: inout ChromeMV3StorageBroker,
        writerContextCategory: String,
        fileManager: FileManager = .default
    ) -> ChromeMV3ServiceWorkerLocalStorageMirrorCallbackResult {
        let hostPreMirrorCount =
            hostBackedBroker.exportSnapshot().values.count
        let popupPreMirrorCount =
            popupBroker.exportSnapshot().values.count
        let recordMirror = mirrorExportedValues(
            exportedValues,
            into: &hostBackedBroker,
            writerContextCategory: writerContextCategory,
            fileManager: fileManager
        )
        let hydration = hydratePopupBrokerFromExportedValues(
            exportedValues,
            into: &popupBroker,
            writerContextCategory: writerContextCategory,
            fileManager: fileManager
        )
        let hostImportCategory: String
        if recordMirror.result.changedKeyCount == 0 {
            hostImportCategory = "noChangesImported"
        } else if recordMirror.result.persisted {
            hostImportCategory = "hostSnapshotPersisted"
        } else {
            hostImportCategory = "inMemoryOnly"
        }
        let popupHydrationCategory: String
        if hydration.importedExportedValueCount > 0 {
            popupHydrationCategory = "hydratedFromExport"
        } else if hydration.missingExportedValueCount == 0 {
            popupHydrationCategory = "alreadyCurrent"
        } else {
            popupHydrationCategory = "hydrationFailed"
        }
        return ChromeMV3ServiceWorkerLocalStorageMirrorCallbackResult(
            onChangedPayload: recordMirror.onChangedPayload,
            exportedValueCount: exportedValues.count,
            hostBackedChangedKeyCount: recordMirror.result.changedKeyCount,
            hostBackedPreMirrorValueCount: hostPreMirrorCount,
            popupBrokerPreMirrorValueCount: popupPreMirrorCount,
            popupBrokerMissingExportedValueCount:
                hydration.missingExportedValueCount,
            popupBrokerImportedExportedValueCount:
                hydration.importedExportedValueCount,
            popupBrokerPostMirrorValueCount:
                popupBroker.exportSnapshot().values.count,
            hostBackedImportCategory: hostImportCategory,
            popupHydrationCategory: popupHydrationCategory
        )
    }

    static func seedBrokerSnapshot(
        _ values: [String: ChromeMV3StorageValue],
        into harness: ChromeMV3ServiceWorkerJSExecutionHarness,
        area: ChromeMV3StorageAreaKind = .local
    ) -> Bool {
        harness.importStorageValues(values, area: area)
    }

    private static func popupOnChangedPayload(
        from changeSet: ChromeMV3StorageChangeSet,
        writerContextCategory: String
    ) -> ChromeMV3StorageOnChangedEventPayload {
        var payload = changeSet.futureOnChangedPayload
        payload.wouldDispatchNow = true
        payload.listenerRegistrationRequired = false
        payload.serviceWorkerWakeRequired = false
        payload.blockers = [
            "storage.onChanged originated from a mirrored service-worker storage.local write.",
            "writerContextCategory=\(writerContextCategory)",
            "No product normal-tab listener is registered.",
        ]
        return payload
    }

    private static func uniqueSortedServiceWorkerLocalStorageMirror(
        _ values: [String]
    ) -> [String] {
        Array(Set(values)).sorted()
    }
}
