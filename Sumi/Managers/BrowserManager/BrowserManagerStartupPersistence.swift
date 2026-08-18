@MainActor
final class BrowserManagerStartupPersistence {
    let database: SumiDatabase

    /// The permission store and its synchronous autoplay view are one lazy
    /// persistence domain. Keeping them lazy is important for explicit
    /// `BrowserConfiguration` overrides: an override must not open a second path.
    private(set) lazy var permissionStore: any SumiPermissionStore =
        DatabasePermissionStore(database: database)

    private(set) lazy var autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter = {
        let adapter = SumiAutoplayPolicyStoreAdapter(
            persistentStore: permissionStore
        )
        adapter.seedCache(
            with: SumiAutoplayPolicyCacheBootstrap.loadAutoplayRecords(
                from: database
            )
        )
        return adapter
    }()

    init(database: SumiDatabase) {
        self.database = database
    }
}
