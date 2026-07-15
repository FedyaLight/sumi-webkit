@MainActor
final class ShortcutSplitLauncherWindowPersistence {
    private let structuralLookup: TabStructuralLookupCoordinator

    init(structuralLookup: TabStructuralLookupCoordinator) {
        self.structuralLookup = structuralLookup
    }

    func execute(
        _ states: [BrowserWindowState],
        using lease: TabRuntimePortLease
    ) {
        guard states.isEmpty == false else { return }
        let ordered = states.sorted { $0.id.uuidString < $1.id.uuidString }
        structuralLookup.runAfterCurrentBatch {
            ordered.forEach(lease.persistWindowSession(for:))
        }
    }
}
