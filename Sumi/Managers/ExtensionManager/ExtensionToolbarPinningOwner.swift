import Foundation
import OSLog

@available(macOS 15.5, *)
enum PinnedToolbarSlot: Identifiable {
    case sumiScriptsManager
    case webExtension(InstalledExtension)

    var id: String {
        switch self {
        case .sumiScriptsManager:
            return SumiScriptsToolbarConstants.nativeToolbarItemID
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
    struct Dependencies {
        let preferences: UserDefaults
        let currentProfileId: @MainActor () -> UUID?
        let installedExtensionIDs: @MainActor () -> Set<String>
        let publishedPinnedIDs: @MainActor () -> [String]
        let setPublishedPinnedIDs: @MainActor ([String]) -> Void
    }

    static let pinnedToolbarExtensionIDsStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.toolbarPinnedIDsByProfile"
    private static let globalPinnedToolbarProfileKey = "__global__"
    private static let logger = Logger.sumi(category: "Extensions")

    private let dependencies: Dependencies
    private var idsByProfile: [String: [String]]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.idsByProfile =
            Self.loadPinnedToolbarExtensionIDsByProfile(from: dependencies.preferences)
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
        dependencies.publishedPinnedIDs().contains(extensionId)
    }

    func pinToToolbar(_ extensionId: String) {
        updatePinnedToolbarExtensionIDs { ids in
            guard ids.contains(extensionId) == false else { return }
            ids.append(extensionId)
        }
    }

    func unpinFromToolbar(_ extensionId: String) {
        updatePinnedToolbarExtensionIDs { ids in
            ids.removeAll { $0 == extensionId }
        }
    }

    func reloadPinnedToolbarExtensionsForCurrentProfile() {
        let profileKey = Self.pinnedToolbarProfileKey(for: dependencies.currentProfileId())
        dependencies.setPublishedPinnedIDs(
            Self.normalizedPinnedToolbarExtensionIDs(
                idsByProfile[profileKey] ?? []
            )
        )
    }

    func reconcilePinnedToolbarExtensions() {
        let installedIDs = dependencies.installedExtensionIDs()
        let sumiSlot = SumiScriptsToolbarConstants.nativeToolbarItemID
        guard installedIDs.isEmpty == false else {
            updatePinnedToolbarExtensionIDs { ids in
                ids.removeAll { $0 != sumiSlot }
            }
            return
        }

        updatePinnedToolbarExtensionIDs { ids in
            ids.removeAll { id in
                if id == sumiSlot { return false }
                return installedIDs.contains(id) == false
            }
        }
    }

    /// Ordered toolbar buttons: built-in SumiScripts slot (when enabled) + pinned extensions.
    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool,
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
            if id == SumiScriptsToolbarConstants.nativeToolbarItemID {
                return sumiScriptsManagerEnabled ? .sumiScriptsManager : nil
            }
            guard let ext = enabledByID[id] else { return nil }
            return .webExtension(ext)
        }
    }

    private func updatePinnedToolbarExtensionIDs(_ update: (inout [String]) -> Void) {
        let profileKey = Self.pinnedToolbarProfileKey(for: dependencies.currentProfileId())
        var ids = idsByProfile[profileKey] ?? []
        update(&ids)

        let normalized = Self.normalizedPinnedToolbarExtensionIDs(ids)
        idsByProfile[profileKey] = normalized
        dependencies.setPublishedPinnedIDs(normalized)
        persistPinnedToolbarExtensionIDsByProfile()
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

        dependencies.preferences.set(
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
extension ExtensionToolbarPinningOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            preferences: manager.extensionPreferences,
            currentProfileId: { [weak manager] in manager?.currentProfileId },
            installedExtensionIDs: { [weak manager] in
                Set((manager?.installedExtensions ?? []).map(\.id))
            },
            publishedPinnedIDs: { [weak manager] in
                manager?.pinnedToolbarExtensionIDs ?? []
            },
            setPublishedPinnedIDs: { [weak manager] ids in
                manager?.pinnedToolbarExtensionIDs = ids
            }
        )
    }
}

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

    func pinToToolbar(_ extensionId: String) {
        toolbarPinningOwner.pinToToolbar(extensionId)
    }

    func unpinFromToolbar(_ extensionId: String) {
        toolbarPinningOwner.unpinFromToolbar(extensionId)
    }

    func reloadPinnedToolbarExtensionsForCurrentProfile() {
        toolbarPinningOwner.reloadPinnedToolbarExtensionsForCurrentProfile()
    }

    func reconcilePinnedToolbarExtensions() {
        toolbarPinningOwner.reconcilePinnedToolbarExtensions()
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool
    ) -> [PinnedToolbarSlot] {
        toolbarPinningOwner.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: sumiScriptsManagerEnabled,
            profileId: currentProfileId
        )
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool,
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        toolbarPinningOwner.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: sumiScriptsManagerEnabled,
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
