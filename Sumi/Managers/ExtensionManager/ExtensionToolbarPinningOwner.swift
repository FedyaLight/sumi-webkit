import Foundation
import OSLog

@available(macOS 15.5, *)
enum PinnedToolbarSlot: Identifiable {
    case webExtension(BrowserExtensionToolbarDisplayRecord)

    var id: String {
        switch self {
        case .webExtension(let ext):
            return ext.id
        }
    }
}

/// Owns per-profile toolbar pinning for extensions.
@available(macOS 15.5, *)
@MainActor
final class ExtensionToolbarPinningOwner {
    private static let documentKey = "extensions.toolbar-pins"
    private static let globalPinnedToolbarProfileKey = "__global__"
    private static let logger = Logger.sumi(category: "Extensions")

    private let database: SumiDatabase
    private let currentProfileId: @MainActor () -> UUID?
    private let installedExtensionIDs: @MainActor () -> Set<String>
    private let publishedPinnedIDs: @MainActor () -> [String]
    private let setPublishedPinnedIDs: @MainActor ([String]) -> Void
    private var idsByProfile: [String: [String]]

    init(
        database: SumiDatabase,
        currentProfileId: @escaping @MainActor () -> UUID?,
        installedExtensionIDs: @escaping @MainActor () -> Set<String>,
        publishedPinnedIDs: @escaping @MainActor () -> [String],
        setPublishedPinnedIDs: @escaping @MainActor ([String]) -> Void
    ) {
        self.database = database
        self.currentProfileId = currentProfileId
        self.installedExtensionIDs = installedExtensionIDs
        self.publishedPinnedIDs = publishedPinnedIDs
        self.setPublishedPinnedIDs = setPublishedPinnedIDs
        self.idsByProfile =
            Self.loadPinnedToolbarExtensionIDsByProfile(from: database)
    }

    var pinnedToolbarExtensionIDsByProfile: [String: [String]] {
        idsByProfile
    }

    func replacePinnedToolbarExtensionIDsByProfile(
        _ idsByProfile: [String: [String]]
    ) {
        self.idsByProfile = idsByProfile.mapValues(Self.normalizedPinnedToolbarExtensionIDs)
        reloadPinnedToolbarExtensionsForCurrentProfile()
        persistPinnedToolbarExtensionIDsByProfile()
    }

    func pinnedToolbarExtensionIDs(profileId: UUID?) -> [String] {
        let profileKey = Self.pinnedToolbarProfileKey(for: profileId)
        return Self.normalizedPinnedToolbarExtensionIDs(
            idsByProfile[profileKey] ?? []
        )
    }

    @discardableResult
    func pinToToolbar(_ extensionId: String, profileId: UUID?) -> Bool {
        updatePinnedToolbarExtensionIDs(profileId: profileId) { ids in
            guard ids.contains(extensionId) == false else { return }
            ids.append(extensionId)
        }
    }

    @discardableResult
    func unpinFromToolbar(_ extensionId: String, profileId: UUID?) -> Bool {
        updatePinnedToolbarExtensionIDs(profileId: profileId) { ids in
            ids.removeAll { $0 == extensionId }
        }
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
        reloadPinnedToolbarExtensionsForCurrentProfile()
        return persistPinnedToolbarExtensionIDsByProfile()
    }

    /// Move an already-pinned slot to a new index within `displayedOrder` — the
    /// slot ids the surface actually rendered — and splice the result back into
    /// the persisted order. The target index is interpreted against the
    /// displayed list with the moved slot removed, matching
    /// `ReorderMove.targetIndex`.
    ///
    /// The displayed list is a subset of the persisted one: `orderedPinnedToolbarSlots`
    /// drops pinned ids whose extension is disabled or has no action, and the
    /// compact URL-bar strip truncates further. Applying a display-space index
    /// straight to the persisted array would land the slot in the wrong place,
    /// so the move is anchored to a displayed neighbour instead, leaving every
    /// filtered-out id where it was.
    @discardableResult
    func movePinnedToolbarSlot(
        id: String,
        to targetIndex: Int,
        within displayedOrder: [String],
        profileId: UUID?
    ) -> Bool {
        updatePinnedToolbarExtensionIDs(profileId: profileId) { ids in
            guard ids.contains(id) else { return }

            let displayed = Self.normalizedPinnedToolbarExtensionIDs(displayedOrder)
                .filter { ids.contains($0) }
            let remaining = displayed.filter { $0 != id }
            let clamped = min(max(targetIndex, 0), remaining.count)

            ids.removeAll { $0 == id }

            let insertionIndex: Int
            if clamped < remaining.count {
                // Land immediately before the displayed slot now occupying the
                // target position.
                insertionIndex = ids.firstIndex(of: remaining[clamped]) ?? ids.count
            } else if let trailing = remaining.last {
                // Past the last displayed slot: land immediately after it.
                insertionIndex = ids.firstIndex(of: trailing).map { $0 + 1 } ?? ids.count
            } else {
                insertionIndex = ids.count
            }

            ids.insert(id, at: min(insertionIndex, ids.count))
        }
    }

