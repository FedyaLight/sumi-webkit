import AppKit
import SumiDomain

@MainActor
final class BrowserShortcutOverlayCommandDispatcher {
    private let activePage: ActivePageResolver
    private let find: FindManager
    private let dialogs: BrowserNativeDialogPresentationOwner
    private let floatingBar: FloatingBarPresentationService

    init(
        activePage: ActivePageResolver,
        find: FindManager,
        dialogs: BrowserNativeDialogPresentationOwner,
        floatingBar: FloatingBarPresentationService
    ) {
        self.activePage = activePage
        self.find = find
        self.dialogs = dialogs
        self.floatingBar = floatingBar
    }

    func dispatch(_ action: ShortcutAction) -> Bool {
        switch action {
        case .findInPage:
            let resolution = activePage.resolveActiveWindow()
            find.showFindBar(
                for: resolution?.tab,
                in: resolution?.windowState.id
            )
        case .focusAddressBar:
            let prefill = activePage.resolveActiveWindow()?.url.absoluteString ?? ""
            floatingBar.focusActiveWindow(
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
