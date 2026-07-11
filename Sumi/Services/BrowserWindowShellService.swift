import AppKit
import SumiDomain

@MainActor
final class BrowserWindowShellService {
    typealias ContentViewFactory = @MainActor (WindowRegistry, BrowserWindowState) -> NSView
    typealias EmptyStatePresenter = @MainActor (BrowserWindowState, Bool) -> Void
    typealias StateInitializer = @MainActor (BrowserWindowState) -> Void
    typealias RejectedRegistrationCompensation = @MainActor (
        BrowserWindowState
    ) -> Void

    struct Context {
        let windowRegistry: WindowRegistry
        let webViewLifecycle: WebViewLifecycleService
        let permissionLifecycleController: SumiPermissionGrantLifecycleController
        let profileManager: ProfileManager
        let tabManager: TabManager
        let makeContentView: ContentViewFactory
        let showEmptyState: EmptyStatePresenter
        let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    }

    @discardableResult
    func createNewWindow(using context: Context) -> BrowserWindowState {
        guard let windowState = createNewWindow(
            using: context,
            initializeBeforePublication: { _ in /* No-op. */ },
            validateAfterRegistration: { _ in true },
            compensateRejectedRegistration: { _ in /* No-op. */ }
        ) else {
            preconditionFailure("Ordinary window registration cannot be rejected")
        }
        return windowState
    }

    /// Initializes model state before content construction, then validates the
    /// synchronous registration workflow before activation or presentation.
    @discardableResult
    func createNewWindow(
        using context: Context,
        initializeBeforePublication: StateInitializer,
        validateAfterRegistration: @MainActor (BrowserWindowState) -> Bool,
        compensateRejectedRegistration: RejectedRegistrationCompensation
    ) -> BrowserWindowState? {
        let windowState = BrowserWindowState(
            sidebarRecoveryCoordinator: context.sidebarHostRecoveryCoordinator
        )
        windowState.tabManager = context.tabManager
        precondition(context.windowRegistry.windows[windowState.id] == nil)
        initializeBeforePublication(windowState)
        precondition(
            context.windowRegistry.windows[windowState.id] == nil,
            "Window initialization must not publish into WindowRegistry"
        )

        let newWindow = makeWindow(
            title: "Sumi",
            contentView: context.makeContentView(
                context.windowRegistry,
                windowState
            )
        )
        context.windowRegistry.bindAppKitWindow(newWindow, to: windowState)
        let registration = context.windowRegistry.register(windowState)
        precondition(
            registration == .registered,
            "A newly created shell must publish one new window state"
        )
        guard validateAfterRegistration(windowState) else {
            compensateRejectedRegistration(windowState)
            context.windowRegistry.rollbackRegistration(windowState)
            newWindow.close()
            return nil
        }
        context.windowRegistry.setActive(windowState)
        newWindow.makeKeyAndOrderFront(nil)
        return windowState
    }

    func createIncognitoWindow(using context: Context) {
        let windowState = BrowserWindowState(
            sidebarRecoveryCoordinator: context.sidebarHostRecoveryCoordinator
        )
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
                windowState
            )
        )
        context.windowRegistry.bindAppKitWindow(newWindow, to: windowState)
        context.windowRegistry.register(windowState)
        context.windowRegistry.setActive(windowState)
        context.showEmptyState(windowState, true)

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
            context.webViewLifecycle.removeAllWebViews(
                for: tab,
                closeActiveFullscreenMedia: true
            )
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
        closeWindow(activeWindow, in: windowRegistry)
    }

    func closeWindow(_ windowState: BrowserWindowState, in windowRegistry: WindowRegistry? = nil) {
        windowRegistry?.appKitWindow(for: windowState)?.performCloseFromBrowserChrome(nil)
    }

    func toggleFullScreenForActiveWindow(in windowRegistry: WindowRegistry) {
        guard let activeWindow = windowRegistry.activeWindow else { return }
        windowRegistry.appKitWindow(for: activeWindow)?.toggleFullScreen(nil)
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
