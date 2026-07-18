import AppKit
import SumiDomain

@MainActor
final class BrowserShortcutOverlayCommandDispatcher {
    private let find: FindManager
    private let dialogs: BrowserNativeDialogPresentationOwner
    private let floatingBar: FloatingBarPresentationService

    init(
        find: FindManager,
        dialogs: BrowserNativeDialogPresentationOwner,
        floatingBar: FloatingBarPresentationService
    ) {
        self.find = find
        self.dialogs = dialogs
        self.floatingBar = floatingBar
    }

    func dispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        switch action {
        case .findInPage:
            find.showFindBar(
                for: context.page?.tab,
                in: context.windowState.id
            )
        case .focusAddressBar:
            let prefill = context.page?.url.absoluteString ?? ""
            floatingBar.focus(
                in: context.windowState,
                prefill: prefill,
                navigateCurrentTab: true,
                reason: .keyboard
            )
        default:
            return false
        }
        return true
    }

    var isFindBarVisible: Bool { find.isFindBarVisible }

    func hideFindBar() {
        find.hideFindBar()
    }

    func isNativeModalPresented(in window: NSWindow) -> Bool {
        dialogs.isNativeModalPresented(in: window)
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        floatingBar.dismiss(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: true
        )
    }
}
