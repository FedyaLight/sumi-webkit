import AppKit

@MainActor
final class BrowserWindowShellService {
    typealias ContentViewFactory = @MainActor (WindowRegistry, WebViewCoordinator, BrowserWindowState) -> NSView
    typealias EmptyStatePresenter = @MainActor (BrowserWindowState) -> Void

    struct Context {
        let windowRegistry: WindowRegistry
        let webViewCoordinator: WebViewCoordinator
        let permissionLifecycleController: SumiPermissionGrantLifecycleController
        let profileManager: ProfileManager
        let tabManager: TabManager
        let makeContentView: ContentViewFactory
        let showEmptyState: EmptyStatePresenter
    }

    func createNewWindow(using context: Context) {
        let windowState = BrowserWindowState()
        windowState.tabManager = context.tabManager

        let newWindow = makeWindow(
            title: "Sumi",
            contentView: context.makeContentView(
                context.windowRegistry,
                context.webViewCoordinator,
                windowState
            )
        )
        windowState.window = newWindow

        context.windowRegistry.register(windowState)
        context.windowRegistry.setActive(windowState)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func createIncognitoWindow(using context: Context) {
        let windowState = BrowserWindowState()
        windowState.isIncognito = true

        let ephemeralProfile = context.profileManager.createEphemeralProfile(for: windowState.id)
        windowState.ephemeralProfile = ephemeralProfile
        windowState.currentProfileId = ephemeralProfile.id

        let ephemeralSpace = Space(
            id: UUID(),
            name: "Incognito",
            icon: "🕶️",
            profileId: ephemeralProfile.id
        )
        ephemeralSpace.isEphemeral = true
        windowState.ephemeralSpaces.append(ephemeralSpace)
        windowState.currentSpaceId = ephemeralSpace.id
        windowState.tabManager = context.tabManager

        let newWindow = makeWindow(
            title: "Incognito - Sumi",
            contentView: context.makeContentView(
                context.windowRegistry,
                context.webViewCoordinator,
                windowState
            )
        )
        windowState.window = newWindow

        context.windowRegistry.register(windowState)
        context.windowRegistry.setActive(windowState)
        context.showEmptyState(windowState)

        newWindow.makeKeyAndOrderFront(nil)

        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Created incognito window: \(windowState.id)"
        )
    }

    func closeIncognitoWindow(
        _ windowState: BrowserWindowState,
        using context: Context
    ) async {
        guard windowState.isIncognito else { return }
        guard windowState.ephemeralProfile != nil
            || windowState.ephemeralTabs.isEmpty == false
            || windowState.ephemeralSpaces.isEmpty == false
        else {
            return
        }

        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Closing incognito window: \(windowState.id)"
        )

        for tab in windowState.ephemeralTabs {
            context.webViewCoordinator.removeAllWebViews(for: tab, closeActiveFullscreenMedia: true)
        }

        for tab in windowState.ephemeralTabs {
            tab.performComprehensiveWebViewCleanup()
        }

        let ephemeralTabs = windowState.ephemeralTabs
        let ephemeralSpaces = windowState.ephemeralSpaces
        let ephemeralProfileId = windowState.ephemeralProfile?.id.uuidString
        windowState.ephemeralTabs.removeAll()
        windowState.ephemeralSpaces.removeAll()
        windowState.currentTabId = nil

        if let ephemeralProfileId {
            context.permissionLifecycleController.handle(
                .profileClosed(
                    profilePartitionId: ephemeralProfileId,
                    reason: "incognito-profile-close"
                )
            )
        }
        await context.profileManager.removeEphemeralProfile(for: windowState.id)

        windowState.ephemeralProfile = nil
        windowState.currentSpaceId = nil

        #if DEBUG
        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Incognito window closed. Ephemeral tabs: \(ephemeralTabs.count), spaces: \(ephemeralSpaces.count)"
        )
        #endif

        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Incognito window fully closed and cleaned up: \(windowState.id)"
        )
    }

    func closeActiveWindow(in windowRegistry: WindowRegistry) {
        guard let activeWindow = windowRegistry.activeWindow else { return }
        closeWindow(activeWindow)
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        windowState.window?.performCloseFromBrowserChrome(nil)
    }

    func toggleFullScreenForActiveWindow(in windowRegistry: WindowRegistry) {
        windowRegistry.activeWindow?.window?.toggleFullScreen(nil)
    }

    private func makeWindow(title: String, contentView: NSView) -> NSWindow {
        let window = SumiBrowserWindow(
            contentRect: NSRect(origin: .zero, size: SumiBrowserWindowShellConfiguration.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = contentView
        window.title = title
        window.applyBrowserWindowShellConfiguration(shouldApplyInitialSize: false)
        window.center()
        return window
    }
}
