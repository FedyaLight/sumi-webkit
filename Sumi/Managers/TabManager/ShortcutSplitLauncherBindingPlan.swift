import Foundation
import SumiDomain

struct ShortcutSplitLauncherBindingTarget {
    let spaceID: UUID?
    let desiredProfileID: UUID?
    let resolvedProfileID: UUID
    let runtimeFallback: TabRuntimeFallbackProfileWitness?
    let folderID: UUID?
}

@MainActor
struct ShortcutSplitLauncherTabReceipt {
    let isPinned: Bool
    let isSpacePinned: Bool
    let shortcutPinID: UUID?
    let shortcutPinRole: ShortcutPinRole?
    let isShortcutLiveInstance: Bool
    let spaceID: UUID?
    let folderID: UUID?

    init(_ tab: Tab) {
        isPinned = tab.isPinned
        isSpacePinned = tab.isSpacePinned
        shortcutPinID = tab.shortcutPinId
        shortcutPinRole = tab.shortcutPinRole
        isShortcutLiveInstance = tab.isShortcutLiveInstance
        spaceID = tab.spaceId
        folderID = tab.folderId
    }

    func accepts(_ tab: Tab) -> Bool {
        tab.isPinned == isPinned
            && tab.isSpacePinned == isSpacePinned
            && tab.shortcutPinId == shortcutPinID
            && tab.shortcutPinRole == shortcutPinRole
            && tab.isShortcutLiveInstance == isShortcutLiveInstance
            && tab.spaceId == spaceID
            && tab.folderId == folderID
    }

    func restoreBindingModel(to tab: Tab) {
        tab.isPinned = isPinned
        tab.isSpacePinned = isSpacePinned
        tab.shortcutPinId = shortcutPinID
        tab.shortcutPinRole = shortcutPinRole
        tab.isShortcutLiveInstance = isShortcutLiveInstance
        tab.spaceId = spaceID
        tab.folderId = folderID
    }
}

@MainActor
struct ShortcutSplitLauncherWindowReceipt: Equatable {
    let currentTabID: UUID?
    let currentSpaceID: UUID?
    let currentShortcutPinID: UUID?
    let currentShortcutPinRole: ShortcutPinRole?
    let isShowingEmptyState: Bool
    let selectedShortcutPinForSpace: [UUID: UUID]
    let selectionHistory: WindowSelectionHistory

    init(_ state: BrowserWindowState) {
        currentTabID = state.currentTabId
        currentSpaceID = state.currentSpaceId
        currentShortcutPinID = state.currentShortcutPinId
        currentShortcutPinRole = state.currentShortcutPinRole
        isShowingEmptyState = state.isShowingEmptyState
        selectedShortcutPinForSpace = state.selectedShortcutPinForSpace
        selectionHistory = state.selectionHistory
    }
}

@MainActor
struct ShortcutSplitLauncherBindingPlan {
    let tab: Tab
    let windowID: UUID
    let windowState: BrowserWindowState?
    let tabReceipt: ShortcutSplitLauncherTabReceipt
    let windowReceipt: ShortcutSplitLauncherWindowReceipt?
    let sourceIdentity: ShortcutBindingIdentity?
    let wasSelected: Bool
    let target: ShortcutSplitLauncherBindingTarget
}
