import Foundation

@MainActor
final class BrowserStartupServices {
    let profileWebKitBootstrap: BrowserProfileWebKitBootstrap
    let pageActivationPerformance: PageActivationPerformanceMonitor
    private weak var browserManager: BrowserManager?
    private let splitQuery: WindowSplitQuery
    private var runtimeLifecycleStorage: BrowserRuntimeLifecycle?

    init(
        browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) {
        self.browserManager = browserManager
        self.splitQuery = splitQuery
        let profileWebKitBootstrap = BrowserProfileWebKitBootstrap(
            profiles: { [weak browserManager] in
                browserManager?.profileManager.profiles ?? []
            }
        )
        self.profileWebKitBootstrap = profileWebKitBootstrap
        self.pageActivationPerformance = PageActivationPerformanceMonitor(
            onFirstPaint: { [weak browserManager, profileWebKitBootstrap] in
                guard let browserManager else { return }
                BrowserPostStartupMaintenance.start(
                    history: browserManager.historyManager,
                    bookmarks: browserManager.bookmarkManager,
                    profiles: browserManager.profileManager.profiles,
                    browsingDataCleanupService: browserManager
                        .browsingDataCleanupService,
                    database: browserManager.database,
                    foregroundProfileID: { [weak browserManager] in
                        browserManager?.currentProfile?.id
                    }
                )
                let profileIDs = Set(
                    browserManager.tabCollectionMembershipOwner.allTabs()
                        .compactMap { $0.resolveProfile()?.id }
                )
                profileWebKitBootstrap.prepareAfterFirstPaint(
                    profileIDs: profileIDs
                )
            }
        )
    }

    func prepareRuntimeForStartupRecovery() {
        runtimeLifecycle().prepareForStartupRecovery()
    }

    func startRuntime(
        after preflight: ProfileRetirementStartupPreflightStatus
    ) {
        runtimeLifecycle().start(after: preflight)
    }

    func shutdown() {
        runtimeLifecycleStorage?.shutdown()
    }

    private func runtimeLifecycle() -> BrowserRuntimeLifecycle {
        if let runtimeLifecycleStorage {
            return runtimeLifecycleStorage
        }
        guard let browserManager else {
            preconditionFailure(
                "Browser startup services outlived their browser runtime"
            )
        }
        let lifecycle = BrowserRuntimeLifecycle.live(
            browserManager: browserManager,
            splitQuery: splitQuery
        )
        runtimeLifecycleStorage = lifecycle
        return lifecycle
    }
}
