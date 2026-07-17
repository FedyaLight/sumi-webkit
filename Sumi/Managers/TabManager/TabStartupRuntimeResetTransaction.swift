import Foundation

@MainActor
final class TabStartupRuntimeResetTransaction {
    private let state: TabStateStore
    private let liveShortcutTabs: LiveShortcutTabRegistry
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        state: TabStateStore,
        liveShortcutTabs: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.state = state
        self.liveShortcutTabs = liveShortcutTabs
        self.runtimeConnection = runtimeConnection
        self.runtimeTeardown = runtimeTeardown
    }

    func prepare() -> PreparedTabStartupRuntimeReset? {
        let shortcutTabs = liveShortcutTabs.snapshot.values.flatMap(\.values)
        let regularTabs = state.spaces.spaces.flatMap {
            state.regularTabs.tabs(in: $0.id)
        }
        let closingTabs = shortcutTabs + regularTabs
        guard closingTabs.isEmpty == false else {
            return PreparedTabStartupRuntimeReset(
                regularTabIDs: Set(regularTabs.map(\.id)),
                teardown: nil
            )
        }
        guard let runtime = runtimeConnection.current,
              let prepared = runtimeTeardown.preparation.prepare(
                  closingTabs,
                  using: runtime
              ) else { return nil }
        return PreparedTabStartupRuntimeReset(
            regularTabIDs: Set(regularTabs.map(\.id)),
            teardown: prepared
        )
    }

    func finish(_ prepared: PreparedTabStartupRuntimeReset) {
        guard let teardown = prepared.teardown else { return }
        runtimeTeardown.finish(teardown)
    }
}
