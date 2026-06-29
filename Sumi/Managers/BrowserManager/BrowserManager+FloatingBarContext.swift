@MainActor
extension BrowserManager {
    var floatingBarBrowserContext: FloatingBarBrowserContext {
        floatingBarBrowserContextOwner.context
    }
}
