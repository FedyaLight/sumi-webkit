import CoreGraphics
import Foundation

enum LegacySplitOrientation: String, Codable, Hashable {
    case horizontal
    case vertical
}

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

// Decode-only compatibility for window snapshots written before split groups moved
// into the tab structural store.
struct LegacySplitSessionSnapshot: Codable, Equatable, Hashable {
    var leftTabId: UUID
    var rightTabId: UUID
    var dividerFraction: Double
    var activeSideRawValue: String?
    var orientation: LegacySplitOrientation

    func makeSplitGroup(spaceId: UUID?) -> SplitGroup? {
        SplitGroup.make(
            tabIds: [leftTabId, rightTabId],
            layoutKind: orientation == .vertical ? .horizontal : .vertical,
            activeTabId: activeSideRawValue == "left" ? leftTabId : rightTabId,
            host: .regular(spaceId: spaceId)
        )
    }
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
    var activeSplitGroupId: UUID? = nil
    var glanceSession: GlanceSessionSnapshot? = nil
    var legacySplitSessionForMigration: LegacySplitSessionSnapshot? = nil

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
        case activeSplitGroupId
        case glanceSession
        case splitSession
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
        activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot]?,
        sidebarWidth: Double,
        savedSidebarWidth: Double,
        sidebarContentWidth: Double,
        isSidebarVisible: Bool,
        floatingBarDraft: FloatingBarDraftState,
        activeSplitGroupId: UUID? = nil,
        glanceSession: GlanceSessionSnapshot? = nil
    ) {
        self.currentTabId = currentTabId
        self.currentSpaceId = currentSpaceId
        self.currentProfileId = currentProfileId
        self.activeShortcutPinId = activeShortcutPinId
        self.activeShortcutPinRole = activeShortcutPinRole
        self.isShowingEmptyState = isShowingEmptyState
        self.floatingBarReason = floatingBarReason
        self.activeTabsBySpace = activeTabsBySpace
        self.activeShortcutsBySpace = activeShortcutsBySpace
        self.sidebarWidth = sidebarWidth
        self.savedSidebarWidth = savedSidebarWidth
        self.sidebarContentWidth = sidebarContentWidth
        self.isSidebarVisible = isSidebarVisible
        self.floatingBarDraft = floatingBarDraft
        self.activeSplitGroupId = activeSplitGroupId
        self.glanceSession = glanceSession
        legacySplitSessionForMigration = nil
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
        activeTabsBySpace = try container.decode([SpaceTabSelectionSnapshot].self, forKey: .activeTabsBySpace)
        activeShortcutsBySpace = try container.decodeIfPresent(
            [SpaceShortcutSelectionSnapshot].self,
            forKey: .activeShortcutsBySpace
        )
        sidebarWidth = try container.decode(Double.self, forKey: .sidebarWidth)
        savedSidebarWidth = try container.decode(Double.self, forKey: .savedSidebarWidth)
        sidebarContentWidth = try container.decode(Double.self, forKey: .sidebarContentWidth)
        isSidebarVisible = try container.decode(Bool.self, forKey: .isSidebarVisible)
        floatingBarDraft = try container.decode(FloatingBarDraftState.self, forKey: .floatingBarDraft)
        activeSplitGroupId = try container.decodeIfPresent(UUID.self, forKey: .activeSplitGroupId)
        glanceSession = try container.decodeIfPresent(GlanceSessionSnapshot.self, forKey: .glanceSession)
        legacySplitSessionForMigration = try container.decodeIfPresent(
            LegacySplitSessionSnapshot.self,
            forKey: .splitSession
        )
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
        try container.encodeIfPresent(activeShortcutsBySpace, forKey: .activeShortcutsBySpace)
        try container.encode(sidebarWidth, forKey: .sidebarWidth)
        try container.encode(savedSidebarWidth, forKey: .savedSidebarWidth)
        try container.encode(sidebarContentWidth, forKey: .sidebarContentWidth)
        try container.encode(isSidebarVisible, forKey: .isSidebarVisible)
        try container.encode(floatingBarDraft, forKey: .floatingBarDraft)
        try container.encodeIfPresent(activeSplitGroupId, forKey: .activeSplitGroupId)
        try container.encodeIfPresent(glanceSession, forKey: .glanceSession)
    }
}
