//
//  SpaceSidebarSnapshots.swift
//  Sumi
//
//

import SumiDomain
import SwiftUI

enum SpaceSidebarSnapshotFolderLayout {
    static let contentLeadingPadding: CGFloat = 14
    static let contentVerticalPadding: CGFloat = 4
}

struct SpaceSidebarSnapshotViewport: Equatable {
    static let zero = SpaceSidebarSnapshotViewport(
        contentOffsetY: 0,
        contentHeight: 0,
        viewportHeight: 0
    )

    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    init(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) {
        self.contentOffsetY = contentOffsetY.isFinite ? contentOffsetY : 0
        self.contentHeight = max(contentHeight.isFinite ? contentHeight : 0, 0)
        self.viewportHeight = max(viewportHeight.isFinite ? viewportHeight : 0, 0)
    }

    func clampedOffset(for renderedViewportHeight: CGFloat? = nil) -> CGFloat {
        let resolvedViewportHeight: CGFloat
        if let renderedViewportHeight {
            resolvedViewportHeight = max(renderedViewportHeight.isFinite ? renderedViewportHeight : 0, 0)
        } else {
            resolvedViewportHeight = viewportHeight
        }

        let maximumOffset = max(contentHeight - resolvedViewportHeight, 0)
        return min(max(contentOffsetY, 0), maximumOffset)
    }
}

enum SpaceSidebarSnapshotThemeResolver {
    @MainActor
    static func pageThemeContext(
        for space: Space,
        baseContext: ResolvedThemeContext,
        settings: SumiSettingsService,
        isIncognito: Bool
    ) -> ResolvedThemeContext {
        let workspaceTheme = isIncognito ? WorkspaceTheme.incognito : space.workspaceTheme
        let chromeColorScheme = ThemeContrastResolver.resolvedChromeColorScheme(
            theme: workspaceTheme,
            globalWindowScheme: baseContext.globalColorScheme,
            settings: settings,
            isIncognito: isIncognito
        )

        var context = baseContext
        context.chromeColorScheme = chromeColorScheme
        context.sourceChromeColorScheme = chromeColorScheme
        context.targetChromeColorScheme = chromeColorScheme
        context.workspaceTheme = workspaceTheme
        context.sourceWorkspaceTheme = workspaceTheme
        context.targetWorkspaceTheme = workspaceTheme
        context.isInteractiveTransition = false
        context.transitionProgress = 1.0
        return context
    }
}

indirect enum SpaceSidebarSnapshotIcon {
    case image(Image)
    case system(String)
    case emoji(String)
    case resolvable(
        launchURL: URL,
        partition: SumiFaviconPartition,
        fallback: SpaceSidebarSnapshotIcon
    )
}

extension SpaceSidebarSnapshotIcon {
    var accentGlyphText: String? {
        switch self {
        case .emoji(let glyph):
            return glyph
        case .resolvable(_, _, let fallback):
            return fallback.accentGlyphText
        case .image, .system:
            return nil
        }
    }

    var accentSystemImageName: String? {
        switch self {
        case .system(let systemName):
            return systemName
        case .resolvable(_, _, let fallback):
            return fallback.accentSystemImageName
        case .image, .emoji:
            return nil
        }
    }

    @MainActor
    func resolved(using store: SidebarFaviconImageStore) -> Self {
        switch self {
        case .resolvable(let launchURL, let partition, let fallback):
            if let image = store.image(for: launchURL, partition: partition) {
                return .image(image)
            }
            return fallback.resolved(using: store)
        case .image, .system, .emoji:
            return self
        }
    }

    @MainActor
    func loadKey(using store: SidebarFaviconImageStore) -> String {
        switch self {
        case .resolvable(let launchURL, let partition, _):
            return store.loadKey(
                launchURL: launchURL,
                partition: partition
            )
        case .image:
            return "static-image"
        case .system(let systemName):
            return "static-system|\(systemName)"
        case .emoji(let glyph):
            return "static-emoji|\(glyph)"
        }
    }

    @MainActor
    func load(using store: SidebarFaviconImageStore) async {
        guard case .resolvable(let launchURL, let partition, _) = self else {
            return
        }
        await store.load(launchURL: launchURL, partition: partition)
    }
}

struct SpaceTabRowSnapshot: Identifiable {
    let id: UUID
    let title: String
    let icon: SpaceSidebarSnapshotIcon
    let isSelected: Bool
    let showsUnloadedIndicator: Bool
    let showsAudioButton: Bool
    let isMuted: Bool
}

enum SpaceRegularRowSnapshot: Identifiable {
    enum Identity: Hashable {
        case tab(UUID)
        case splitGroup(UUID)
    }

    case tab(SpaceTabRowSnapshot)
    case splitGroup(SpaceSplitGroupSnapshot)

    var id: Identity {
        switch self {
        case .tab(let tab):
            return .tab(tab.id)
        case .splitGroup(let group):
            return .splitGroup(group.id)
        }
    }
}

struct SpaceShortcutSnapshot: Identifiable {
    let id: UUID
    let title: String
    let icon: SpaceSidebarSnapshotIcon
    let accentSource: SpaceShortcutSnapshotAccentSource
    let favoriteBackdrop: Image?
    let presentationState: ShortcutPresentationState
    let showsAudioButton: Bool
    let isMuted: Bool
    let showsSplitOutline: Bool
    let showsChangedURLSlash: Bool
}

struct SpaceShortcutSnapshotAccentSource: Equatable {
    let launchURL: URL
    let partition: SumiFaviconPartition
}

struct SpaceFolderSnapshot: Identifiable {
    let id: UUID
    let title: String
    let iconValue: String
    let isOpen: Bool
    let hasActiveSelection: Bool
    let bodyChildren: [SpacePinnedItemSnapshot]
}

