import Foundation

@MainActor
final class BrowserTabSelectionPublicationTransaction {
    private let state: BrowserTabSelectionStateApplication
    private let extensionLifecycle: any TabExtensionLifecyclePort
    private let pageResidency: BrowserPageResidencyController
    private let activeSelection: TabActiveSelectionOwner
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        state: BrowserTabSelectionStateApplication,
        extensionLifecycle: any TabExtensionLifecyclePort,
        pageResidency: BrowserPageResidencyController,
        activeSelection: TabActiveSelectionOwner,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.state = state
        self.extensionLifecycle = extensionLifecycle
        self.pageResidency = pageResidency
        self.activeSelection = activeSelection
        self.persistence = persistence
    }

    func commit(
        _ tab: Tab,
        previousTabID: UUID?,
        in windowState: BrowserWindowState,
        persistSelection: Bool
    ) {
        let previousTab = previousTabID.flatMap {
            state.resolvedTab($0, in: windowState)
        }
        extensionLifecycle.notifyTabActivatedIfLoaded(
            newTab: tab,
            previous: previousTab
        )
        pageResidency.schedule(reason: "tab-selection-changed")

        if state.activeWindowID == windowState.id {
            activeSelection.updateActiveTabState(tab)
        }
        if persistSelection {
            persistence.persist(windowState)
        }
    }

    func persist(_ windowState: BrowserWindowState) {
        persistence.persist(windowState)
    }
}
