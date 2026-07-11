import Foundation

/// Creates and closes native browser shells. Contextual link and WebKit-child
/// policy live in their own transactions instead of accumulating here.
@MainActor
final class BrowserWindowCommands {
    typealias ContextProvider = @MainActor () -> BrowserWindowShellService.Context
    typealias WindowRegistryProvider = @MainActor () -> WindowRegistry

    private let shells = BrowserWindowShellService()
    private let context: ContextProvider
    private let windowRegistry: WindowRegistryProvider
    private let discardRegistration: @MainActor (BrowserWindowState) -> Void
    private let discardActivation: @MainActor (BrowserWindowState) -> Void

    init(
        context: @escaping ContextProvider,
        windowRegistry: @escaping WindowRegistryProvider,
        discardRegistration: @escaping @MainActor (BrowserWindowState) -> Void,
        discardActivation: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.context = context
        self.windowRegistry = windowRegistry
        self.discardRegistration = discardRegistration
        self.discardActivation = discardActivation
    }

    @discardableResult
    func createNewWindow() -> BrowserWindowState? {
        shells.createNewWindow(using: context())
    }

    @discardableResult
    func createPreparedWindow(
        initialize: BrowserWindowShellService.StateInitializer,
        validateBeforeShell: @escaping @MainActor (
            BrowserWindowState
        ) -> Bool = { _ in true },
        validateBeforePublication: @escaping @MainActor (
            BrowserWindowState
        ) -> Bool = { $0.isAwaitingInitialSessionResolution == false },
        validateCommittedRegistration:
            @escaping BrowserWindowShellService.CommittedRegistrationValidator = { _ in true },
        discardPreparedState:
            BrowserWindowShellService.RejectedRegistrationCompensation,
        activate: Bool = true,
        presentAfterRegistration: Bool = true
    ) -> BrowserWindowState? {
        shells.createNewWindow(
            using: context(),
            initializeBeforePublication: initialize,
            validateBeforeShellPublication: validateBeforeShell,
            validateRestoredStateBeforePublication: validateBeforePublication,
            validateCommittedRegistration: validateCommittedRegistration,
            compensateRejectedRegistration: { [discardRegistration, discardActivation] window in
                discardRegistration(window)
                discardPreparedState(window)
                discardActivation(window)
            },
            activateAfterRegistration: activate,
            presentAfterRegistration: presentAfterRegistration
        )
    }

    @discardableResult
    func presentPreparedWindow(
        _ window: BrowserWindowState,
        activate: Bool
    ) -> Bool {
        shells.presentRegisteredWindow(
            window,
            in: windowRegistry(),
            activate: activate
        )
    }

    @discardableResult
    func createIncognitoWindow(activate: Bool = true) -> BrowserWindowState {
        shells.createIncognitoWindow(
            using: context(),
            activateAfterRegistration: activate
        )
    }

    func closeIncognitoWindow(_ window: BrowserWindowState) async {
        await shells.closeIncognitoWindow(window, using: context())
    }

    func closeActiveWindow() {
        shells.closeActiveWindow(in: windowRegistry())
    }

    func closeWindow(_ window: BrowserWindowState) {
        shells.closeWindow(window, in: windowRegistry())
    }

    func toggleFullScreenForActiveWindow() {
        shells.toggleFullScreenForActiveWindow(in: windowRegistry())
    }
}
