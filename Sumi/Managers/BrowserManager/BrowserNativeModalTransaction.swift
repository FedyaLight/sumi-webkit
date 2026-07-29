import AppKit
import Foundation

@MainActor
final class BrowserNativeModalTransaction {
    private let state: BrowserNativeModalPresentationState
    private let windows: WindowRegistry
    private let recovery: SidebarHostRecoveryHandling

    init(
        state: BrowserNativeModalPresentationState,
        windows: WindowRegistry,
        recovery: SidebarHostRecoveryHandling
    ) {
        self.state = state
        self.windows = windows
        self.recovery = recovery
    }

    @discardableResult
    func present(
        _ kind: BrowserNativeModalKind,
        windowState: BrowserWindowState? = nil,
        source: SidebarTransientPresentationSource? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Bool {
        dismiss(reason: "BrowserNativeModalTransaction.replace", invokeOnDismiss: true)

        let targetWindow = windowState ?? windows.activeWindow
        guard let windowID = source?.windowID ?? targetWindow?.id else {
            return false
        }
        let appKitWindow = source?.window?.parent
            ?? source?.window
            ?? targetWindow.flatMap { windows.appKitWindow(for: $0) }
            ?? modalPresentationWindow(for: source)
        let token: SidebarTransientSessionToken?
        if let source {
            token = source.coordinator?.beginSession(
                kind: .dialog,
                source: source,
                path: "BrowserNativeModalTransaction.present"
            )
        } else {
            token = nil
        }
        state.replace(
            with: BrowserNativeModalPresentation(
                windowID: windowID,
                window: appKitWindow,
                kind: kind,
                source: source,
                transientSessionToken: token,
                onDismiss: onDismiss
            )
        )
        return true
    }

    func dismiss(
        for windowID: UUID? = nil,
        reason: String,
        invokeOnDismiss: Bool
    ) {
        guard let presentation = state.presentation,
              windowID == nil || presentation.windowID == windowID else {
            return
        }
        state.replace(with: nil)
        if let token = presentation.transientSessionToken,
           let coordinator = presentation.source?.coordinator {
            coordinator.finishSession(token, reason: reason)
        } else {
            recovery.recover(in: presentation.window)
        }
        if invokeOnDismiss {
            presentation.onDismiss?()
        }
    }

    func isPresented(in windowID: UUID?) -> Bool {
        guard let presentation = state.presentation else { return false }
        guard let windowID else { return true }
        return presentation.windowID == windowID
    }

    func isPresented(in window: NSWindow?) -> Bool {
        guard let presentation = state.presentation else { return false }
        guard let window else { return true }
        return presentation.window === window
            || windows.appKitWindow(for: presentation.windowID) === window
    }

    private func modalPresentationWindow(
        for source: SidebarTransientPresentationSource?
    ) -> NSWindow? {
        source?.window?.parent
            ?? source?.window
            ?? windows.activeWindow.flatMap { windows.appKitWindow(for: $0) }
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
    }
}