struct SpaceSplitGroupMemberSnapshot: Identifiable {
    let id: SplitMemberID
    let title: String
    let icon: SpaceSidebarSnapshotIcon
    let desaturatesIcon: Bool
    let accentSource: SpaceShortcutSnapshotAccentSource?
    let favoriteBackdrop: Image?
    let isSelected: Bool
}

struct SpaceSplitGroupSnapshot: Identifiable {
    let id: UUID
    let displayTitle: String
    let customIcon: SpaceSidebarSnapshotIcon?
    let members: [SpaceSplitGroupMemberSnapshot]
    let isSelected: Bool
    let isLoaded: Bool
}

indirect enum SpacePinnedItemSnapshot: Identifiable {
    case folder(SpaceFolderSnapshot)
    case shortcut(SpaceShortcutSnapshot)
    case splitGroup(SpaceSplitGroupSnapshot)

    var id: UUID {
        switch self {
        case .folder(let folder):
            return folder.id
        case .shortcut(let shortcut):
            return shortcut.id
        case .splitGroup(let splitGroup):
            return splitGroup.id
        }
    }
}

extension Array where Element == SpacePinnedItemSnapshot {
    var containsActiveSelection: Bool {
        contains { item in
            switch item {
            case .folder(let folder):
                return folder.hasActiveSelection || folder.bodyChildren.containsActiveSelection
            case .shortcut(let shortcut):
                return shortcut.presentationState.isSelected
            case .splitGroup(let splitGroup):
                return splitGroup.isSelected
            }
        }
    }
}

enum FavoriteSnapshotItem: Identifiable {
    case shortcut(SpaceShortcutSnapshot)
    case splitGroup(SpaceSplitGroupSnapshot)

    var id: UUID {
        switch self {
        case .shortcut(let shortcut): shortcut.id
        case .splitGroup(let group): group.id
        }
    }
}

struct FavoriteSnapshot {
    let items: [FavoriteSnapshotItem]
    /// Mirrors the live grid's empty-state hint so it does not blink out of
    /// existence for the duration of a space transition. Resolved once here
    /// rather than read per frame by the snapshot view.
    let showsPlaceholder: Bool
}

struct ExtensionActionSlotSnapshot: Identifiable {
    let id: String
    let icon: NSImage?
    let badgeText: String?
    let hasUnreadBadgeText: Bool
}

struct ExtensionActionGridSnapshot {
    let slots: [ExtensionActionSlotSnapshot]
}

struct SpaceSidebarPageSnapshot {
    let spaceId: UUID
    let title: String
    let iconValue: String
    let extensionActions: ExtensionActionGridSnapshot?
    let favorite: FavoriteSnapshot?
    let supportsPinnedContent: Bool
    let hasPinnedContent: Bool
    let isPinnedContentCollapsed: Bool
    let pinnedItems: [SpacePinnedItemSnapshot]
    let regularRows: [SpaceRegularRowSnapshot]
    let showsNewTabButtonInList: Bool
    let showsTopNewTabButton: Bool
    let rowCornerRadius: CGFloat
    let scrollViewport: SpaceSidebarSnapshotViewport

    init(
        spaceId: UUID,
        title: String,
        iconValue: String,
        extensionActions: ExtensionActionGridSnapshot?,
        favorite: FavoriteSnapshot?,
        supportsPinnedContent: Bool = true,
        hasPinnedContent: Bool,
        isPinnedContentCollapsed: Bool,
        pinnedItems: [SpacePinnedItemSnapshot],
        regularRows: [SpaceRegularRowSnapshot],
        showsNewTabButtonInList: Bool,
        showsTopNewTabButton: Bool,
        rowCornerRadius: CGFloat,
        scrollViewport: SpaceSidebarSnapshotViewport
    ) {
        self.spaceId = spaceId
        self.title = title
        self.iconValue = iconValue
        self.extensionActions = extensionActions
        self.favorite = favorite
        self.supportsPinnedContent = supportsPinnedContent
        self.hasPinnedContent = hasPinnedContent
        self.isPinnedContentCollapsed = isPinnedContentCollapsed
        self.pinnedItems = pinnedItems
        self.regularRows = regularRows
        self.showsNewTabButtonInList = showsNewTabButtonInList
        self.showsTopNewTabButton = showsTopNewTabButton
        self.rowCornerRadius = rowCornerRadius
        self.scrollViewport = scrollViewport
    }

    var tabSectionBoundaryLayout: SpaceTabSectionBoundaryLayout {
        SpaceTabSectionBoundaryLayout(
            hasPinnedContent: hasPinnedContent,
            regularTabCount: regularRows.count,
            supportsPinnedContent: supportsPinnedContent
        )
    }
}

struct SpaceSidebarTransitionSnapshot {
    let source: SpaceSidebarPageSnapshot
    let destination: SpaceSidebarPageSnapshot
    let stationaryFavorite: FavoriteSnapshot?

    func page(for spaceId: UUID) -> SpaceSidebarPageSnapshot? {
        if source.spaceId == spaceId {
            return source
        }
        if destination.spaceId == spaceId {
            return destination
        }
        return nil
    }

    func matches(sourceSpaceId: UUID, destinationSpaceId: UUID) -> Bool {
        source.spaceId == sourceSpaceId && destination.spaceId == destinationSpaceId
    }

    func matches(_ transitionState: SpaceSidebarTransitionState) -> Bool {
        guard let sourceSpaceId = transitionState.sourceSpaceId,
              let destinationSpaceId = transitionState.destinationSpaceId else {
            return false
        }
        return matches(sourceSpaceId: sourceSpaceId, destinationSpaceId: destinationSpaceId)
    }
}
