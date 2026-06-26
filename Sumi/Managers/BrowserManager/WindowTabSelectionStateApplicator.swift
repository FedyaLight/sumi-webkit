//
//  WindowTabSelectionStateApplicator.swift
//  Sumi
//
//

import Foundation

struct WindowTabSelectionTargetState: Equatable {
    enum ShortcutMemoryUpdate: Equatable {
        case none
        case set(spaceId: UUID, pinId: UUID)
        case clear(spaceId: UUID)
    }

    enum RegularTabMemoryUpdate: Equatable {
        case none
        case set(spaceId: UUID, tabId: UUID)
    }

    let currentTabId: UUID?
    let currentSpaceId: UUID?
    let currentShortcutPinId: UUID?
    let currentShortcutPinRole: ShortcutPinRole?
    let isShowingEmptyState: Bool
    let shortcutMemoryUpdate: ShortcutMemoryUpdate
    let regularTabMemoryUpdate: RegularTabMemoryUpdate
}

struct WindowTabSelectionApplicationResult: Equatable {
    let previousTabId: UUID?
    let previousSpaceId: UUID?
    let stateDidChange: Bool
}

enum WindowTabSelectionPolicy {
    static func targetState(
        tabId: UUID,
        tabSpaceId: UUID?,
        isShortcutLiveInstance: Bool,
        shortcutPinId: UUID?,
        shortcutPinRole: ShortcutPinRole?,
        currentSpaceId: UUID?,
        updateSpaceFromTab: Bool,
        rememberSelection: Bool
    ) -> WindowTabSelectionTargetState {
        var resolvedSpaceId = currentSpaceId
        if updateSpaceFromTab,
           let tabSpaceId,
           currentSpaceId != tabSpaceId,
           !(isShortcutLiveInstance && shortcutPinRole == .essential) {
            resolvedSpaceId = tabSpaceId
        }

        let resolvedShortcutPinId = isShortcutLiveInstance ? shortcutPinId : nil
        let resolvedShortcutPinRole = isShortcutLiveInstance ? shortcutPinRole : nil

        let shortcutMemoryUpdate: WindowTabSelectionTargetState.ShortcutMemoryUpdate
        if rememberSelection, let resolvedSpaceId {
            if isShortcutLiveInstance,
               shortcutPinRole != .essential,
               let shortcutPinId {
                shortcutMemoryUpdate = .set(spaceId: resolvedSpaceId, pinId: shortcutPinId)
            } else if !isShortcutLiveInstance {
                shortcutMemoryUpdate = .clear(spaceId: resolvedSpaceId)
            } else {
                shortcutMemoryUpdate = .none
            }
        } else {
            shortcutMemoryUpdate = .none
        }

        let regularTabMemoryUpdate: WindowTabSelectionTargetState.RegularTabMemoryUpdate
        if rememberSelection, let resolvedSpaceId, !isShortcutLiveInstance {
            regularTabMemoryUpdate = .set(spaceId: resolvedSpaceId, tabId: tabId)
        } else {
            regularTabMemoryUpdate = .none
        }

        return WindowTabSelectionTargetState(
            currentTabId: tabId,
            currentSpaceId: resolvedSpaceId,
            currentShortcutPinId: resolvedShortcutPinId,
            currentShortcutPinRole: resolvedShortcutPinRole,
            isShowingEmptyState: false,
            shortcutMemoryUpdate: shortcutMemoryUpdate,
            regularTabMemoryUpdate: regularTabMemoryUpdate
        )
    }
}

@MainActor
enum WindowTabSelectionStateApplicator {
    static func apply(
        _ tab: Tab,
        to windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        rememberSelection: Bool
    ) -> WindowTabSelectionApplicationResult {
        let previousTabId = windowState.currentTabId
        let previousSpaceId = windowState.currentSpaceId
        let targetState = WindowTabSelectionPolicy.targetState(
            tabId: tab.id,
            tabSpaceId: tab.spaceId,
            isShortcutLiveInstance: tab.isShortcutLiveInstance,
            shortcutPinId: tab.shortcutPinId,
            shortcutPinRole: tab.shortcutPinRole,
            currentSpaceId: windowState.currentSpaceId,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )

        var stateDidChange = false
        stateDidChange = assignIfChanged(\.currentTabId, targetState.currentTabId, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.isShowingEmptyState, targetState.isShowingEmptyState, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.currentSpaceId, targetState.currentSpaceId, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.currentShortcutPinId, targetState.currentShortcutPinId, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.currentShortcutPinRole, targetState.currentShortcutPinRole, in: windowState) || stateDidChange
        stateDidChange = applyShortcutMemoryUpdate(targetState.shortcutMemoryUpdate, to: windowState) || stateDidChange
        stateDidChange = applyRegularTabMemoryUpdate(targetState.regularTabMemoryUpdate, to: windowState) || stateDidChange
        stateDidChange = recordSelectionHistoryIfNeeded(
            tab,
            targetState: targetState,
            rememberSelection: rememberSelection,
            in: windowState
        ) || stateDidChange

        return WindowTabSelectionApplicationResult(
            previousTabId: previousTabId,
            previousSpaceId: previousSpaceId,
            stateDidChange: stateDidChange
        )
    }

    @discardableResult
    private static func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<BrowserWindowState, Value>,
        _ value: Value,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard windowState[keyPath: keyPath] != value else { return false }
        windowState[keyPath: keyPath] = value
        return true
    }

    @discardableResult
    private static func applyShortcutMemoryUpdate(
        _ update: WindowTabSelectionTargetState.ShortcutMemoryUpdate,
        to windowState: BrowserWindowState
    ) -> Bool {
        switch update {
        case .none:
            return false
        case let .set(spaceId, pinId):
            guard windowState.selectedShortcutPinForSpace[spaceId] != pinId else { return false }
            windowState.selectedShortcutPinForSpace[spaceId] = pinId
            return true
        case let .clear(spaceId):
            guard windowState.selectedShortcutPinForSpace[spaceId] != nil else { return false }
            windowState.selectedShortcutPinForSpace[spaceId] = nil
            return true
        }
    }

    @discardableResult
    private static func applyRegularTabMemoryUpdate(
        _ update: WindowTabSelectionTargetState.RegularTabMemoryUpdate,
        to windowState: BrowserWindowState
    ) -> Bool {
        switch update {
        case .none:
            return false
        case let .set(spaceId, tabId):
            var didChange = false
            if windowState.activeTabForSpace[spaceId] != tabId {
                windowState.activeTabForSpace[spaceId] = tabId
                didChange = true
            }
            if windowState.recentRegularTabIdsBySpace[spaceId]?.first != tabId {
                windowState.recordRegularTabSelection(tabId, in: spaceId)
                didChange = true
            }
            return didChange
        }
    }

    @discardableResult
    private static func recordSelectionHistoryIfNeeded(
        _ tab: Tab,
        targetState: WindowTabSelectionTargetState,
        rememberSelection: Bool,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard rememberSelection,
              let spaceId = targetState.currentSpaceId
        else {
            return false
        }

        let item: BrowserWindowSelectionHistoryItem
        if tab.isShortcutLiveInstance {
            guard let pinId = tab.shortcutPinId else { return false }
            item = .shortcutPin(pinId)
        } else {
            item = .regularTab(tab.id)
        }

        return windowState.recordSelection(item, in: spaceId)
    }
}
