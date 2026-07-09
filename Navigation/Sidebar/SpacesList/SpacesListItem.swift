//
//  SpacesListItem.swift
//  Sumi
//
//

import SwiftUI

struct SpacesListItem: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let space: Space
    let browserContext: SidebarBrowserContext
    let isActive: Bool
    let isFaded: Bool
    /// When true the item collapses its icon to a small dot (the strip's
    /// compact overflow treatment); hover and activity restore the icon.
    let showsCompactDot: Bool
    let slotWidth: CGFloat
    let metrics: SpaceStripMetrics
    let onSelect: () -> Void
    let onHoverChange: ((Bool) -> Void)?

    @StateObject private var emojiManager = EmojiPickerManager()
    @State private var isHovered = false

    init(
        space: Space,
        browserContext: SidebarBrowserContext,
        isActive: Bool,
        isFaded: Bool,
        showsCompactDot: Bool,
        slotWidth: CGFloat,
        metrics: SpaceStripMetrics,
        onSelect: @escaping () -> Void,
        onHoverChange: ((Bool) -> Void)? = nil
    ) {
        self.space = space
        self.browserContext = browserContext
        self.isActive = isActive
        self.isFaded = isFaded
        self.showsCompactDot = showsCompactDot
        self.slotWidth = slotWidth
        self.metrics = metrics
        self.onSelect = onSelect
        self.onHoverChange = onHoverChange
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(
                    themeContext
                        .tokens(settings: sumiSettings)
                        .chromeControlHoverBackground
                        .opacity(displayIsHovering ? 1 : 0)
                )

            spaceIcon
                .opacity(showsCompactDot ? 0 : (isActive ? 1.0 : 0.7))
                .scaleEffect(showsCompactDot ? 0.1 : 1)
                .frame(maxWidth: .infinity)

            Circle()
                .fill(iconColor.opacity(0.45))
                .frame(width: metrics.compactDotSize, height: metrics.compactDotSize)
                .opacity(showsCompactDot ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: showsCompactDot)
        .frame(width: slotWidth, height: metrics.slotSize)
        .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        .opacity(isFaded ? 0.3 : 1.0)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("space-icon-\(space.id.uuidString)")
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect()
        }
        .sidebarDDGHover($isHovered)
        .onChange(of: displayIsHovering) { _, hovering in
            onHoverChange?(hovering)
        }
        .onDisappear {
            onHoverChange?(false)
        }
        .sidebarAppKitContextMenu(entries: {
            spaceContextMenuEntries()
        })
    }

    // MARK: - Icon

    @ViewBuilder
    private var spaceIcon: some View {
        SpaceIconGlyphView(
            iconValue: space.icon,
            textColor: iconColor,
            defaultDotSize: metrics.dotSize,
            emojiFont: .body,
            systemFont: .body,
            desaturatesEmoji: !isActive,
            hidesAccessibility: true
        )
        .background(EmojiPickerAnchor(manager: emojiManager))
        .onChange(of: emojiManager.selectedEmoji) { _, newValue in
            guard !newValue.isEmpty else { return }
            space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(newValue)
            browserContext.tabManager.structuralPersistence.markAllSpacesStructurallyDirty()
            browserContext.tabManager.scheduleStructuralPersistence()
        }
    }

    private var iconColor: Color {
        themeContext.tokens(settings: sumiSettings).primaryText
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    // MARK: - Context Menu

    private func spaceContextMenuEntries() -> [SidebarContextMenuEntry] {
        let deleteSpaceAction: (() -> Void)?
        if browserContext.tabManager.spaceStateOwner.spaces.count > 1 {
            deleteSpaceAction = { showDeleteConfirmation() }
        } else {
            deleteSpaceAction = nil
        }

        let actions = SidebarSpaceMenuActions(
            edit: {
                browserContext.presentationActions.showSpaceEditor(
                    space,
                    windowState,
                    themeContext,
                    windowState.resolveSidebarPresentationSource(in: windowRegistry)
                )
            },
            changeTheme: {
                browserContext.presentationActions.showGradientEditorForSpace(
                    space,
                    windowState.resolveSidebarPresentationSource(in: windowRegistry)
                )
            },
            deleteSpace: deleteSpaceAction
        )

        return makeSpaceContextMenuEntries(actions: actions)
    }

    // MARK: - Helper Methods

    private func showDeleteConfirmation() {
        browserContext.presentationActions.confirmDeleteSpace(
            space,
            windowState
        )
    }
}