    func reloadPinnedToolbarExtensionsForCurrentProfile() {
        let profileKey = Self.pinnedToolbarProfileKey(for: currentProfileId())
        setPublishedPinnedIDs(
            Self.normalizedPinnedToolbarExtensionIDs(
                idsByProfile[profileKey] ?? []
            )
        )
    }

    func reconcilePinnedToolbarExtensions() {
        let installedIDs = installedExtensionIDs()
        updatePinnedToolbarExtensionIDs(profileId: currentProfileId()) { ids in
            ids.removeAll { installedIDs.contains($0) == false }
        }
    }

    /// Ordered toolbar buttons for enabled, pinned extensions.
    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        let enabledByID = Dictionary(
            uniqueKeysWithValues: enabledExtensions
                .filter(\.isEnabled)
                .filter(\.hasAction)
                .map { ($0.id, $0) }
        )
        let profileKey = Self.pinnedToolbarProfileKey(for: profileId)
        let normalizedPinnedIDs =
            Self.normalizedPinnedToolbarExtensionIDs(
                idsByProfile[profileKey] ?? []
            )

        return normalizedPinnedIDs.compactMap { id -> PinnedToolbarSlot? in
            guard let ext = enabledByID[id] else { return nil }
            return .webExtension(ext)
        }
    }

    @discardableResult
    private func updatePinnedToolbarExtensionIDs(
        profileId: UUID?,
        _ update: (inout [String]) -> Void
    ) -> Bool {
        let profileKey = Self.pinnedToolbarProfileKey(for: profileId)
        let previous = Self.normalizedPinnedToolbarExtensionIDs(
            idsByProfile[profileKey] ?? []
        )
        var ids = previous
        update(&ids)

        let normalized = Self.normalizedPinnedToolbarExtensionIDs(ids)
        guard normalized != previous else { return false }
        idsByProfile[profileKey] = normalized
        if profileKey == Self.pinnedToolbarProfileKey(for: currentProfileId()) {
            setPublishedPinnedIDs(normalized)
        }
        persistPinnedToolbarExtensionIDsByProfile()
        return true
    }

    @discardableResult
    private func persistPinnedToolbarExtensionIDsByProfile() -> Bool {
        do {
            try database.transaction {
                try $0.documents.save(
                    idsByProfile,
                    forKey: Self.documentKey
                )
            }
        } catch {
            Self.logger.error(
                "Failed to encode pinned toolbar extension IDs: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        return true
    }

    static func loadPinnedToolbarExtensionIDsByProfile(
        from database: SumiDatabase
    ) -> [String: [String]] {
        do {
            let decoded = try database.read {
                try $0.documents.value(
                    [String: [String]].self,
                    forKey: documentKey
                ) ?? [:]
            }
            return decoded.mapValues(normalizedPinnedToolbarExtensionIDs)
        } catch {
            Self.logger.error(
                "Failed to decode pinned toolbar extension IDs: \(String(describing: error), privacy: .public)"
            )
            return [:]
        }
    }

    static func pinnedToolbarProfileKey(for profileId: UUID?) -> String {
        profileId?.uuidString.lowercased() ?? globalPinnedToolbarProfileKey
    }

    static func normalizedPinnedToolbarExtensionIDs(
        _ ids: [String]
    ) -> [String] {
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
extension ExtensionToolbarPinningOwner:
    ExtensionToolbarProfileReloading {}
