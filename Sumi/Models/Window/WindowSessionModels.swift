import CoreGraphics
import Foundation
import SumiDomain

enum CommandPalettePresentationReason: String, Codable, Equatable, Hashable {
    case none
    case emptySpace
    case keyboard
    case splitTabPicker
}

struct CommandPaletteDraftState: Codable, Equatable, Hashable {
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

struct GlanceSessionRectSnapshot: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct GlanceSessionSnapshot: Codable, Equatable, Hashable {
    var targetURL: URL
    var currentURL: URL?
    var title: String?
    var sourceTabId: UUID?
    var sourceShortcutPinId: UUID? = nil
    var sourceShortcutPinRole: ShortcutPinRole? = nil
    var originRectInWindow: GlanceSessionRectSnapshot?
}

struct WindowSessionSnapshot: Codable, Equatable, Hashable {
    var currentTabId: UUID?
    var currentSpaceId: UUID?
    var currentProfileId: UUID?
    var activeShortcutPinId: UUID?
    var activeShortcutPinRole: ShortcutPinRole?
    var isShowingEmptyState: Bool
    var commandPaletteReason: CommandPalettePresentationReason?
    /// Map-shaped selection state stored as a stable array for Codable.
    /// Canonical ordering is part of the session identity contract: restore
    /// deduplication hashes complete snapshots, so dictionary iteration order
    /// must never make the same window look like a different session. Invalid
    /// duplicate Space keys collapse to the lexicographically smallest value
    /// before any dictionary materialization can trap.
    private(set) var activeTabsBySpace: [SpaceTabSelectionSnapshot]
    private(set) var activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot]
    private(set) var collapsedPinnedSpaceIDs: [UUID]
    var sidebarWidth: Double
    var savedSidebarWidth: Double
    var sidebarContentWidth: Double
    var isSidebarVisible: Bool
    var commandPaletteDraft: CommandPaletteDraftState
    var splitSelection: WindowSplitSelection? = nil
    var glanceSession: GlanceSessionSnapshot? = nil

    private enum CodingKeys: String, CodingKey {
        case currentTabId
        case currentSpaceId
        case currentProfileId
        case activeShortcutPinId
        case activeShortcutPinRole
        case isShowingEmptyState
        case commandPaletteReason
        case activeTabsBySpace
        case activeShortcutsBySpace
        case collapsedPinnedSpaceIDs
        case sidebarWidth
        case savedSidebarWidth
        case sidebarContentWidth
        case isSidebarVisible
        case commandPaletteDraft
        case splitSelection
        case glanceSession
    }

