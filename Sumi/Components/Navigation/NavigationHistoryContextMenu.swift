//
//  NavigationHistoryContextMenu.swift
//  Sumi
//
//  Created by Jonathan Caudill on 01/10/2025.
//

import SwiftUI
import WebKit

enum NavigationHistoryDisplayTitle {
    static func resolve(
        cachedTitle: String?,
        rawTitle: String?,
        url: URL?
    ) -> String {
        let normalizedCachedTitle = cachedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCachedTitle, !normalizedCachedTitle.isEmpty {
            return normalizedCachedTitle
        }

        let normalizedRawTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedRawTitle, !normalizedRawTitle.isEmpty {
            return normalizedRawTitle
        }

        return url?.host ?? "Untitled"
    }
}

struct NavigationHistoryContextMenu: View {
    let historyType: HistoryType
    let windowState: BrowserWindowState
    @EnvironmentObject var browserManager: BrowserManager
    @State private var historyItems: [NavigationHistoryContextMenuItem] = []

    enum HistoryType {
        case back
        case forward
    }

    var body: some View {
        Group {
            if !historyItems.isEmpty {
                ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, item in
                    Button(action: {
                        navigateToHistoryItem(item)
                    }) {
                        HStack(spacing: 8) {
                            // Directional icon
                            Image(systemName: historyType == .back ? "arrow.backward" : "arrow.forward")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 12)

                            // Title and URL
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                if let url = item.url {
                                    Text(urlDisplayString(url))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("No \(historyType == .back ? "back" : "forward") history")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadHistoryItems()
        }
        .onChange(of: windowState.currentTabId) { _, _ in
            refreshHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            guard let currentTab = currentTab else { return }
            guard let tabId = notification.userInfo?["tabId"] as? UUID else { return }
            guard tabId == currentTab.id else { return }
            refreshHistory()
        }
    }

    private func loadHistoryItems() {
        historyItems = loadHistoryItemsFresh()
    }

    private func loadHistoryItemsFresh() -> [NavigationHistoryContextMenuItem] {
        NavigationHistoryContextMenuEntries.historyItems(
            historyType: historyType,
            windowState: windowState,
            browserManager: browserManager
        )
    }

    private func refreshHistory() {
        loadHistoryItems()
    }

    private func navigateToHistoryItem(_ item: NavigationHistoryContextMenuItem) {
        NavigationHistoryContextMenuEntries.navigate(
            to: item,
            windowState: windowState,
            browserManager: browserManager
        )
    }

    private func urlDisplayString(_ url: URL) -> String {
        if let host = url.host {
            return host
        }
        return url.absoluteString.prefix(50) + "..."
    }

    private var currentTab: Tab? {
        let currentTabId = windowState.currentTabId
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == currentTabId }
        }
        guard let currentTabId else { return nil }
        return browserManager.tabManager.tab(for: currentTabId)
            ?? browserManager.currentTab(for: windowState)
    }
}

@MainActor
enum NavigationHistoryContextMenuEntries {
    static func make(
        historyType: NavigationHistoryContextMenu.HistoryType,
        windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> [SidebarContextMenuEntry] {
        let items = historyItems(
            historyType: historyType,
            windowState: windowState,
            browserManager: browserManager
        )

        guard items.isEmpty == false else {
            return [
                .action(
                    SidebarContextMenuAction(
                        title: "No \(historyType == .back ? "back" : "forward") history",
                        isEnabled: false,
                        classification: .presentationOnly,
                        action: {}
                    )
                )
            ]
        }

        let systemImage = historyType == .back ? "arrow.backward" : "arrow.forward"
        return items.map { item in
            .action(
                SidebarContextMenuAction(
                    title: menuTitle(for: item),
                    systemImage: systemImage,
                    classification: .stateMutationNonStructural,
                    action: {
                        navigate(
                            to: item,
                            windowState: windowState,
                            browserManager: browserManager
                        )
                    }
                )
            )
        }
    }

    static func historyItems(
        historyType: NavigationHistoryContextMenu.HistoryType,
        windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> [NavigationHistoryContextMenuItem] {
        guard let tab = currentTab(windowState: windowState, browserManager: browserManager),
              // Use assignedWebView as fallback to avoid triggering lazy initialization
              let webView = browserManager.getWebView(for: tab.id, in: windowState.id) ?? tab.assignedWebView
        else {
            return []
        }

        switch historyType {
        case .back:
            return webView.backForwardList.backList.reversed().map(NavigationHistoryContextMenuItem.init)
        case .forward:
            return webView.backForwardList.forwardList.map(NavigationHistoryContextMenuItem.init)
        }
    }

    static func navigate(
        to item: NavigationHistoryContextMenuItem,
        windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) {
        guard let tab = currentTab(windowState: windowState, browserManager: browserManager),
              // Use assignedWebView as fallback to avoid triggering lazy initialization
              let webView = browserManager.getWebView(for: tab.id, in: windowState.id) ?? tab.assignedWebView
        else { return }

        // Use WebKit's proper navigation history API to jump to the specific item.
        webView.go(to: item.backForwardItem)
    }

    private static func currentTab(
        windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> Tab? {
        let currentTabId = windowState.currentTabId
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == currentTabId }
        }
        guard let currentTabId else { return nil }
        return browserManager.tabManager.tab(for: currentTabId)
            ?? browserManager.currentTab(for: windowState)
    }

    private static func menuTitle(for item: NavigationHistoryContextMenuItem) -> String {
        guard let host = item.url?.host,
              !host.isEmpty,
              host != item.title
        else {
            return item.title
        }
        return "\(item.title) (\(host))"
    }
}

// MARK: - Navigation History Context Menu Item

/// A wrapper around WKBackForwardListItem that preserves the original WebKit navigation item
/// for proper navigation state management when jumping through history
struct NavigationHistoryContextMenuItem: Identifiable {
    let id: UUID
    let url: URL?
    let title: String
    let backForwardItem: WKBackForwardListItem

    init(from backForwardItem: WKBackForwardListItem) {
        self.id = UUID()
        self.url = backForwardItem.url
        self.title = NavigationHistoryDisplayTitle.resolve(
            cachedTitle: backForwardItem.tabTitle,
            rawTitle: backForwardItem.title,
            url: backForwardItem.url
        )
        self.backForwardItem = backForwardItem
    }
}
