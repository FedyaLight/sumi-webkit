//
//  TabFolderHeaderView.swift
//  Sumi
//

import AppKit
import SwiftUI

/// Folder header chrome: title row, drop geometry, context menu, and search-hover anchor.
struct TabFolderHeaderView: View {
    let folder: TabFolder
    let presentation: SidebarFolderPresentationCell
    let space: Space
    let browserContext: SidebarBrowserContext
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let parentFolderId: UUID?
    let contentProjection: SidebarFolderContentProjection
    let isInteractive: Bool
    let folderPreviewIsOpen: Bool
    let hasActiveSelection: Bool
    let hasActiveProjection: Bool
    let isDragging: Bool
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let onToggle: () -> Void
    let onActivateShortcutPin: (ShortcutPin) -> Void
    let onResetProjection: (() -> Void)?
    let resetProjectionErrorTitle: String?

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var nativeSurfaceHoverUpdatesEnabled

    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
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

    /// The preview belongs to a folder that *looks* shut, so it keys off the very
    /// shell state the glyph renders rather than re-deriving one from the model.
    /// Two derivations of "is this folder closed" is what let the panel and the
    /// glyph disagree.
    private var folderShellIsClosed: Bool {
        folderGlyphPresentation.shellState == .closed
    }

    /// Body-level arming only. The press and text-entry gates are re-checked at
    /// open time instead: reading them here would re-render every folder header
    /// on each sidebar press.
    private var folderPreviewHoverIsEnabled: Bool {
        isInteractive
            && sidebarPresentationContext.allowsInteractiveWork
            && nativeSurfaceHoverUpdatesEnabled
            && windowState.sidebarInteractionState.allowsFolderPreviewHoverTracking
            && folderShellIsClosed
            && !isDragging
    }

    var body: some View {
        TabFolderHeaderRow(
            title: presentation.title,
            glyphPresentation: folderGlyphPresentation,
            glyphPalette: folderShellPalette,
            isInteractive: isInteractive,
            onResetProjection: onResetProjection,
            resetProjectionErrorTitle: resetProjectionErrorTitle
        )
        .sidebarAppKitContextMenu(
            isEnabled: true,
            isInteractionEnabled: isInteractive,
            dragSource: SidebarDragSourceConfiguration(
                item: SumiDragItem.folder(
                    folderId: folder.id,
                    title: presentation.title
                ),
                sourceZone: parentFolderId.map(DropZoneID.folder) ?? .spacePinned(space.id),
                previewKind: .folderRow,
                folderGlyphPresentation: folderGlyphPresentation,
                folderGlyphPalette: folderShellPalette,
                exclusionZones: onResetProjection != nil ? [.trailingStrip(40)] : [],
                isEnabled: isInteractive
            ),
            primaryActionExclusionZones:
                onResetProjection != nil ? [.trailingStrip(40)] : [],
            releaseAction: onToggle,
            sourceID: folderHeaderSourceID,
            suppressesActionAnimation: false,
            entries: contextMenuEntries
        )
        .overlay {
            folderPreviewHoverAnchor
        }
        // A folder whose shell opens puts its rows in the sidebar, so the panel
        // has nothing left to preview. The hover gate only refuses to open; an
        // already-open panel has to be taken down outright, without the hover
        // grace, or it lingers over the rows that just appeared.
        .onChange(of: folderShellIsClosed) { _, isClosed in
            guard !isClosed else { return }
            windowState.sidebarFolderPreview.close(folderID: folder.id)
        }
        .accessibilityIdentifier("folder-header-\(folder.id.uuidString)")
        .accessibilityLabel(presentation.title)
        .accessibilityValue(presentation.isExpanded ? "expanded" : "collapsed")
    }

    private var folderGlyphPresentation: SumiFolderGlyphPresentationState {
        SumiFolderGlyphPresentationState(
            iconValue: presentation.iconValue,
            isOpen: folderPreviewIsOpen,
            hasActiveProjection: hasActiveProjection
                || hasActiveSelection
                || contentProjection.hasCollapsedProjectionForLayout
        )
    }

    @ViewBuilder
    private var folderPreviewHoverAnchor: some View {
        SidebarFolderPreviewAnchorBridge(
            hoverSession: windowState.sidebarInteractionState.hoverSession,
            isEnabled: folderPreviewHoverIsEnabled,
            onOpen: { anchorView, anchorRect in
                openFolderPreview(anchorView: anchorView, anchorRect: anchorRect)
            },
            onHoverChanged: { hovering in
                windowState.sidebarFolderPreview.setAnchorHovered(
                    folderID: folder.id,
                    hovering: hovering
                )
            }
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func openFolderPreview(anchorView: NSView, anchorRect: CGRect) {
        let candidates = folderPreviewCandidates
        guard folderPreviewHoverIsEnabled,
              SidebarFolderPreviewHoverPolicy.allowsOpen(
                  isSidebarDragging: isDragging,
                  isHeaderPressed: windowState.sidebarInteractionState
                      .presentsPressVisual(for: folderHeaderSourceID),
                  isTextEntryActive: SidebarFolderPreviewAnchorBridge.isTextEntryActive(
                      in: anchorView.window
                  )
              ),
              !candidates.isEmpty
        else { return }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: anchorView.window ?? windowState.shellWindow(in: windowRegistry),
            ownerView: anchorView
        )
        windowState.sidebarFolderPreview.open(
            request: SidebarFolderPreviewRequest(
                folderID: folder.id,
                folderName: presentation.title,
                candidates: candidates,
                anchorRect: anchorRect
            ),
            sidebarPosition: sumiSettings.sidebarPosition,
            source: source
        )
    }

    private var folderPreviewCandidates: [FolderSearchCandidate] {
        let builder = FolderSearchCandidateBuilder(
            inventory: inventory,
            selection: selection,
            windowState: windowState,
            liveFolderProvider: browserContext.liveFolderManager,
            faviconImageReader: browserContext.faviconImageReader,
            pinProjection: pinProjection,
            actions: FolderSearchActivationActions(
                activateShortcut: { pin in
                    onActivateShortcutPin(pin)
                },
                activateLiveItem: { item in
                    browserContext.liveFolderManager.open(item: item, in: windowState)
                },
                activateSplitGroupItem: { item, group in
                    browserContext.splitFocusCommands.focusGroup(
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
        return candidates
    }
}
