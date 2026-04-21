import Foundation

enum SplitOrientation: String, Codable {
    case horizontal
    case vertical
}

enum WindowSidebarMenuSection: String, Codable {
    case history
    case downloads
}

enum CommandPalettePresentationReason: String, Codable, Equatable {
    case none
    case emptySpace
    case keyboard
}

struct URLBarDraftState: Codable, Equatable {
    var text: String
    var navigateCurrentTab: Bool
}

struct SpaceTabSelectionSnapshot: Codable, Equatable {
    var spaceId: UUID
    var tabId: UUID
}

struct SpaceShortcutSelectionSnapshot: Codable, Equatable {
    var spaceId: UUID
    var shortcutPinId: UUID
}

struct SplitSessionSnapshot: Codable, Equatable {
    var leftTabId: UUID
    var rightTabId: UUID
    var dividerFraction: Double
    var activeSideRawValue: String?
    var orientation: SplitOrientation
}

struct WindowSessionSnapshot: Codable, Equatable {
    var currentTabId: UUID?
    var currentSpaceId: UUID?
    var currentProfileId: UUID?
    var activeShortcutPinId: UUID?
    var activeShortcutPinRole: ShortcutPinRole?
    var isShowingEmptyState: Bool
    var commandPaletteReason: CommandPalettePresentationReason?
    var activeTabsBySpace: [SpaceTabSelectionSnapshot]
    var activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot]?
    var sidebarWidth: Double
    var savedSidebarWidth: Double
    var sidebarContentWidth: Double
    var isSidebarVisible: Bool
    var isSidebarMenuVisible: Bool
    var selectedSidebarMenuSection: WindowSidebarMenuSection
    var urlBarDraft: URLBarDraftState
    var splitSession: SplitSessionSnapshot?
}
