import Foundation

@MainActor
protocol BrowserStartupSessionRestoreProviding: AnyObject {
    var canOfferRestoreShortcut: Bool { get }
    var windowSnapshots: [LastSessionWindowSnapshot] { get }
    var tabSnapshot: TabPersistenceSnapshot? { get }
    func markRestoreOfferConsumed()
}

@MainActor
final class BrowserStartupSessionRestoreOwner: BrowserStartupSessionRestoreProviding {
    private let coordinator = SumiStartupSessionCoordinator()
    private var lastSessionWindowsStore: LastSessionWindowsStore

    private(set) var windowSnapshots: [LastSessionWindowSnapshot]
    private(set) var tabSnapshot: TabPersistenceSnapshot?
    private var didConsumeRestoreOffer = false

    var canOfferRestoreShortcut: Bool {
        !didConsumeRestoreOffer && !windowSnapshots.isEmpty
    }

    init(lastSessionWindowsStore: LastSessionWindowsStore) {
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.windowSnapshots = lastSessionWindowsStore.snapshots
        self.tabSnapshot = lastSessionWindowsStore.tabSnapshot
    }

    func reload(from lastSessionWindowsStore: LastSessionWindowsStore) {
        self.lastSessionWindowsStore = lastSessionWindowsStore
        windowSnapshots = lastSessionWindowsStore.snapshots
        tabSnapshot = lastSessionWindowsStore.tabSnapshot
        didConsumeRestoreOffer = false
    }

    func reconcileIfReady(
        hasLoadedInitialTabData: @escaping @MainActor () -> Bool,
        startupMode: @escaping @MainActor () -> SumiStartupMode?,
        startupWindow: @escaping @MainActor () -> BrowserWindowState?,
        applyStartupPolicy: @escaping @MainActor (SumiStartupMode) -> Void
    ) {
        coordinator.applyIfReady(
            hasLoadedInitialTabData: hasLoadedInitialTabData,
            startupMode: startupMode,
            startupWindow: startupWindow,
            applyStartupPolicy: applyStartupPolicy
        )
    }

    func archiveLoadedSessionForManualRestore(
        currentWindowSnapshots: @MainActor () -> [LastSessionWindowSnapshot],
        currentTabSnapshot: @MainActor () -> TabPersistenceSnapshot
    ) {
        // Clean startup reuses the same runtime windows for new content. Give
        // the historical branch detached identities so it remains restorable.
        let archivedWindowSnapshots = windowSnapshots.isEmpty
            ? currentWindowSnapshots().map {
                LastSessionWindowSnapshot(id: UUID(), session: $0.session)
            }
            : windowSnapshots
        let resolvedTabSnapshot = currentTabSnapshot()
        guard !archivedWindowSnapshots.isEmpty || !resolvedTabSnapshot.tabs.isEmpty else {
            return
        }

        windowSnapshots = archivedWindowSnapshots
        tabSnapshot = resolvedTabSnapshot
        lastSessionWindowsStore.updateSnapshots(
            archivedWindowSnapshots,
            tabSnapshot: resolvedTabSnapshot
        )
        didConsumeRestoreOffer = false
    }

    func markRestoreOfferConsumed() {
        didConsumeRestoreOffer = true
    }
}
