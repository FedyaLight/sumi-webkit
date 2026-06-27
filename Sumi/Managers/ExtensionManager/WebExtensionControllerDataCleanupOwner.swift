//
//  WebExtensionControllerDataCleanupOwner.swift
//  Sumi
//
//  Owns matching and removing WebKit WebExtension data records across profile
//  controllers. ExtensionManager remains the install/runtime orchestrator.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct WebExtensionControllerDataCleanupOwner {
    @MainActor
    struct MatchedRecords {
        let dataTypes: Set<WKWebExtension.DataType>
        fileprivate let records: [WKWebExtension.DataRecord]

        var isEmpty: Bool {
            records.isEmpty
        }

        var errors: [Error] {
            records.flatMap { $0.errors }
        }
    }

    func matchingRecords(
        for extensionId: String,
        controllersByProfile: [UUID: WKWebExtensionController]
    ) async -> MatchedRecords {
        let dataTypes = WKWebExtensionController.allExtensionDataTypes
        var matchingRecords: [WKWebExtension.DataRecord] = []

        for (profileId, controller) in controllersByProfile {
            let records = await fetchDataRecords(
                ofTypes: dataTypes,
                from: controller
            )
            matchingRecords.append(
                contentsOf: records.filter {
                    matches($0, extensionId: extensionId, profileId: profileId)
                }
            )
        }

        return MatchedRecords(
            dataTypes: dataTypes,
            records: matchingRecords
        )
    }

    func remove(
        _ matchedRecords: MatchedRecords,
        extensionId: String,
        using controllersByProfile: [UUID: WKWebExtensionController]
    ) async {
        // Preserve ExtensionManager's legacy cleanup behavior: unscoped records are
        // offered to every profile controller, not only the controller that fetched them.
        for (profileId, controller) in controllersByProfile {
            let profileRecords = matchedRecords.records.filter {
                matches($0, extensionId: extensionId, profileId: profileId)
            }
            guard profileRecords.isEmpty == false else { continue }

            await removeData(
                ofTypes: matchedRecords.dataTypes,
                records: profileRecords,
                from: controller
            )
        }
    }

    private func fetchDataRecords(
        ofTypes dataTypes: Set<WKWebExtension.DataType>,
        from controller: WKWebExtensionController
    ) async -> [WKWebExtension.DataRecord] {
        await withCheckedContinuation { continuation in
            controller.fetchDataRecords(ofTypes: dataTypes) { records in
                continuation.resume(returning: records)
            }
        }
    }

    private func removeData(
        ofTypes dataTypes: Set<WKWebExtension.DataType>,
        records: [WKWebExtension.DataRecord],
        from controller: WKWebExtensionController
    ) async {
        await withCheckedContinuation { continuation in
            controller.removeData(
                ofTypes: dataTypes,
                from: records
            ) {
                continuation.resume(returning: ())
            }
        }
    }

    private func matches(
        _ record: WKWebExtension.DataRecord,
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        let scopedIdentifier = "\(profileId.uuidString):\(extensionId)"
        return record.uniqueIdentifier == extensionId
            || record.uniqueIdentifier == scopedIdentifier
    }
}
