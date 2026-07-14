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

/// Owns per-profile toolbar pinning for extensions: pin/unpin state, profile
/// switches, reconciliation against installed extensions, ordered toolbar
/// slots, and persistence to preferences.
@available(macOS 15.5, *)
@MainActor
final class ExtensionToolbarPinningOwner {
    static let pinnedToolbarExtensionIDsStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.toolbarPinnedIDsByProfile"
    private static let globalPinnedToolbarProfileKey = "__global__"
    private static let logger = Logger.sumi(category: "Extensions")

    private let preferences: UserDefaults
    private let currentProfileId: @MainActor () -> UUID?
    private let installedExtensionIDs: @MainActor () -> Set<String>
    private let publishedPinnedIDs: @MainActor () -> [String]
    private let setPublishedPinnedIDs: @MainActor ([String]) -> Void
    private var idsByProfile: [String: [String]]

    init(
        preferences: UserDefaults,
        currentProfileId: @escaping @MainActor () -> UUID?,
        installedExtensionIDs: @escaping @MainActor () -> Set<String>,
        publishedPinnedIDs: @escaping @MainActor () -> [String],
        setPublishedPinnedIDs: @escaping @MainActor ([String]) -> Void
    ) {
        self.preferences = preferences
        self.currentProfileId = currentProfileId
        self.installedExtensionIDs = installedExtensionIDs
        self.publishedPinnedIDs = publishedPinnedIDs
        self.setPublishedPinnedIDs = setPublishedPinnedIDs
        self.idsByProfile =
            Self.loadPinnedToolbarExtensionIDsByProfile(from: preferences)
    }

    convenience init(manager: ExtensionManager) {
        self.init(
            preferences: manager.extensionPreferences,
            currentProfileId: { [weak manager] in manager?.profileRuntime.currentProfileId },
            installedExtensionIDs: { [weak manager] in
                Set((manager?.installedExtensionCollection.records ?? []).map(\.id))
            },
            publishedPinnedIDs: { [weak manager] in
                manager?.pinnedToolbarExtensionIDs ?? []
            },
            setPublishedPinnedIDs: { [weak manager] ids in
                manager?.pinnedToolbarExtensionIDs = ids
            }
        )
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

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        publishedPinnedIDs().contains(extensionId)
    }

    func pinnedToolbarExtensionIDs(profileId: UUID?) -> [String] {
        let profileKey = Self.pinnedToolbarProfileKey(for: profileId)
        return Self.normalizedPinnedToolbarExtensionIDs(
            idsByProfile[profileKey] ?? []
        )
    }

    @discardableResult
    func pinToToolbar(_ extensionId: String) -> Bool {
        updatePinnedToolbarExtensionIDs { ids in
            guard ids.contains(extensionId) == false else { return }
            ids.append(extensionId)
        }
    }

    @discardableResult
    func unpinFromToolbar(_ extensionId: String) -> Bool {
        updatePinnedToolbarExtensionIDs { ids in
            ids.removeAll { $0 == extensionId }
        }
    }

    /// Move an already-pinned slot to a new index within the pinned order. The
    /// target index is interpreted against the array with the moved slot
    /// removed, matching `ReorderMove.targetIndex`.
    @discardableResult
    func movePinnedToolbarSlot(id: String, to targetIndex: Int) -> Bool {
        updatePinnedToolbarExtensionIDs { ids in
            guard let from = ids.firstIndex(of: id) else { return }
            let slot = ids.remove(at: from)
            let clamped = min(max(targetIndex, 0), ids.count)
            ids.insert(slot, at: clamped)
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
        updatePinnedToolbarExtensionIDs { ids in
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
        _ update: (inout [String]) -> Void
    ) -> Bool {
        let profileKey = Self.pinnedToolbarProfileKey(for: currentProfileId())
        let previous = Self.normalizedPinnedToolbarExtensionIDs(
            idsByProfile[profileKey] ?? []
        )
        var ids = previous
        update(&ids)

        let normalized = Self.normalizedPinnedToolbarExtensionIDs(ids)
        guard normalized != previous else { return false }
        idsByProfile[profileKey] = normalized
        setPublishedPinnedIDs(normalized)
        persistPinnedToolbarExtensionIDsByProfile()
        return true
    }

    private func persistPinnedToolbarExtensionIDsByProfile() {
        let data: Data
        do {
            data = try JSONEncoder().encode(idsByProfile)
        } catch {
            Self.logger.error(
                "Failed to encode pinned toolbar extension IDs: \(String(describing: error), privacy: .public)"
            )
            return
        }

        preferences.set(
            data,
            forKey: Self.pinnedToolbarExtensionIDsStorageKey
        )
    }

    static func loadPinnedToolbarExtensionIDsByProfile(
        from userDefaults: UserDefaults = .standard
    ) -> [String: [String]] {
        guard
            let data = userDefaults.data(
                forKey: pinnedToolbarExtensionIDsStorageKey
            )
        else {
            return [:]
        }

        let decoded: [String: [String]]
        do {
            decoded = try JSONDecoder().decode([String: [String]].self, from: data)
        } catch {
            Self.logger.error(
                "Failed to decode pinned toolbar extension IDs: \(String(describing: error), privacy: .public)"
            )
            return [:]
        }

        return decoded.mapValues(Self.normalizedPinnedToolbarExtensionIDs)
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

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var pinnedToolbarExtensionIDsByProfile: [String: [String]] {
        get {
            toolbarPinningOwner.pinnedToolbarExtensionIDsByProfile
        }
        set {
            toolbarPinningOwner.replacePinnedToolbarExtensionIDsByProfile(newValue)
        }
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        toolbarPinningOwner.isPinnedToToolbar(extensionId)
    }

    func pinnedToolbarExtensionIDs(profileId: UUID?) -> [String] {
        toolbarPinningOwner.pinnedToolbarExtensionIDs(profileId: profileId)
    }

    @discardableResult
    func pinToToolbar(_ extensionId: String) -> Bool {
        toolbarPinningOwner.pinToToolbar(extensionId)
    }

    @discardableResult
    func unpinFromToolbar(_ extensionId: String) -> Bool {
        toolbarPinningOwner.unpinFromToolbar(extensionId)
    }

    @discardableResult
    func movePinnedToolbarSlot(id: String, to targetIndex: Int) -> Bool {
        toolbarPinningOwner.movePinnedToolbarSlot(id: id, to: targetIndex)
    }

    func reloadPinnedToolbarExtensionsForCurrentProfile() {
        toolbarPinningOwner.reloadPinnedToolbarExtensionsForCurrentProfile()
    }

    func reconcilePinnedToolbarExtensions() {
        toolbarPinningOwner.reconcilePinnedToolbarExtensions()
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord]
    ) -> [PinnedToolbarSlot] {
        toolbarPinningOwner.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileRuntime.currentProfileId
        )
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        toolbarPinningOwner.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileId
        )
    }

    static func loadPinnedToolbarExtensionIDsByProfile(
        from userDefaults: UserDefaults = .standard
    ) -> [String: [String]] {
        ExtensionToolbarPinningOwner.loadPinnedToolbarExtensionIDsByProfile(
            from: userDefaults
        )
    }

    static func pinnedToolbarProfileKey(for profileId: UUID?) -> String {
        ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: profileId)
    }

    static func normalizedPinnedToolbarExtensionIDs(
        _ ids: [String]
    ) -> [String] {
        ExtensionToolbarPinningOwner.normalizedPinnedToolbarExtensionIDs(ids)
    }
}
