import Foundation

@MainActor
final class BrowserSidebarTabCommandOwner {
    private let requestUserTabActivationAction: @MainActor (Tab, BrowserWindowState) -> Void
    private let closeTabAction: @MainActor (Tab, BrowserWindowState) -> Void
    private let moveTabUpAction: @MainActor (UUID) -> Void
    private let moveTabDownAction: @MainActor (UUID) -> Void
    private let openForegroundTabAction: @MainActor (String, BrowserWindowState, UUID?) -> Tab?
    private let openNewTabOrFloatingBarAction: @MainActor (BrowserWindowState) -> Void
    private let duplicateTabAction: @MainActor (Tab, BrowserWindowState) -> Void

    init(
        requestUserTabActivation: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        closeTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        moveTabUp: @escaping @MainActor (UUID) -> Void,
        moveTabDown: @escaping @MainActor (UUID) -> Void,
        openForegroundTab: @escaping @MainActor (String, BrowserWindowState, UUID?) -> Tab?,
        openNewTabOrFloatingBar: @escaping @MainActor (BrowserWindowState) -> Void,
        duplicateTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void
    ) {
        self.requestUserTabActivationAction = requestUserTabActivation
        self.closeTabAction = closeTab
        self.moveTabUpAction = moveTabUp
        self.moveTabDownAction = moveTabDown
        self.openForegroundTabAction = openForegroundTab
        self.openNewTabOrFloatingBarAction = openNewTabOrFloatingBar
        self.duplicateTabAction = duplicateTab
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            requestUserTabActivation: { [weak browserManager] tab, windowState in
                browserManager?.requestUserTabActivation(tab, in: windowState)
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.tabLifecycleService.closeOrchestration.closeTab(tab, in: windowState)
            },
            moveTabUp: { [weak browserManager] tabId in
                browserManager?.tabManager.regularTabCollectionOwner.moveTabUp(tabId)
            },
            moveTabDown: { [weak browserManager] tabId in
                browserManager?.tabManager.regularTabCollectionOwner.moveTabDown(tabId)
            },
            openForegroundTab: { [weak browserManager] url, windowState, preferredSpaceId in
                browserManager?.tabLifecycleService.opening.openNewTab(
                    url: url,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            openNewTabOrFloatingBar: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.floatingBar.commit
                    .openNewTabSurface(in: windowState)
            },
            duplicateTab: { [weak browserManager] tab, windowState in
                browserManager?.tabLifecycleService.opening.duplicateTab(tab, in: windowState)
            }
        )
    }

    func requestUserTabActivation(_ tab: Tab, in windowState: BrowserWindowState) {
        requestUserTabActivationAction(tab, windowState)
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        closeTabAction(tab, windowState)
    }

    func moveTabUp(_ tabId: UUID) {
        moveTabUpAction(tabId)
    }

    func moveTabDown(_ tabId: UUID) {
        moveTabDownAction(tabId)
    }

    func openForegroundTab(
        _ url: String,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    ) -> Tab? {
        openForegroundTabAction(url, windowState, preferredSpaceId)
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        openNewTabOrFloatingBarAction(windowState)
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        duplicateTabAction(tab, windowState)
    }
}
