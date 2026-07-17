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
    typealias CommittedRegistrationValidator = @MainActor (
        BrowserWindowState
    ) -> Bool

    struct Context {
        let windowRegistry: WindowRegistry
        let permissionLifecycleController: SumiPermissionGrantLifecycleController
        let profileManager: ProfileManager
        let tabResidences: BrowserTabResidenceAuthority
        let makeContentView: ContentViewFactory
        let showEmptyState: EmptyStatePresenter
        let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    }

    @discardableResult
    func createNewWindow(using context: Context) -> BrowserWindowState? {
        createNewWindow(
            using: context,
            initializeBeforePublication: { _ in /* No-op. */ },
            validateRestoredStateBeforePublication: { _ in true },
            compensateRejectedRegistration: { _ in /* No-op. */ }
        )
    }

    /// Initializes model state before content construction, then validates the
    /// synchronous registration workflow before activation or presentation.
    @discardableResult
    func createNewWindow(
        using context: Context,
        initializeBeforePublication: StateInitializer,
        validateBeforeShellPublication: @MainActor (
            BrowserWindowState
        ) -> Bool = { _ in true },
        validateRestoredStateBeforePublication: @MainActor (
            BrowserWindowState
        ) -> Bool,
        validateCommittedRegistration:
            @escaping CommittedRegistrationValidator = { _ in true },
        compensateRejectedRegistration: RejectedRegistrationCompensation,
        activateAfterRegistration: Bool = true,
        presentAfterRegistration: Bool = true
    ) -> BrowserWindowState? {
        let windowState = BrowserWindowState(
            sidebarRecoveryCoordinator: context.sidebarHostRecoveryCoordinator
        )
        context.tabResidences.establishResidenceSession(on: windowState)
        guard context.windowRegistry.windows[windowState.id] == nil else {
            compensateRejectedRegistration(windowState)
            return nil
        }
        initializeBeforePublication(windowState)
        guard context.windowRegistry.windows[windowState.id] == nil else {
            _ = context.windowRegistry.discardRejectedRegistration(windowState)
            compensateRejectedRegistration(windowState)
            return nil
        }
        guard validateBeforeShellPublication(windowState) else {
            compensateRejectedRegistration(windowState)
            return nil
        }

        let newWindow = makeWindow(
            title: windowState.isIncognito ? "Incognito - Sumi" : "Sumi",
            contentView: context.makeContentView(
                context.windowRegistry,
                windowState
            )
        )
        context.windowRegistry.bindAppKitWindow(newWindow, to: windowState)
        let registration = context.windowRegistry.beginRegistration(windowState)
        guard registration == .registered else {
            _ = context.windowRegistry.discardRejectedRegistration(windowState)
            compensateRejectedRegistration(windowState)
            newWindow.close()
            return nil
        }
        guard validateRestoredStateBeforePublication(windowState) else {
            _ = context.windowRegistry.rollbackProvisionalRegistration(
                windowState
            )
            compensateRejectedRegistration(windowState)
            newWindow.close()
            return nil
        }
        guard context.windowRegistry.commitRegistration(
            windowState,
            validatePublication: validateCommittedRegistration
        ) else {
            _ = context.windowRegistry.discardRejectedRegistration(windowState)
            compensateRejectedRegistration(windowState)
            newWindow.close()
            return nil
        }
        if presentAfterRegistration {
            presentRegisteredWindow(
                windowState,
                in: context.windowRegistry,
                activate: activateAfterRegistration
            )
        }
        return windowState
    }

    /// Presents only the exact shell that still belongs to the registered
    /// model. Activation observers may synchronously close the window, so the
    /// binding is revalidated before crossing into AppKit presentation.
    @discardableResult
    func presentRegisteredWindow(
        _ windowState: BrowserWindowState,
        in windowRegistry: WindowRegistry,
        activate: Bool
    ) -> Bool {
        guard windowRegistry.windows[windowState.id] === windowState,
              let window = windowRegistry.appKitWindow(for: windowState)
        else {
            return false
        }
        if activate {
            windowRegistry.setActive(windowState)
            guard windowRegistry.windows[windowState.id] === windowState,
                  windowRegistry.appKitWindow(for: windowState) === window
            else {
                return false
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        return windowRegistry.windows[windowState.id] === windowState
            && windowRegistry.appKitWindow(for: windowState) === window
    }

    @discardableResult
    func createIncognitoWindow(
        using context: Context,
        activateAfterRegistration: Bool = true
    ) -> BrowserWindowState {
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
        windowState.appendEphemeralSpace(ephemeralSpace)
        windowState.currentSpaceId = ephemeralSpace.id
        context.tabResidences.establishResidenceSession(on: windowState)

        let newWindow = makeWindow(
            title: "Incognito - Sumi",
            contentView: context.makeContentView(
                context.windowRegistry,
                windowState
            )
        )
        context.windowRegistry.bindAppKitWindow(newWindow, to: windowState)
        context.windowRegistry.register(windowState)
        context.showEmptyState(windowState, true)

        presentRegisteredWindow(
            windowState,
            in: context.windowRegistry,
            activate: activateAfterRegistration
        )
        RuntimeDiagnostics.emit(
            "🔒 [WindowShellService] Created incognito window: \(windowState.id)"
        )
        return windowState
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
            tab.performComprehensiveWebViewCleanup()
        }

        let ephemeralTabs = windowState.ephemeralTabs
        let ephemeralSpaces = windowState.ephemeralSpaces
        windowState.removeAllEphemeralTabs()
        windowState.removeAllEphemeralSpaces()
        windowState.currentTabId = nil

        let releasedProfileID = await context.profileManager
            .releaseEphemeralProfile(for: windowState.id)
        if let releasedProfileID {
            context.permissionLifecycleController.handle(
                .profileClosed(
                    profilePartitionId: releasedProfileID.uuidString,
                    reason: "incognito-profile-close"
                )
            )
        }

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
