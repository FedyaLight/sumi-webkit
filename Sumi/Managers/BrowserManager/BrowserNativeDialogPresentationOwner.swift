import AppKit
import Foundation

@MainActor
final class BrowserNativeDialogPresentationOwner {
    private let windowRegistry: @MainActor @Sendable () -> WindowRegistry?
    private let nativeModalPresentation: @MainActor @Sendable () -> BrowserNativeModalPresentation?
    private let setNativeModalPresentation: @MainActor @Sendable (BrowserNativeModalPresentation?) -> Void
    private let postCollapsedSidebarOverlayDismissal: @MainActor @Sendable () -> Void
    private let dismissFloatingBarForActiveWindow: @MainActor @Sendable (Bool) -> Void
    private let dismissThemePickerDiscardingIfNeeded: @MainActor @Sendable () -> Void
    private let dismissThemePickerCommittingIfNeeded: @MainActor @Sendable () -> Void
    private let terminateApplication: @MainActor @Sendable () -> Void
    private let keyWindow: @MainActor @Sendable () -> NSWindow?
    private let mainWindow: @MainActor @Sendable () -> NSWindow?
    private let recoverSidebarHost: @MainActor @Sendable (NSWindow?) -> Void
    private let presentSharingServicePickerAction: @MainActor @Sendable ([Any], SidebarTransientPresentationSource) -> Void

    var currentPresentation: BrowserNativeModalPresentation? {
        nativeModalPresentation()
    }

    init(
        windowRegistry: @escaping @MainActor @Sendable () -> WindowRegistry?,
        nativeModalPresentation: @escaping @MainActor @Sendable () -> BrowserNativeModalPresentation?,
        setNativeModalPresentation: @escaping @MainActor @Sendable (BrowserNativeModalPresentation?) -> Void,
        postCollapsedSidebarOverlayDismissal: @escaping @MainActor @Sendable () -> Void,
        dismissFloatingBarForActiveWindow: @escaping @MainActor @Sendable (Bool) -> Void,
        dismissThemePickerDiscardingIfNeeded: @escaping @MainActor @Sendable () -> Void,
        dismissThemePickerCommittingIfNeeded: @escaping @MainActor @Sendable () -> Void,
        terminateApplication: @escaping @MainActor @Sendable () -> Void,
        keyWindow: @escaping @MainActor @Sendable () -> NSWindow?,
        mainWindow: @escaping @MainActor @Sendable () -> NSWindow?,
        recoverSidebarHost: @escaping @MainActor @Sendable (NSWindow?) -> Void,
        presentSharingServicePicker: @escaping @MainActor @Sendable ([Any], SidebarTransientPresentationSource) -> Void
    ) {
        self.windowRegistry = windowRegistry
        self.nativeModalPresentation = nativeModalPresentation
        self.setNativeModalPresentation = setNativeModalPresentation
        self.postCollapsedSidebarOverlayDismissal = postCollapsedSidebarOverlayDismissal
        self.dismissFloatingBarForActiveWindow = dismissFloatingBarForActiveWindow
        self.dismissThemePickerDiscardingIfNeeded = dismissThemePickerDiscardingIfNeeded
        self.dismissThemePickerCommittingIfNeeded = dismissThemePickerCommittingIfNeeded
        self.terminateApplication = terminateApplication
        self.keyWindow = keyWindow
        self.mainWindow = mainWindow
        self.recoverSidebarHost = recoverSidebarHost
        self.presentSharingServicePickerAction = presentSharingServicePicker
    }

    func requestCollapsedSidebarOverlayDismissal() {
        postCollapsedSidebarOverlayDismissal()
    }

    func showQuitDialog() {
        requestCollapsedSidebarOverlayDismissal()
        dismissFloatingBarForActiveWindow(true)
        dismissThemePickerCommittingIfNeeded()
        terminateApplication()
    }

    func presentBrowsingDataSheet(windowState: BrowserWindowState? = nil) {
        _ = presentNativeModal(.browsingData, windowState: windowState)
    }

