import CoreGraphics
import Foundation
import SumiDomain

enum FloatingBarPresentationReason: String, Codable, Equatable, Hashable {
    case none
    case emptySpace
    case keyboard
    case splitTabPicker
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
    var floatingBarReason: FloatingBarPresentationReason?
    /// Map-shaped selection state stored as a stable array for Codable.
    /// Canonical ordering is part of the session identity contract: restore
    /// deduplication hashes complete snapshots, so dictionary iteration order
    /// must never make the same window look like a different session. Invalid
    /// duplicate Space keys collapse to the lexicographically smallest value
    /// before any dictionary materialization can trap.
    private(set) var activeTabsBySpace: [SpaceTabSelectionSnapshot]
    private(set) var activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot]
    var sidebarWidth: Double
    var savedSidebarWidth: Double
    var sidebarContentWidth: Double
    var isSidebarVisible: Bool
    var floatingBarDraft: FloatingBarDraftState
    var splitSelection: WindowSplitSelection? = nil
    var glanceSession: GlanceSessionSnapshot? = nil

    private enum CodingKeys: String, CodingKey {
        case currentTabId
        case currentSpaceId
        case currentProfileId
        case activeShortcutPinId
        case activeShortcutPinRole
        case isShowingEmptyState
        case floatingBarReason
        case activeTabsBySpace
        case activeShortcutsBySpace
        case sidebarWidth
        case savedSidebarWidth
        case sidebarContentWidth
        case isSidebarVisible
        case floatingBarDraft
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
        floatingBarReason: FloatingBarPresentationReason?,
        activeTabsBySpace: [SpaceTabSelectionSnapshot],
        activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot],
        sidebarWidth: Double,
        savedSidebarWidth: Double,
        sidebarContentWidth: Double,
        isSidebarVisible: Bool,
        floatingBarDraft: FloatingBarDraftState,
        splitSelection: WindowSplitSelection? = nil,
        glanceSession: GlanceSessionSnapshot? = nil
    ) {
        self.currentTabId = currentTabId
        self.currentSpaceId = currentSpaceId
        self.currentProfileId = currentProfileId
        self.activeShortcutPinId = activeShortcutPinId
        self.activeShortcutPinRole = activeShortcutPinRole
        self.isShowingEmptyState = isShowingEmptyState
        self.floatingBarReason = floatingBarReason
        self.activeTabsBySpace = Self.canonicalized(activeTabsBySpace)
        self.activeShortcutsBySpace = Self.canonicalized(activeShortcutsBySpace)
        self.sidebarWidth = sidebarWidth
        self.savedSidebarWidth = savedSidebarWidth
        self.sidebarContentWidth = sidebarContentWidth
        self.isSidebarVisible = isSidebarVisible
        self.floatingBarDraft = floatingBarDraft
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
        floatingBarReason = try container.decodeIfPresent(FloatingBarPresentationReason.self, forKey: .floatingBarReason)
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
        sidebarWidth = try container.decode(Double.self, forKey: .sidebarWidth)
        savedSidebarWidth = try container.decode(Double.self, forKey: .savedSidebarWidth)
        sidebarContentWidth = try container.decode(Double.self, forKey: .sidebarContentWidth)
        isSidebarVisible = try container.decode(Bool.self, forKey: .isSidebarVisible)
        floatingBarDraft = try container.decode(FloatingBarDraftState.self, forKey: .floatingBarDraft)
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
        try container.encodeIfPresent(floatingBarReason, forKey: .floatingBarReason)
        try container.encode(activeTabsBySpace, forKey: .activeTabsBySpace)
        try container.encode(activeShortcutsBySpace, forKey: .activeShortcutsBySpace)
        try container.encode(sidebarWidth, forKey: .sidebarWidth)
        try container.encode(savedSidebarWidth, forKey: .savedSidebarWidth)
        try container.encode(sidebarContentWidth, forKey: .sidebarContentWidth)
        try container.encode(isSidebarVisible, forKey: .isSidebarVisible)
        try container.encode(floatingBarDraft, forKey: .floatingBarDraft)
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
}
