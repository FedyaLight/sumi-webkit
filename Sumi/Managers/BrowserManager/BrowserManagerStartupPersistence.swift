import SwiftData

@MainActor
struct BrowserManagerStartupPersistence {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    static var production: BrowserManagerStartupPersistence {
        BrowserManagerStartupPersistence(container: SumiStartupPersistence.shared.container)
    }

    var mainContext: ModelContext {
        container.mainContext
    }
}
