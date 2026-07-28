import Foundation

@MainActor
final class BrowserTabSelectionMaterializationOwner {
    private let state: BrowserTabSelectionStateApplication
    private let startupProtection: BrowserStartupProtectionRuntime
    private let compositor: TabCompositorManager
    private let trackedAdmission: TrackedWebViewAdmissionService
    private let windowVisuals: BrowserWindowVisualCoordinator

    init(
        state: BrowserTabSelectionStateApplication,
        startupProtection: BrowserStartupProtectionRuntime,
        compositor: TabCompositorManager,
        trackedAdmission: TrackedWebViewAdmissionService,
        windowVisuals: BrowserWindowVisualCoordinator
    ) {
        self.state = state
        self.startupProtection = startupProtection
        self.compositor = compositor
        self.trackedAdmission = trackedAdmission
        self.windowVisuals = windowVisuals
    }

    func scheduleIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        if tab.isUnloaded {
            tab.beginLoadingPresentationIfNeeded()
        }

        guard startupProtection.canMaterializeWebViewDuringStartup(tab) else {
            return
        }

        if tab.isUnloaded {
            tab.resolveProfile()?.prepareWebKitRuntime()
        }

        switch loadPolicy {
        case .immediate:
            materialize(tab, in: windowState)
        case .deferred:
            Task { @MainActor [weak self, weak tab, weak windowState] in
                guard let self, let tab, let windowState else { return }
                await Task.yield()
                guard state.currentTab(in: windowState)?.id == tab.id else {
                    return
                }
                materialize(tab, in: windowState)
                windowVisuals.refreshCompositor(for: windowState)
            }
        }
    }

    func materialize(_ tab: Tab, in windowState: BrowserWindowState) {
        compositor.markTabAccessed(tab.id)
        _ = trackedAdmission.webView(for: tab, in: windowState.id)
    }
}
