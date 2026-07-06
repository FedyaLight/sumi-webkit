//
//  ExtensionHubOrderingOwner.swift
//  Sumi
//
//  Owns the per-profile display order of *unpinned* extension action tiles in
//  the URL hub. Pinned toolbar order lives in `ExtensionToolbarPinningOwner`;
//  this is its sibling for the complementary set, so the hub can be reordered
//  independently of the toolbar. Persisted to preferences as JSON.
//

import Foundation
import OSLog

@available(macOS 15.5, *)
@MainActor
final class ExtensionHubOrderingOwner {
    struct Dependencies {
        let preferences: UserDefaults
        let currentProfileId: @MainActor () -> UUID?
    }

    static let unpinnedOrderStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.hubUnpinnedOrderByProfile"
    private static let globalProfileKey = "__global__"
    private static let logger = Logger.sumi(category: "Extensions")

    private let dependencies: Dependencies
    private var idsByProfile: [String: [String]]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.idsByProfile =
            Self.loadUnpinnedOrderByProfile(from: dependencies.preferences)
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
    /// then persist the resulting order for the current profile. `targetIndex`
    /// is interpreted against the list with the moved tile removed.
    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String]
    ) {
        var order = Self.normalized(currentOrder)
        guard let from = order.firstIndex(of: id) else { return }

        let item = order.remove(at: from)
        let clamped = min(max(targetIndex, 0), order.count)
        order.insert(item, at: clamped)

        let profileKey = Self.profileKey(for: dependencies.currentProfileId())
        idsByProfile[profileKey] = order
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(idsByProfile)
            dependencies.preferences.set(data, forKey: Self.unpinnedOrderStorageKey)
        } catch {
            Self.logger.error(
                "Failed to encode hub unpinned order: \(String(describing: error), privacy: .public)"
            )
        }
    }

    static func loadUnpinnedOrderByProfile(
        from userDefaults: UserDefaults = .standard
    ) -> [String: [String]] {
        guard let data = userDefaults.data(forKey: unpinnedOrderStorageKey) else {
            return [:]
        }

        do {
            let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
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

@available(macOS 15.5, *)
extension ExtensionHubOrderingOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            preferences: manager.extensionPreferences,
            currentProfileId: { [weak manager] in manager?.currentProfileId }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func orderedUnpinnedExtensionIDs(
        candidateIDs: [String],
        profileId: UUID?
    ) -> [String] {
        hubOrderingOwner.orderedUnpinnedExtensionIDs(
            candidateIDs: candidateIDs,
            profileId: profileId ?? currentProfileId
        )
    }

    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String]
    ) {
        hubOrderingOwner.moveUnpinnedExtension(
            id: id,
            to: targetIndex,
            within: currentOrder
        )
    }
}
