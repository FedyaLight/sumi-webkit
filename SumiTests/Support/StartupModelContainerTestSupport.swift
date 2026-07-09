import Foundation
import SwiftData

@testable import Sumi

/// Shared factory for the in-memory SwiftData container tests use to host a `TabManager`
/// (or any startup-schema fixture) without touching the on-disk store.
@MainActor
func makeInMemoryStartupModelContainer() throws -> ModelContainer {
    try ModelContainer(
        for: SumiStartupPersistence.schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}

@MainActor
func makeInMemoryTabManager(
    currentProfileId: @escaping () -> UUID? = { nil },
    windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
    windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
    visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
    materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in },
    requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in },
    loadPersistedState: Bool = false
) throws -> TabManager {
    let container = try makeInMemoryStartupModelContainer()
    return TabManager(
        runtimePorts: TestRuntimePorts.make(
            currentProfileId: currentProfileId,
            windowState: windowState,
            windows: windows,
            webViewLifecycle: TabManagerWebViewLifecycleService(
                materializeVisibleTabWebViewIfNeeded: materializeVisibleTabWebViewIfNeeded,
                requireRemoveAllWebViews: requireRemoveAllWebViews
            ),
            visibleSplitTabIds: visibleSplitTabIds
        ),
        context: container.mainContext,
        loadPersistedState: loadPersistedState
    )
}
