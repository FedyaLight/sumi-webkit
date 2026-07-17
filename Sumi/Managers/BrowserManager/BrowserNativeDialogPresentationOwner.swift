import AppKit
import Foundation

@MainActor
final class BrowserNativeDialogPresentationOwner {
    private let modal: BrowserNativeModalTransaction
    private let floatingBar: FloatingBarPresentationService
    private let themes: BrowserWorkspaceThemeEditorOwner
    private let sharing: BrowserSharingPickerPresentationOwner

    init(
        modal: BrowserNativeModalTransaction,
        floatingBar: FloatingBarPresentationService,
        themes: BrowserWorkspaceThemeEditorOwner,
        sharing: BrowserSharingPickerPresentationOwner
    ) {
        self.modal = modal
        self.floatingBar = floatingBar
        self.themes = themes
        self.sharing = sharing
    }

    var currentPresentation: BrowserNativeModalPresentation? {
        modal.currentPresentation
    }

    func requestCollapsedSidebarOverlayDismissal() {
        NotificationCenter.default.post(
            name: .sumiShouldHideCollapsedSidebarOverlay,
            object: nil
        )
    }

    func showQuitDialog() {
        requestCollapsedSidebarOverlayDismissal()
        floatingBar.dismissActiveWindow(preserveDraft: true)
        themes.dismissThemePickerCommittingIfNeeded()
        NSApplication.shared.terminate(nil)
    }

    func presentBrowsingDataSheet(windowState: BrowserWindowState? = nil) {
        prepareForNativeModalPresentation()
        _ = modal.present(.browsingData, windowState: windowState)
    }

    @discardableResult
    func presentBasicAuthSheet(
        _ session: BasicAuthSheetSession,
        in windowState: BrowserWindowState?
    ) -> Bool {
        prepareForNativeModalPresentation()
        return modal.present(
            .basicAuth(session),
            windowState: windowState,
            onDismiss: session.cancel
        )
    }

    @discardableResult
    func presentNoticeSheet(
        _ notice: BrowserNoticeSheetModel,
        source: SidebarTransientPresentationSource? = nil
    ) -> Bool {
        prepareForNativeModalPresentation()
        return modal.present(.notice(notice), source: source)
    }

    func dismissNativeModalPresentation() {
        modal.dismiss(
            reason: "BrowserNativeDialogPresentationOwner.dismiss",
            invokeOnDismiss: false
        )
    }

    func nativeModalPresentationBindingDismissed(for windowID: UUID) {
        modal.dismiss(
            for: windowID,
            reason: "BrowserNativeDialogPresentationOwner.bindingDismissed",
            invokeOnDismiss: true
        )
    }

    func isNativeModalPresented(in windowID: UUID?) -> Bool {
        modal.isPresented(in: windowID)
    }

    func isNativeModalPresented(in window: NSWindow?) -> Bool {
        modal.isPresented(in: window)
    }

    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        sharing.presentSharingServicePicker(items, source: source)
    }

    private func prepareForNativeModalPresentation() {
        requestCollapsedSidebarOverlayDismissal()
        themes.dismissThemePickerDiscardingIfNeeded()
    }
}
