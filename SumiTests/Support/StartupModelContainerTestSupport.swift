import Foundation
import SumiWebRuntime
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
    defaultProfileId: @escaping () -> UUID? = { nil },
    profileExists: @escaping (UUID) -> Bool = { _ in true },
    profile: @escaping (UUID) -> Profile? = { _ in nil },
    windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
    windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
    visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
    primaryTrackedWindowId: @escaping (UUID) -> UUID? = { _ in nil },
    materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in /* No-op. */ },
    unloadTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
    requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in /* No-op. */ },
    notifyTabClosedIfLoaded: @escaping (Tab) -> Void = { _ in /* No-op. */ },
    updateTabVisibility: @escaping () -> Void = { /* No-op. */ },
    persistWindowSession: @escaping (BrowserWindowState) -> Void = { _ in /* No-op. */ },
    executeProfileAssignment: @escaping (
        Tab,
        Profile,
        DeferredWebViewProfileAssignmentIntent
    ) -> TabProfileAssignmentExecutionOutcome = { tab, _, intent in
        tab.profileAssignment.commit(intent) ? .committed : .stale
    },
    webViewLifecycle: TabManagerWebViewLifecycleService? = nil,
    webViewSessions: WebViewSessionRepository = WebViewSessionRepository(),
    loadPersistedState: Bool = false,
    attachRuntimePorts: Bool = true
) throws -> TabManager {
    let container = try makeInMemoryStartupModelContainer()
    let runtimePorts = TestRuntimePorts.make(
        currentProfileId: currentProfileId,
        defaultProfileId: defaultProfileId,
        profileExists: profileExists,
        profile: profile,
        windowState: windowState,
        windows: windows,
        windowStates: { windows().map(\.1) },
        updateTabVisibility: updateTabVisibility,
        webViewLifecycle: webViewLifecycle
            ?? TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                materializeVisibleTabWebViewIfNeeded: materializeVisibleTabWebViewIfNeeded,
                unloadTab: unloadTab,
                requireRemoveAllWebViews: requireRemoveAllWebViews,
                primaryTrackedWindowId: primaryTrackedWindowId,
                executeProfileAssignment: executeProfileAssignment
            ),
        visibleSplitTabIds: visibleSplitTabIds,
        notifyTabClosedIfLoaded: notifyTabClosedIfLoaded,
        persistWindowSession: persistWindowSession
    )
    return TabManager(
        runtimePorts: attachRuntimePorts ? runtimePorts : nil,
        context: container.mainContext,
        webViewSessions: webViewSessions,
        loadPersistedState: loadPersistedState
    )
}