    init(
        currentTabId: UUID?,
        currentSpaceId: UUID?,
        currentProfileId: UUID?,
        activeShortcutPinId: UUID?,
        activeShortcutPinRole: ShortcutPinRole?,
        isShowingEmptyState: Bool,
        commandPaletteReason: CommandPalettePresentationReason?,
        activeTabsBySpace: [SpaceTabSelectionSnapshot],
        activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot],
        collapsedPinnedSpaceIDs: [UUID] = [],
        sidebarWidth: Double,
        savedSidebarWidth: Double,
        sidebarContentWidth: Double,
        isSidebarVisible: Bool,
        commandPaletteDraft: CommandPaletteDraftState,
        splitSelection: WindowSplitSelection? = nil,
        glanceSession: GlanceSessionSnapshot? = nil
    ) {
        self.currentTabId = currentTabId
        self.currentSpaceId = currentSpaceId
        self.currentProfileId = currentProfileId
        self.activeShortcutPinId = activeShortcutPinId
        self.activeShortcutPinRole = activeShortcutPinRole
        self.isShowingEmptyState = isShowingEmptyState
        self.commandPaletteReason = commandPaletteReason
        self.activeTabsBySpace = Self.canonicalized(activeTabsBySpace)
        self.activeShortcutsBySpace = Self.canonicalized(activeShortcutsBySpace)
        self.collapsedPinnedSpaceIDs = Self.canonicalized(collapsedPinnedSpaceIDs)
        self.sidebarWidth = sidebarWidth
        self.savedSidebarWidth = savedSidebarWidth
        self.sidebarContentWidth = sidebarContentWidth
        self.isSidebarVisible = isSidebarVisible
        self.commandPaletteDraft = commandPaletteDraft
        self.splitSelection = splitSelection
        self.glanceSession = glanceSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentTabId = try container.decodeIfPresent(UUID.self, forKey: .currentTabId)
        currentSpaceId = try container.decodeIfPresent(UUID.self, forKey: .currentSpaceId)
        currentProfileId = try container.decodeIfPresent(UUID.self, forKey: .currentProfileId)
        activeShortcutPinId = try container.decodeIfPresent(UUID.self, forKey: .activeShortcutPinId)
        activeShortcutPinRole = try container.decodeIfPresent(ShortcutPinRole.self, forKey: .activeShortcutPinRole)
        isShowingEmptyState = try container.decode(Bool.self, forKey: .isShowingEmptyState)
        commandPaletteReason = try container.decodeIfPresent(CommandPalettePresentationReason.self, forKey: .commandPaletteReason)
        activeTabsBySpace = Self.canonicalized(
            try container.decode(
                [SpaceTabSelectionSnapshot].self,
                forKey: .activeTabsBySpace
            )
        )
        activeShortcutsBySpace = Self.canonicalized(
            try container.decodeIfPresent(
                [SpaceShortcutSelectionSnapshot].self,
                forKey: .activeShortcutsBySpace
            ) ?? []
        )
        collapsedPinnedSpaceIDs = Self.canonicalized(
            try container.decode(
                [UUID].self,
                forKey: .collapsedPinnedSpaceIDs
            )
        )
        sidebarWidth = try container.decode(Double.self, forKey: .sidebarWidth)
        savedSidebarWidth = try container.decode(Double.self, forKey: .savedSidebarWidth)
        sidebarContentWidth = try container.decode(Double.self, forKey: .sidebarContentWidth)
        isSidebarVisible = try container.decode(Bool.self, forKey: .isSidebarVisible)
        commandPaletteDraft = try container.decode(CommandPaletteDraftState.self, forKey: .commandPaletteDraft)
        splitSelection = try container.decodeIfPresent(
            WindowSplitSelection.self,
            forKey: .splitSelection
        )
        glanceSession = try container.decodeIfPresent(GlanceSessionSnapshot.self, forKey: .glanceSession)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(currentTabId, forKey: .currentTabId)
        try container.encodeIfPresent(currentSpaceId, forKey: .currentSpaceId)
        try container.encodeIfPresent(currentProfileId, forKey: .currentProfileId)
        try container.encodeIfPresent(activeShortcutPinId, forKey: .activeShortcutPinId)
        try container.encodeIfPresent(activeShortcutPinRole, forKey: .activeShortcutPinRole)
        try container.encode(isShowingEmptyState, forKey: .isShowingEmptyState)
        try container.encodeIfPresent(commandPaletteReason, forKey: .commandPaletteReason)
        try container.encode(activeTabsBySpace, forKey: .activeTabsBySpace)
        try container.encode(activeShortcutsBySpace, forKey: .activeShortcutsBySpace)
        try container.encode(collapsedPinnedSpaceIDs, forKey: .collapsedPinnedSpaceIDs)
        try container.encode(sidebarWidth, forKey: .sidebarWidth)
        try container.encode(savedSidebarWidth, forKey: .savedSidebarWidth)
        try container.encode(sidebarContentWidth, forKey: .sidebarContentWidth)
        try container.encode(isSidebarVisible, forKey: .isSidebarVisible)
        try container.encode(commandPaletteDraft, forKey: .commandPaletteDraft)
        try container.encodeIfPresent(splitSelection, forKey: .splitSelection)
        try container.encodeIfPresent(glanceSession, forKey: .glanceSession)
    }

    private static func canonicalized(
        _ selections: [SpaceTabSelectionSnapshot]
    ) -> [SpaceTabSelectionSnapshot] {
        let bySpace = selections.reduce(
            into: [UUID: SpaceTabSelectionSnapshot]()
        ) { result, selection in
            if let current = result[selection.spaceId],
               current.tabId.uuidString <= selection.tabId.uuidString {
                return
            }
            result[selection.spaceId] = selection
        }
        return bySpace.values.sorted {
            $0.spaceId.uuidString < $1.spaceId.uuidString
        }
    }

    private static func canonicalized(
        _ selections: [SpaceShortcutSelectionSnapshot]
    ) -> [SpaceShortcutSelectionSnapshot] {
        let bySpace = selections.reduce(
            into: [UUID: SpaceShortcutSelectionSnapshot]()
        ) { result, selection in
            if let current = result[selection.spaceId],
               current.shortcutPinId.uuidString
                <= selection.shortcutPinId.uuidString {
                return
            }
            result[selection.spaceId] = selection
        }
        return bySpace.values.sorted {
            $0.spaceId.uuidString < $1.spaceId.uuidString
        }
    }

    private static func canonicalized(_ spaceIDs: [UUID]) -> [UUID] {
        Set(spaceIDs).sorted { $0.uuidString < $1.uuidString }
    }
}
