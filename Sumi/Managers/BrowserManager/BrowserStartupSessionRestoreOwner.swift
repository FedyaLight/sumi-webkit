import Foundation

@MainActor
protocol BrowserStartupSessionRestoreProviding: AnyObject {
    var canOfferRestoreShortcut: Bool { get }
    var windowSnapshots: [LastSessionWindowSnapshot] { get }
    var tabSnapshot: TabSnapshotRepository.Snapshot? { get }
    func markRestoreOfferConsumed()
}

@MainActor
final class BrowserStartupSessionRestoreOwner: BrowserStartupSessionRestoreProviding {
    private let coordinator = SumiStartupSessionCoordinator()
    private var lastSessionWindowsStore: LastSessionWindowsStore

    private(set) var windowSnapshots: [LastSessionWindowSnapshot]
    private(set) var tabSnapshot: TabSnapshotRepository.Snapshot?
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

    func reconcileIfReady(dependencies: SumiStartupSessionCoordinator.Dependencies) {
        coordinator.applyIfReady(dependencies: dependencies)
    }

    func archiveLoadedSessionForManualRestore(
        currentWindowSnapshots: @MainActor () -> [LastSessionWindowSnapshot],
        currentTabSnapshot: @MainActor () -> TabSnapshotRepository.Snapshot
    ) {
        let archivedWindowSnapshots = windowSnapshots.isEmpty
            ? currentWindowSnapshots()
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
