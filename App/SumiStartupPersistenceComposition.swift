import SwiftData

@MainActor
enum SumiStartupPersistenceComposition {
    private static let startupPersistence = SumiStartupPersistence.shared

    static var startupContainer: ModelContainer {
        startupPersistence.container
    }

    static var browserManagerStartupPersistence: BrowserManagerStartupPersistence {
        BrowserManagerStartupPersistence(container: startupContainer)
    }

    /// Single SwiftData permission store shared by coordinator and autoplay adapter.
    static let persistentPermissionStore = SwiftDataPermissionStore(
        container: SumiStartupPersistence.shared.container
    )

    static let autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter = {
        let adapter = SumiAutoplayPolicyStoreAdapter(
            persistentStore: persistentPermissionStore
        )
        adapter.seedCache(
            with: SumiAutoplayPolicyCacheBootstrap.loadAutoplayRecords(
                from: SumiStartupPersistence.shared.container
            )
        )
        return adapter
    }()

    static func saveMainContext() throws {
        try startupContainer.mainContext.save()
    }
}

@MainActor
extension BrowserManagerStartupPersistence {
    static var production: BrowserManagerStartupPersistence {
        SumiStartupPersistenceComposition.browserManagerStartupPersistence
    }
}
