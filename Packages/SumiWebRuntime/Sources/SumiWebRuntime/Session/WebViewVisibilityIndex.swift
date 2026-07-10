//
//  WebViewVisibilityIndex.swift
//  SumiWebRuntime
//

import Foundation

@MainActor
final class WebViewVisibilityIndex {
    private var recentlyVisibleTabIDsByWindow: [UUID: [UUID]] = [:]

    func noteVisibleTabs(_ tabIDs: [UUID], in windowID: UUID) {
        guard tabIDs.isEmpty == false else { return }
        var mru = recentlyVisibleTabIDsByWindow[windowID] ?? []
        for tabID in tabIDs.reversed() {
            mru.removeAll { $0 == tabID }
            mru.insert(tabID, at: 0)
        }
        recentlyVisibleTabIDsByWindow[windowID] = Array(mru.prefix(32))
    }

    func removeTab(_ tabID: UUID, in windowID: UUID) {
        guard var mru = recentlyVisibleTabIDsByWindow[windowID] else { return }
        mru.removeAll { $0 == tabID }
        if mru.isEmpty {
            recentlyVisibleTabIDsByWindow.removeValue(forKey: windowID)
        } else {
            recentlyVisibleTabIDsByWindow[windowID] = mru
        }
    }

    func removeWindow(_ windowID: UUID) {
        recentlyVisibleTabIDsByWindow.removeValue(forKey: windowID)
    }

    func removeAll() {
        recentlyVisibleTabIDsByWindow.removeAll()
    }

    func rank(for owner: TrackedWebViewOwner) -> Int {
        recentlyVisibleTabIDsByWindow[owner.windowID]?
            .firstIndex(of: owner.tabID) ?? Int.max
    }
}
