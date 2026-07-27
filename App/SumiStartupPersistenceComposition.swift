@MainActor
enum SumiStartupPersistenceComposition {
    private static let startupPersistence = SumiStartupPersistence.shared

    static var database: SumiDatabase {
        startupPersistence.database
    }

    /// One process-wide startup persistence identity. Its permission store and
    /// autoplay adapter are lazy members of the same persistence domain.
    static let browserManagerStartupPersistence = BrowserManagerStartupPersistence(
        database: database
    )

    static func flushDatabase() throws {}
}

@MainActor
extension BrowserManagerStartupPersistence {
    static var production: BrowserManagerStartupPersistence {
        SumiStartupPersistenceComposition.browserManagerStartupPersistence
    }
}
