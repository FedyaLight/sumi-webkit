import AppKit
import WebKit

enum SumiNavigationHistoryDirection {
    case back
    case forward
}

struct SumiNavigationHistoryMenuItem {
    let id: UUID
    let url: URL?
    let title: String
    let backForwardItem: WKBackForwardListItem?
    let isCurrent: Bool

    init(
        id: UUID = UUID(),
        url: URL?,
        title: String,
        backForwardItem: WKBackForwardListItem? = nil,
        isCurrent: Bool
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.backForwardItem = backForwardItem
        self.isCurrent = isCurrent
    }

    @MainActor
    init(backForwardItem: WKBackForwardListItem, isCurrent: Bool) {
        self.init(
            url: backForwardItem.url,
            title: NavigationHistoryDisplayTitle.resolve(
                cachedTitle: backForwardItem.tabTitle,
                rawTitle: backForwardItem.title,
                url: backForwardItem.url
            ),
            backForwardItem: backForwardItem,
            isCurrent: isCurrent
        )
    }
}

@MainActor
struct SumiNavigationHistoryContext {
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let openURLInNewTab: (URL, Bool, Tab?) -> Void
    let openURLsInNewWindow: ([URL]) -> Void
}

enum SumiNavigationHistoryMenuModel {
    @MainActor
    static func items(
        direction: SumiNavigationHistoryDirection,
        tab: Tab?,
        webView: WKWebView?
    ) -> [SumiNavigationHistoryMenuItem] {
        guard let current = currentItem(tab: tab, webView: webView) else { return [] }

        let backItems = webView?.backForwardList.backList.map {
            SumiNavigationHistoryMenuItem(backForwardItem: $0, isCurrent: false)
        } ?? []
        let forwardItems = webView?.backForwardList.forwardList.map {
            SumiNavigationHistoryMenuItem(backForwardItem: $0, isCurrent: false)
        } ?? []

        return orderedItems(
            current: current,
            backItems: backItems,
            forwardItems: forwardItems,
            direction: direction
        )
    }

    static func orderedItems(
        current: SumiNavigationHistoryMenuItem,
        backItems: [SumiNavigationHistoryMenuItem],
        forwardItems: [SumiNavigationHistoryMenuItem],
        direction: SumiNavigationHistoryDirection
    ) -> [SumiNavigationHistoryMenuItem] {
        switch direction {
        case .back:
            return [current] + backItems.reversed()
        case .forward:
            return [current] + forwardItems
        }
    }

    @MainActor
    static func navigate(
        to item: SumiNavigationHistoryMenuItem,
        tab: Tab?,
        webView: WKWebView?,
        historyContext: SumiNavigationHistoryContext?,
        event: NSEvent?
    ) {
        guard let url = item.url else { return }

        let behavior = SumiLinkOpenBehavior(
            event: event,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: true
        )

        switch behavior {
        case .currentTab:
            guard !item.isCurrent else { return }

            if let backForwardItem = item.backForwardItem,
               let webView {
                webView.go(to: backForwardItem)
            } else {
                tab?.loadURL(url)
            }
        case .newTab(let selected):
            historyContext?.openURLInNewTab(url, selected, tab)
        case .newWindow:
            historyContext?.openURLsInNewWindow([url])
        }
    }

    @discardableResult
    @MainActor
    static func openURLIfModifiedClick(
        _ url: URL?,
        historyContext: SumiNavigationHistoryContext?,
        sourceTab: Tab?,
        event: NSEvent?
    ) -> Bool {
        guard let url else { return false }

        let behavior = SumiLinkOpenBehavior(
            event: event,
            switchToNewTabWhenOpenedPreference: false,
            canOpenLinkInCurrentTab: true
        )

        switch behavior {
        case .currentTab:
            return false
        case .newTab(let selected):
            historyContext?.openURLInNewTab(url, selected, sourceTab)
            return true
        case .newWindow:
            historyContext?.openURLsInNewWindow([url])
            return true
        }
    }

    @MainActor
    private static func currentItem(
        tab: Tab?,
        webView: WKWebView?
    ) -> SumiNavigationHistoryMenuItem? {
        if let currentBackForwardItem = webView?.backForwardList.currentItem {
            return SumiNavigationHistoryMenuItem(
                backForwardItem: currentBackForwardItem,
                isCurrent: true
            )
        }

        let url = webView?.url ?? tab?.url
        let title = NavigationHistoryDisplayTitle.resolve(
            cachedTitle: tab?.name,
            rawTitle: webView?.title,
            url: url
        )
        return SumiNavigationHistoryMenuItem(
            url: url,
            title: title,
            isCurrent: true
        )
    }
}

@MainActor
final class SumiNavigationHistoryMenuDelegate: NSObject, NSMenuDelegate {
    var direction: SumiNavigationHistoryDirection
    var historyContext: SumiNavigationHistoryContext?
    var tabProvider: (() -> Tab?)?
    var webViewProvider: (() -> WKWebView?)?

    private var items: [SumiNavigationHistoryMenuItem] = []

    init(direction: SumiNavigationHistoryDirection) {
        self.direction = direction
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        items = SumiNavigationHistoryMenuModel.items(
            direction: direction,
            tab: tabProvider?(),
            webView: webViewProvider?()
        )

        guard items.count > 1 else { return }

        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(menuItemAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = index
            menuItem.state = item.isCurrent ? .on : .off
            menuItem.isEnabled = item.url != nil
            menuItem.representedObject = item.id
            let profile = tabProvider?()?.resolveProfile()
            let partition = historyContext?.faviconService.partition(profile: profile)
                ?? BrowserManagerDataServices.productionFaviconService.partition(profile: profile)
            menuItem.image = SumiFaviconResolver.menuImage(
                for: item.url,
                partition: partition,
                faviconImageService: historyContext?.faviconImageService
                    ?? BrowserManagerDataServices.productionFaviconImageService
            )
            menu.addItem(menuItem)
        }
    }

    @objc private func menuItemAction(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }

        SumiNavigationHistoryMenuModel.navigate(
            to: items[sender.tag],
            tab: tabProvider?(),
            webView: webViewProvider?(),
            historyContext: historyContext,
            event: NSApp.currentEvent
        )
    }
}
