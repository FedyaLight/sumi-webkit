import SwiftData

@MainActor
struct BrowserManagerStartupPersistence {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    var mainContext: ModelContext {
        container.mainContext
    }
}
