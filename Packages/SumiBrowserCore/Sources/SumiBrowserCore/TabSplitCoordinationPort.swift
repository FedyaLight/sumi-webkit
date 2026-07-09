//
//  TabSplitCoordinationPort.swift
//  SumiBrowserCore
//
//  UUID-only split coordination port. Live adapters that capture BrowserManager
//  remain in the app target.
//

import Foundation

@MainActor
public protocol TabSplitCoordinationPort {
    func handleTabClosure(_ tabId: UUID)
    func visibleSplitTabIds(for windowId: UUID) -> [UUID]
    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool
    func updateActiveSplitSide(for tabId: UUID, in windowId: UUID)
}
