import Foundation
import SwiftData
import SumiWebRuntime

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
    defaultProfileId: @escaping () -> UUID? = { nil },
    profileExists: @escaping (UUID) -> Bool = { _ in true },
    profile: @escaping (UUID) -> Profile? = { _ in nil },
    windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
    windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
    visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
    primaryTrackedWindowId: @escaping (UUID) -> UUID? = { _ in nil },
    materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in },
    requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in },
    executeProfileAssignment: @escaping (
        Tab,
        Profile,
        DeferredWebViewProfileAssignmentIntent
    ) -> TabProfileAssignmentExecutionOutcome = { tab, _, intent in
        tab.commitProfileAssignmentIntent(intent) ? .committed : .stale
    },
    webViewSessions: WebViewSessionRepository = WebViewSessionRepository(),
    loadPersistedState: Bool = false
) throws -> TabManager {
    let container = try makeInMemoryStartupModelContainer()
    return TabManager(
        runtimePorts: TestRuntimePorts.make(
            currentProfileId: currentProfileId,
            defaultProfileId: defaultProfileId,
            profileExists: profileExists,
            profile: profile,
            windowState: windowState,
            windows: windows,
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                materializeVisibleTabWebViewIfNeeded: materializeVisibleTabWebViewIfNeeded,
                requireRemoveAllWebViews: requireRemoveAllWebViews,
                primaryTrackedWindowId: primaryTrackedWindowId,
                executeProfileAssignment: executeProfileAssignment
            ),
            visibleSplitTabIds: visibleSplitTabIds
        ),
        context: container.mainContext,
        webViewSessions: webViewSessions,
        loadPersistedState: loadPersistedState
    )
}
