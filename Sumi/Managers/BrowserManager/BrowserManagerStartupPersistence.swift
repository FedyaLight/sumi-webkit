import SwiftData

@MainActor
final class BrowserManagerStartupPersistence {
    let container: ModelContainer

    /// The permission store and its synchronous autoplay view are one lazy
    /// persistence domain. Keeping them lazy is important for explicit
    /// `BrowserConfiguration` overrides: an override must not open a second
    /// SwiftData path against the startup container.
    private(set) lazy var permissionStore: any SumiPermissionStore = SwiftDataPermissionStore(
        container: container
    )

    private(set) lazy var autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter = {
        let adapter = SumiAutoplayPolicyStoreAdapter(
            persistentStore: permissionStore
        )
        adapter.seedCache(
            with: SumiAutoplayPolicyCacheBootstrap.loadAutoplayRecords(
                from: container
            )
        )
        return adapter
    }()

    init(container: ModelContainer) {
        self.container = container
    }

    var mainContext: ModelContext {
        container.mainContext
    }
}
