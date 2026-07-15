import Foundation
import SumiDomain

struct ShortcutSplitLauncherBindingTarget {
    let spaceID: UUID?
    let profileID: UUID?
    let folderID: UUID?
}

@MainActor
struct ShortcutSplitLauncherTabReceipt {
    let isPinned: Bool
    let isSpacePinned: Bool
    let shortcutPinID: UUID?
    let shortcutPinRole: ShortcutPinRole?
    let spaceID: UUID?
    let profileID: UUID?
    let folderID: UUID?
    let profileRevision: UInt64

    init(_ tab: Tab) {
        isPinned = tab.isPinned
        isSpacePinned = tab.isSpacePinned
        shortcutPinID = tab.shortcutPinId
        shortcutPinRole = tab.shortcutPinRole
        spaceID = tab.spaceId
        profileID = tab.profileId
        folderID = tab.folderId
        profileRevision = tab.profileAssignment.changeRevision
    }

    func accepts(_ tab: Tab) -> Bool {
        tab.isPinned == isPinned
            && tab.isSpacePinned == isSpacePinned
            && tab.shortcutPinId == shortcutPinID
            && tab.shortcutPinRole == shortcutPinRole
            && tab.spaceId == spaceID
            && tab.profileId == profileID
            && tab.folderId == folderID
            && tab.profileAssignment.changeRevision == profileRevision
            && tab.profileAssignment.hasUnsettledAssignment == false
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
