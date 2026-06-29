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

    static let autoplayPolicyStore = SumiAutoplayPolicyStoreAdapter(
        modelContainer: startupPersistence.container
    )

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

@MainActor
extension SumiAutoplayPolicyStoreAdapter {
    static var shared: SumiAutoplayPolicyStoreAdapter {
        SumiStartupPersistenceComposition.autoplayPolicyStore
    }
}
