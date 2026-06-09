//
//  ChromeMV3ServiceWorkerLocalStorageMirror.swift
//  Sumi
//
//  Generic chrome.storage.local mirroring between a service-worker JavaScript
//  harness and a host-backed popup/options storage broker for one extension and
//  profile namespace. No Bitwarden-specific behavior is implemented here.
//

import Foundation

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
