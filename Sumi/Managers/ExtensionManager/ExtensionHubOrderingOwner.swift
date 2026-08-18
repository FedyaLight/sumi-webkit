//
//  ExtensionHubOrderingOwner.swift
//  Sumi
//
//  Owns the scoped display order of *unpinned* extension action tiles in the
//  the URL hub. Pinned toolbar order lives in `ExtensionToolbarPinningOwner`;
//  this is its sibling for the complementary set, so the hub can be reordered
//  independently of the toolbar. Persisted to preferences as JSON.
//

import Foundation
import OSLog

@available(macOS 15.5, *)
@MainActor
final class ExtensionHubOrderingOwner {
    private static let documentKey = "extensions.hub-order"
    private static let globalProfileKey = "__global__"
    private static let logger = Logger.sumi(category: "Extensions")

    private let database: SumiDatabase
    private var idsByProfile: [String: [String]]

    init(database: SumiDatabase) {
        self.database = database
        self.idsByProfile = Self.loadUnpinnedOrderByProfile(from: database)
    }

    /// The unpinned tiles in their persisted display order. `candidateIDs` are
    /// the currently-eligible unpinned extension IDs in their natural fallback
    /// (name-sorted) order; any not yet ordered are appended to the end.
    func orderedUnpinnedExtensionIDs(
        candidateIDs: [String],
        profileId: UUID?
    ) -> [String] {
        let profileKey = Self.profileKey(for: profileId)
        let stored = idsByProfile[profileKey] ?? []
        let candidateSet = Set(candidateIDs)

        let ordered = stored.filter { candidateSet.contains($0) }
        let orderedSet = Set(ordered)
        let missing = candidateIDs.filter { !orderedSet.contains($0) }
        return ordered + missing
    }

    /// Move an unpinned tile to a new index within the given displayed order,
    /// then persist the resulting order for the rendered profile. `targetIndex`
    /// is interpreted against the list with the moved tile removed.
    @discardableResult
    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String],
        profileId: UUID?
    ) -> Bool {
        var order = Self.normalized(currentOrder)
        let previous = order
        guard let from = order.firstIndex(of: id) else { return false }

        let item = order.remove(at: from)
        let clamped = min(max(targetIndex, 0), order.count)
        order.insert(item, at: clamped)
        guard order != previous else { return false }

        let profileKey = Self.profileKey(for: profileId)
        idsByProfile[profileKey] = order
        persist()
        return true
    }

    @discardableResult
    func removeExtensionFromAllProfiles(_ extensionId: String) -> Bool {
        var retainedByProfile: [String: [String]] = [:]
        for (profileKey, ids) in idsByProfile {
            let retained = ids.filter { $0 != extensionId }
            if retained.isEmpty == false {
                retainedByProfile[profileKey] = retained
            }
        }
        guard retainedByProfile != idsByProfile else { return true }
        idsByProfile = retainedByProfile
        return persist()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try database.transaction {
                try $0.documents.save(
                    idsByProfile,
                    forKey: Self.documentKey
                )
            }
        } catch {
            Self.logger.error(
                "Failed to encode hub unpinned order: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        return true
    }

    static func loadUnpinnedOrderByProfile(
        from database: SumiDatabase
    ) -> [String: [String]] {
        do {
            let decoded = try database.read {
                try $0.documents.value(
                    [String: [String]].self,
                    forKey: documentKey
                ) ?? [:]
            }
            return decoded.mapValues(Self.normalized)
        } catch {
            Self.logger.error(
                "Failed to decode hub unpinned order: \(String(describing: error), privacy: .public)"
            )
            return [:]
        }
    }

    static func profileKey(for profileId: UUID?) -> String {
        profileId?.uuidString.lowercased() ?? globalProfileKey
    }

    static func normalized(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids {
            let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else {
                continue
            }
            result.append(normalized)
        }
        return result
    }
}