    @discardableResult
    func presentBasicAuthSheet(
        _ session: BasicAuthSheetSession,
        in windowState: BrowserWindowState?
    ) -> Bool {
        presentNativeModal(
            .basicAuth(session),
            windowState: windowState,
            onDismiss: {
                session.cancel()
            }
        )
    }

    func presentNoticeSheet(
        _ notice: BrowserNoticeSheetModel,
        source: SidebarTransientPresentationSource? = nil
    ) {
        _ = presentNativeModal(.notice(notice), source: source)
    }

    func dismissNativeModalPresentation() {
        dismissNativeModalPresentation(
            for: nil,
            reason: "BrowserManager.dismissNativeModalPresentation",
            invokeOnDismiss: false
        )
    }

    func nativeModalPresentationBindingDismissed(for windowID: UUID) {
        dismissNativeModalPresentation(
            for: windowID,
            reason: "BrowserManager.nativeModalPresentationBindingDismissed",
            invokeOnDismiss: true
        )
    }

    func isNativeModalPresented(in windowID: UUID?) -> Bool {
        guard let presentation = nativeModalPresentation() else { return false }
        guard let windowID else { return true }
        return presentation.windowID == windowID
    }

    func isNativeModalPresented(in window: NSWindow?) -> Bool {
        guard let presentation = nativeModalPresentation() else { return false }
        guard let window else { return true }
        if let presentedWindow = presentation.window {
            return presentedWindow === window
        }
        return windowRegistry()?.appKitWindow(for: presentation.windowID) === window
    }

    /// Compatibility forward to `BrowserSharingPickerPresentationOwner`.
    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        presentSharingServicePickerAction(items, source)
    }

    private func prepareForNativeModalPresentation() {
        requestCollapsedSidebarOverlayDismissal()
        dismissThemePickerDiscardingIfNeeded()
    }

    @discardableResult
    private func presentNativeModal(
        _ kind: BrowserNativeModalKind,
        windowState: BrowserWindowState? = nil,
        source: SidebarTransientPresentationSource? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Bool {
        prepareForNativeModalPresentation()
        dismissNativeModalPresentation(
            for: nil,
            reason: "BrowserManager.presentNativeModalReplacingExisting",
            invokeOnDismiss: true
        )

        let targetWindowState = windowState ?? windowRegistry()?.activeWindow
        let windowID = source?.windowID ?? targetWindowState?.id
        guard let windowID else { return false }

        let window = source?.window?.parent
            ?? source?.window
            ?? targetWindowState.flatMap { windowRegistry()?.appKitWindow(for: $0) }
            ?? modalPresentationWindow(for: source)
        let transientSessionToken: SidebarTransientSessionToken?
        if let source {
            transientSessionToken = source.coordinator?.beginSession(
                kind: .dialog,
                source: source,
                path: "BrowserManager.presentNativeModal"
            )
        } else {
            transientSessionToken = nil
        }

        setNativeModalPresentation(
            BrowserNativeModalPresentation(
                windowID: windowID,
                window: window,
                kind: kind,
                source: source,
                transientSessionToken: transientSessionToken,
                onDismiss: onDismiss
            )
        )
        return true
    }

    private func dismissNativeModalPresentation(
        for windowID: UUID?,
        reason: String,
        invokeOnDismiss: Bool
    ) {
        guard let presentation = nativeModalPresentation() else { return }
        guard windowID == nil || presentation.windowID == windowID else { return }

        setNativeModalPresentation(nil)

        if let transientSessionToken = presentation.transientSessionToken,
           let coordinator = presentation.source?.coordinator {
            coordinator.finishSession(
                transientSessionToken,
                reason: reason
            )
        } else {
            recoverSidebarHost(presentation.window)
        }

        if invokeOnDismiss {
            presentation.onDismiss?()
        }
    }

    private func modalPresentationWindow(
        for source: SidebarTransientPresentationSource? = nil
    ) -> NSWindow? {
        source?.window?.parent
            ?? source?.window
            ?? windowRegistry()?.activeWindow.flatMap { windowRegistry()?.appKitWindow(for: $0) }
            ?? keyWindow()
            ?? mainWindow()
    }
}
