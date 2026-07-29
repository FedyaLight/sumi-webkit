import AppKit
import Foundation

@MainActor
final class BrowserNativeDialogPresentationOwner {
    private let modal: BrowserNativeModalTransaction
    private let commandPalette: CommandPalettePresentationService
    private let themes: BrowserWorkspaceThemeEditorOwner
    private let sharing: BrowserSharingPickerPresentationOwner
    private let alerts: BrowserNativeAlertPresenter

    init(
        modal: BrowserNativeModalTransaction,
        commandPalette: CommandPalettePresentationService,
        themes: BrowserWorkspaceThemeEditorOwner,
        sharing: BrowserSharingPickerPresentationOwner,
        alerts: BrowserNativeAlertPresenter
    ) {
        self.modal = modal
        self.commandPalette = commandPalette
        self.themes = themes
        self.sharing = sharing
        self.alerts = alerts
    }

    func requestCollapsedSidebarOverlayDismissal() {
        NotificationCenter.default.post(
            name: .sumiShouldHideCollapsedSidebarOverlay,
            object: nil
        )
    }

    func showQuitDialog() {
        requestCollapsedSidebarOverlayDismissal()
        commandPalette.dismissActiveWindow(preserveDraft: true)
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

    @discardableResult
    func presentDestructiveConfirmationAlert(
        title: String,
        message: String,
        confirmButtonTitle: String,
        onConfirm: @escaping @MainActor () -> Void
    ) -> Bool {
        prepareForNativeModalPresentation()
        return alerts.presentDestructiveConfirmation(
            title: title,
            message: message,
            confirmButtonTitle: confirmButtonTitle,
            onConfirm: onConfirm
        )
    }

    @discardableResult
    func presentNoticeAlert(
        title: String,
        subtitle: String?,
        message: String
    ) -> Bool {
        prepareForNativeModalPresentation()
        return alerts.presentNotice(
            title: title,
            subtitle: subtitle,
            message: message
        )
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
