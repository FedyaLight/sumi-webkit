//
//  TabFolderHeaderView.swift
//  Sumi
//

import AppKit
import SwiftUI

/// Folder header chrome: title row, drop geometry, context menu, and search-hover anchor.
struct TabFolderHeaderView: View {
    let folder: TabFolder
    let space: Space
    let browserContext: SidebarBrowserContext
    let parentFolderId: UUID?
    let topLevelIndex: Int
    let contentProjection: SidebarFolderContentProjection
    let projection: SidebarFolderViewProjection
    let isInteractive: Bool
    let isDropHighlighted: Bool
    let folderPreviewIsOpen: Bool
    let hasActiveSelection: Bool
    let hasActiveProjection: Bool
    let geometryGeneration: Int
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let onToggle: () -> Void
    let onActivateShortcutPin: (ShortcutPin) -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var nativeSurfaceHoverUpdatesEnabled
    @EnvironmentObject private var dragState: SidebarDragState

    private var folderDragSnapshot: SidebarFolderDragSnapshot {
        SidebarFolderDragSnapshot(dragState: dragState)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var folderShellPalette: SumiFolderGlyphPalette {
        SumiFolderGlyphPalette.sidebarFolder(
            accent: themeContext.gradient.primaryColor,
            chromeColorScheme: themeContext.chromeColorScheme,
            primaryText: tokens.primaryText
        )
    }

    private var folderHeaderSourceID: String {
        "folder-header-\(folder.id.uuidString)"
    }

    private var folderSearchHoverIsEnabled: Bool {
        isInteractive
            && sidebarPresentationContext.allowsInteractiveWork
            && nativeSurfaceHoverUpdatesEnabled
            && windowState.sidebarInteractionState.allowsFolderSearchHoverTracking
            && !folder.isOpen
            && !folderDragSnapshot.isDragging
    }

    var body: some View {
        TabFolderHeaderRow(
            title: folder.name,
            glyphPresentation: folderGlyphPresentation,
            glyphPalette: folderShellPalette,
            isDropHighlighted: isDropHighlighted,
            isInteractive: isInteractive
        )
        .sidebarFolderDropGeometry(
            folderId: folder.id,
            spaceId: space.id,
            parentFolderId: parentFolderId,
            topLevelIndex: topLevelIndex,
            childCount: contentProjection.childCount,
            isOpen: folder.isOpen,
            region: .header,
            generation: geometryGeneration,
            isActive: isInteractive && !projection.isLiveFolder
        )
        .sidebarAppKitContextMenu(
            isEnabled: true,
            isInteractionEnabled: isInteractive,
            dragSource: SidebarDragSourceConfiguration(
                item: SumiDragItem.folder(folderId: folder.id, title: folder.name),
                sourceZone: parentFolderId.map(DropZoneID.folder) ?? .spacePinned(space.id),
                previewKind: .folderRow,
                folderGlyphPresentation: folderGlyphPresentation,
                folderGlyphPalette: folderShellPalette,
                onActivate: onToggle,
                isEnabled: isInteractive
            ),
            primaryAction: onToggle,
            sourceID: folderHeaderSourceID,
            entries: contextMenuEntries
        )
        .overlay {
            folderSearchHoverAnchor
        }
        .accessibilityIdentifier("folder-header-\(folder.id.uuidString)")
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.isOpen ? "expanded" : "collapsed")
    }

    private var folderGlyphPresentation: SumiFolderGlyphPresentationState {
        SumiFolderGlyphPresentationState(
            iconValue: folder.icon,
            isOpen: folderPreviewIsOpen,
            hasActiveProjection: hasActiveProjection
                || hasActiveSelection
                || contentProjection.hasCollapsedProjectionForLayout
        )
    }

    @ViewBuilder
    private var folderSearchHoverAnchor: some View {
        FolderSearchHoverAnchorBridge(
            isEnabled: folderSearchHoverIsEnabled,
            onOpen: { anchorView in
                openFolderSearchPopover(anchorView: anchorView)
            },
            onHoverChanged: { hovering in
                browserContext.presentationActions.folderSearchAnchorHoverChanged(
                    folder.id,
                    windowState,
                    hovering
                )
            }
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func openFolderSearchPopover(anchorView: NSView) {
        guard folderSearchHoverIsEnabled,
              let request = folderSearchPopoverRequest
        else { return }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: anchorView.window ?? windowState.shellWindow(in: windowRegistry),
            ownerView: anchorView
        )
        browserContext.presentationActions.showFolderSearchPopover(
            request,
            windowState,
            themeContext,
            source
        )
    }

    private var folderSearchPopoverRequest: FolderSearchPopoverRequest? {
        let builder = FolderSearchCandidateBuilder(
            browserContext: browserContext,
            actions: FolderSearchActivationActions(
                activateShortcut: { pin in
                    onActivateShortcutPin(pin)
                },
                activateLiveItem: { item in
                    browserContext.liveFolderManager.open(item: item, in: windowState)
                },
                activateSplitGroupItem: { item, group in
                    browserContext.commands.focusSplitGroup(
                        group.id,
                        item.id,
                        windowState.id
                    )
                }
            )
        )
        let candidates = builder.candidates(
            for: folder,
            in: space,
            excludingVisibleCollapsedProjectionIDs: Set(contentProjection.visibleCollapsedProjectionIDs)
        )
        guard !candidates.isEmpty else { return nil }

        return FolderSearchPopoverRequest(
            folderID: folder.id,
            folderName: folder.name,
            candidates: candidates
        )
    }
}
