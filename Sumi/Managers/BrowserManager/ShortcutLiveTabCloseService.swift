import Foundation

/// Coordinates exact-residence admission, split/standalone retirement and
/// terminal history/notification publication for one live shortcut Tab.
@MainActor
final class ShortcutLiveTabCloseService {
    private let tabStore: any ShellSelectionTabStore
    private let splitClose: ShortcutLiveTabSplitCloseTransaction
    private let standaloneClose: ShortcutLiveTabStandaloneCloseTransaction
    private let publication: ShortcutLiveTabClosePublication

    init(
        tabStore: any ShellSelectionTabStore,
        splitClose: ShortcutLiveTabSplitCloseTransaction,
        standaloneClose: ShortcutLiveTabStandaloneCloseTransaction,
        publication: ShortcutLiveTabClosePublication
    ) {
        self.tabStore = tabStore
        self.splitClose = splitClose
        self.standaloneClose = standaloneClose
        self.publication = publication
    }

    @discardableResult
    func close(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        presentNotification: Bool = true
    ) -> Bool {
        guard tab.isShortcutLiveInstance,
              let pinID = tab.shortcutPinId,
              tabStore.liveShortcutTabs(in: windowState.id).contains(where: {
                  $0 === tab && $0.shortcutPinId == pinID
              }) else { return false }

        let splitTabCount: Int?
        switch splitClose.close(pinID: pinID, in: windowState) {
        case .committed(let unloadedTabCount):
            publication.captureHistory(for: tab, in: windowState)
            splitTabCount = unloadedTabCount
        case .rejected:
            return false
        case .notGrouped:
            guard standaloneClose.close(
                tab,
                pinID: pinID,
                in: windowState,
                publishingHistory: { [publication] in
                    publication.captureHistory(for: tab, in: windowState)
                }
            ) else { return false }
            splitTabCount = nil
        }

        if presentNotification {
            if let splitTabCount {
                publication.notifySplitViewUnload(
                    tabCount: splitTabCount,
                    in: windowState
                )
            } else {
                publication.notifyClose(in: windowState)
            }
        }
        return true
    }
}
