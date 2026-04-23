//
//  RecentlyClosedManager.swift
//  Sumi
//

import Foundation

@MainActor
final class RecentlyClosedManager: ObservableObject {
    private enum Const {
        static let maxItems = 30
    }

    @Published private(set) var items: [RecentlyClosedItem] = []

    var mostRecentItem: RecentlyClosedItem? {
        items.first
    }

    var canReopenRecentlyClosedItem: Bool {
        !items.isEmpty
    }

    func captureClosedTab(
        _ tab: Tab,
        sourceSpaceId: UUID?,
        currentURL: URL?,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        guard !tab.representsSumiEmptySurface else { return }

        let item = RecentlyClosedItem.tab(
            RecentlyClosedTabState(
                id: UUID(),
                title: tab.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? tab.url.absoluteString
                    : tab.name,
                url: tab.url,
                sourceSpaceId: sourceSpaceId,
                currentURL: currentURL,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                profileId: tab.profileId
            )
        )
        prepend(item)
    }

    func captureClosedWindow(
        title: String,
        session: WindowSessionSnapshot
    ) {
        let item = RecentlyClosedItem.window(
            RecentlyClosedWindowState(
                id: UUID(),
                title: title,
                session: session
            )
        )
        prepend(item)
    }

    func remove(_ item: RecentlyClosedItem) {
        items.removeAll { $0.id == item.id }
    }

    private func prepend(_ item: RecentlyClosedItem) {
        items.removeAll { existing in
            switch (existing, item) {
            case (.tab(let lhs), .tab(let rhs)):
                return lhs.url == rhs.url && lhs.profileId == rhs.profileId
            case (.window(let lhs), .window(let rhs)):
                return lhs.session == rhs.session
            default:
                return false
            }
        }
        items.insert(item, at: 0)
        if items.count > Const.maxItems {
            items = Array(items.prefix(Const.maxItems))
        }
    }
}
