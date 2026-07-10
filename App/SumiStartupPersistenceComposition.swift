import SwiftData

@MainActor
enum SumiStartupPersistenceComposition {
    private static let startupPersistence = SumiStartupPersistence.shared

    static var startupContainer: ModelContainer {
        startupPersistence.container
    }

    /// One process-wide startup persistence identity. Its permission store and
    /// autoplay adapter are lazy members of the same persistence domain.
    static let browserManagerStartupPersistence = BrowserManagerStartupPersistence(
        container: startupContainer
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
