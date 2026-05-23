//
//  SpacesListItem.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let space: Space
    let isActive: Bool
    let compact: Bool
    let isFaded: Bool
    let metrics: SpaceStripMetrics
    let onSelect: () -> Void
    let onHoverChange: ((Bool) -> Void)?

    @StateObject private var emojiManager = EmojiPickerManager()
    @State private var isHovered = false

    init(
        space: Space,
        isActive: Bool,
        compact: Bool,
        isFaded: Bool,
        metrics: SpaceStripMetrics,
        onSelect: @escaping () -> Void,
        onHoverChange: ((Bool) -> Void)? = nil
    ) {
        self.space = space
        self.isActive = isActive
        self.compact = compact
        self.isFaded = isFaded
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
                .opacity(isActive ? 1.0 : 0.7)
                .frame(maxWidth: .infinity)
        }
        .frame(width: metrics.slotSize, height: metrics.slotSize)
        .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        .opacity(isFaded ? 0.3 : 1.0)
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
        if compact && !isActive {
            // Compact mode: show dot
            Circle()
                .fill(iconColor)
                .frame(width: metrics.dotSize, height: metrics.dotSize)
        } else {
            // Normal mode: show icon or emoji
            if SumiPersistentGlyph.presentsAsEmoji(space.icon) {
                Text(space.icon)
                    .conditionally(if: !isActive, apply: { view in
                        view.colorMultiply(.gray).blendMode(.luminosity)
                    })
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(newValue)
                        browserManager.tabManager.markAllSpacesStructurallyDirty()
                        browserManager.tabManager.scheduleStructuralPersistence()
                    }

            } else {
                Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(space.icon))
                    .foregroundStyle(iconColor)
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(newValue)
                        browserManager.tabManager.markAllSpacesStructurallyDirty()
                        browserManager.tabManager.scheduleStructuralPersistence()
                    }
            }
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
        if browserManager.tabManager.spaces.count > 1 {
            deleteSpaceAction = { showDeleteConfirmation() }
        } else {
            deleteSpaceAction = nil
        }

        let actions = SidebarSpaceMenuActions(
            edit: {
                browserManager.showSpaceEditor(
                    for: space,
                    in: windowState,
                    themeContext: themeContext,
                    source: windowState.resolveSidebarPresentationSource()
                )
            },
            changeTheme: {
                browserManager.showGradientEditor(
                    for: space,
                    source: windowState.resolveSidebarPresentationSource()
                )
            },
            deleteSpace: deleteSpaceAction
        )

        return makeSpaceContextMenuEntries(actions: actions)
    }

    // MARK: - Helper Methods

    private func showDeleteConfirmation() {
        SpaceDeletionConfirmationPresenter.confirmDelete(
            space: space,
            browserManager: browserManager,
            window: windowState.window
        )
    }

}
