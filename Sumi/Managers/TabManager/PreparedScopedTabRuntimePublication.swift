@MainActor
final class PreparedScopedTabRuntimePublication {
    private let tabs: [Tab]
    private let runtime: RuntimePortRegistry
    private var isPublished = false

    init?(tabs: [Tab], runtime: RuntimePortRegistry) {
        guard tabs.allSatisfy({
            $0.webViewSession.allKnownWebViews.isEmpty
        }) else { return nil }
        self.tabs = tabs
        self.runtime = runtime
    }

    func publish() {
        guard isPublished == false else { return }
        isPublished = true
        tabs.forEach(runtime.notifyTabClosedIfLoaded)
    }
}
