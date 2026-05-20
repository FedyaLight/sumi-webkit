import Foundation

enum LegacySplitOrientation: String, Codable, Hashable {
    case horizontal
    case vertical
}

enum FloatingBarPresentationReason: String, Codable, Equatable, Hashable {
    case none
    case emptySpace
    case keyboard
}

struct FloatingBarDraftState: Codable, Equatable, Hashable {
    var text: String
    var navigateCurrentTab: Bool
}

struct SpaceTabSelectionSnapshot: Codable, Equatable, Hashable {
    var spaceId: UUID
    var tabId: UUID
}

struct SpaceShortcutSelectionSnapshot: Codable, Equatable, Hashable {
    var spaceId: UUID
    var shortcutPinId: UUID
}

// Legacy decoder only. New split groups are persisted with tab snapshots.
struct LegacySplitSessionSnapshot: Codable, Equatable, Hashable {
    var leftTabId: UUID
    var rightTabId: UUID
    var dividerFraction: Double
    var activeSideRawValue: String?
    var orientation: LegacySplitOrientation
}

struct WindowSessionSnapshot: Codable, Equatable, Hashable {
    var currentTabId: UUID?
    var currentSpaceId: UUID?
    var currentProfileId: UUID?
    var activeShortcutPinId: UUID?
    var activeShortcutPinRole: ShortcutPinRole?
    var isShowingEmptyState: Bool
    var floatingBarReason: FloatingBarPresentationReason?
    var activeTabsBySpace: [SpaceTabSelectionSnapshot]
    var activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot]?
    var sidebarWidth: Double
    var savedSidebarWidth: Double
    var sidebarContentWidth: Double
    var isSidebarVisible: Bool
    var floatingBarDraft: FloatingBarDraftState
    var splitSession: LegacySplitSessionSnapshot?
}
