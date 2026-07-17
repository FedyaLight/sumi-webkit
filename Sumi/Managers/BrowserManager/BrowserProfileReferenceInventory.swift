import Foundation

/// Reads every browser-shell reference authority without mutating it. An
/// unavailable window authority is itself a reference risk and fails closed.
@MainActor
final class BrowserProfileReferenceInventory {
    private let currentProfile: @MainActor () -> Profile?
    private let liveWindows: @MainActor () -> [BrowserWindowState]?
    private let hasTabReference: @MainActor (UUID) -> Bool
    private let primaryWindowSnapshotStore: WindowSessionSnapshotStore
    private let lastSessionWindowsStore: LastSessionWindowsStore
    private let startupRestore: BrowserStartupSessionRestoreOwner
    private let recentlyClosedManager: RecentlyClosedManager
    private let glanceManager: GlanceManager
    private let extensionRuntimeContainsReference: @MainActor (UUID) -> Bool

    init(
        currentProfile: @escaping @MainActor () -> Profile?,
        liveWindows: @escaping @MainActor () -> [BrowserWindowState]?,
        hasTabReference: @escaping @MainActor (UUID) -> Bool,
        primaryWindowSnapshotStore: WindowSessionSnapshotStore,
        lastSessionWindowsStore: LastSessionWindowsStore,
        startupRestore: BrowserStartupSessionRestoreOwner,
        recentlyClosedManager: RecentlyClosedManager,
        glanceManager: GlanceManager,
        extensionRuntimeContainsReference: @escaping @MainActor (UUID) -> Bool
    ) {
        self.currentProfile = currentProfile
        self.liveWindows = liveWindows
        self.hasTabReference = hasTabReference
        self.primaryWindowSnapshotStore = primaryWindowSnapshotStore
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.startupRestore = startupRestore
        self.recentlyClosedManager = recentlyClosedManager
        self.glanceManager = glanceManager
        self.extensionRuntimeContainsReference = extensionRuntimeContainsReference
    }

    func containsReference(to profileID: UUID) -> Bool {
        guard let liveWindows = liveWindows() else { return true }
        return hasTabReference(profileID)
            || glanceManager.containsProfileReference(to: profileID)
            || extensionRuntimeContainsReference(profileID)
            || currentProfile()?.id == profileID
            || recentlyClosedManager.containsProfileReference(to: profileID)
            || liveWindows.contains {
                ProfileReferenceInventory(windowState: $0).contains(profileID)
            }
            || primaryWindowSnapshotStore
            .containsDurableWindowProfileReference(to: profileID)
            || lastSessionWindowsStore.containsProfileReference(to: profileID)
            || startupRestore.containsCachedProfileReference(to: profileID)
    }
}
