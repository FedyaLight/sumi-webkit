import Foundation

@MainActor
struct PreparedTabRuntimeTeardown {
    let tabs: [Tab]
    let runtime: RuntimePortRegistry

    var tabIds: Set<UUID> { Set(tabs.map(\.id)) }
}

/// Prepares terminal teardown outside reversible repository quarantine.
@MainActor
struct TabRuntimeTeardownPreparationService {
    func prepare(
        _ tabs: [Tab],
        using runtime: RuntimePortRegistry
    ) -> PreparedTabRuntimeTeardown? {
        let tabs = Self.orderedUnique(tabs)
        guard tabs.allSatisfy({
            $0.performComprehensiveWebViewCleanup()
        }) else { return nil }
        return PreparedTabRuntimeTeardown(tabs: tabs, runtime: runtime)
    }

    static func orderedUnique(_ tabs: [Tab]) -> [Tab] {
        var seen = Set<UUID>()
        return tabs.filter { seen.insert($0.id).inserted }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
