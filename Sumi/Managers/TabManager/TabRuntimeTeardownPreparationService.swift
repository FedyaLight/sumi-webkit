import Foundation

@MainActor
struct PreparedTabRuntimeTeardown {
    let tabs: [Tab]
    let runtime: RuntimePortRegistry

    var tabIds: Set<UUID> { Set(tabs.map(\.id)) }
}

/// Performs only the fallible physical phase of tab retirement. Structural
/// owners remain untouched until every unique tab has released its WebViews.
@MainActor
struct TabRuntimeTeardownPreparationService {
    func prepare(
        _ tabs: [Tab],
        using runtime: RuntimePortRegistry
    ) -> PreparedTabRuntimeTeardown? {
        var seen = Set<UUID>()
        let uniqueTabs = tabs.filter { seen.insert($0.id).inserted }
        guard uniqueTabs.allSatisfy({
            $0.performComprehensiveWebViewCleanup()
        }) else { return nil }
        return PreparedTabRuntimeTeardown(tabs: uniqueTabs, runtime: runtime)
    }
}
