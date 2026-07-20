//
//  WindowTabSelectionStateApplicator.swift
//  Sumi
//
//

import Foundation
import SumiDomain

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
        var state = windowState.unpublishedShortcutMutationState
        let result = apply(
            tab,
            to: &state,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )
        if result.stateDidChange {
            precondition(windowState.commitShortcutMutationState(state))
        }
        return result
    }

    static func apply(
        _ tab: Tab,
        to state: inout BrowserWindowShortcutMutationState,
        updateSpaceFromTab: Bool,
        rememberSelection: Bool
    ) -> WindowTabSelectionApplicationResult {
        let previousTabId = state.currentTabId
        let previousSpaceId = state.currentSpaceId
        let targetState = WindowTabSelectionPolicy.targetState(
            tabId: tab.id,
            tabSpaceId: tab.spaceId,
            isShortcutLiveInstance: tab.isShortcutLiveInstance,
            shortcutPinId: tab.shortcutPinId,
            shortcutPinRole: tab.shortcutPinRole,
            currentSpaceId: state.currentSpaceId,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )

        var stateDidChange = false
        if state.webKitChildWindowIdentity != nil,
           state.webKitChildWindowIdentity?.initialTabID != tab.id {
            state.webKitChildWindowIdentity = nil
            stateDidChange = true
        }
        stateDidChange = assignIfChanged(
            \.currentTabId,
            targetState.currentTabId,
            in: &state
        ) || stateDidChange
        stateDidChange = assignIfChanged(
            \.isShowingEmptyState,
            targetState.isShowingEmptyState,
            in: &state
        ) || stateDidChange
        stateDidChange = assignIfChanged(
            \.currentSpaceId,
            targetState.currentSpaceId,
            in: &state
        ) || stateDidChange
        stateDidChange = assignIfChanged(
            \.currentShortcutPinId,
            targetState.currentShortcutPinId,
            in: &state
        ) || stateDidChange
        stateDidChange = assignIfChanged(
            \.currentShortcutPinRole,
            targetState.currentShortcutPinRole,
            in: &state
        ) || stateDidChange
        stateDidChange = applyShortcutMemoryUpdate(
            targetState.shortcutMemoryUpdate,
            to: &state
        ) || stateDidChange
        stateDidChange = applyRegularTabMemoryUpdate(
            targetState.regularTabMemoryUpdate,
            to: &state
        ) || stateDidChange
        stateDidChange = recordSelectionHistoryIfNeeded(
            tab,
            targetState: targetState,
            rememberSelection: rememberSelection,
            in: &state
        ) || stateDidChange

        return WindowTabSelectionApplicationResult(
            previousTabId: previousTabId,
            previousSpaceId: previousSpaceId,
            stateDidChange: stateDidChange
        )
    }

    static func applyFallback(
        _ tab: Tab,
        to state: inout BrowserWindowShortcutMutationState,
        splitMembership: SplitGroupMembershipQuery,
        updateSpaceFromTab: Bool,
        rememberSelection: Bool
    ) -> WindowTabSelectionApplicationResult {
        let result = apply(
            tab,
            to: &state,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )
        let memberID = splitMembership.memberID(for: tab)
        let splitSelection = splitMembership.group(containing: memberID).map {
            WindowSplitSelection(
                groupID: $0.id,
                activeMemberID: memberID
            )
        }
        let splitStateDidChange = assignIfChanged(
            \.splitSelection,
            splitSelection,
            in: &state
        )
        return WindowTabSelectionApplicationResult(
            previousTabId: result.previousTabId,
            previousSpaceId: result.previousSpaceId,
            stateDidChange: result.stateDidChange || splitStateDidChange
        )
    }

    @discardableResult
    private static func assignIfChanged<Value: Equatable>(
        _ keyPath: WritableKeyPath<BrowserWindowShortcutMutationState, Value>,
        _ value: Value,
        in state: inout BrowserWindowShortcutMutationState
    ) -> Bool {
        guard state[keyPath: keyPath] != value else { return false }
        state[keyPath: keyPath] = value
        return true
    }

    @discardableResult
    private static func applyShortcutMemoryUpdate(
        _ update: WindowTabSelectionTargetState.ShortcutMemoryUpdate,
        to state: inout BrowserWindowShortcutMutationState
    ) -> Bool {
        switch update {
        case .none:
            return false
        case let .set(spaceId, pinId):
            guard state.selectedShortcutPinForSpace[spaceId] != pinId else {
                return false
            }
            state.selectedShortcutPinForSpace[spaceId] = pinId
            return true
        case let .clear(spaceId):
            guard state.selectedShortcutPinForSpace[spaceId] != nil else {
                return false
            }
            state.selectedShortcutPinForSpace[spaceId] = nil
            return true
        }
    }

    @discardableResult
    private static func applyRegularTabMemoryUpdate(
        _ update: WindowTabSelectionTargetState.RegularTabMemoryUpdate,
        to state: inout BrowserWindowShortcutMutationState
    ) -> Bool {
        switch update {
        case .none:
            return false
        case let .set(spaceId, tabId):
            var didChange = false
            if state.activeTabForSpace[spaceId] != tabId {
                state.activeTabForSpace[spaceId] = tabId
                didChange = true
            }
            if state.selectionHistory.recentRegularTabIdsBySpace[spaceId]?.first
                != tabId {
                state.selectionHistory.recordRegularTabSelection(
                    tabId,
                    in: spaceId
                )
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
        in state: inout BrowserWindowShortcutMutationState
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

        return state.selectionHistory.recordSelection(item, in: spaceId)
    }
}
