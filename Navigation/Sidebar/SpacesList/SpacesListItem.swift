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
                        .primaryText
                        .opacity(displayIsHovering ? hoverBackgroundOpacity : 0)
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

    private var hoverBackgroundOpacity: Double {
        themeContext.chromeColorScheme == .dark ? 0.2 : 0.1
    }


    // MARK: - Context Menu

    private func spaceContextMenuEntries() -> [SidebarContextMenuEntry] {
        let canDeleteSpace: Bool = browserManager.tabManager.spaces.count > 1
        let deleteAction: (() -> Void)? = canDeleteSpace ? { showDeleteConfirmation() } : nil
        let callbacks = SidebarSpaceListMenuCallbacks(
            onOpenSettings: { showSpaceEditDialog() },
            onDeleteSpace: deleteAction
        )

        return makeSpaceListContextMenuEntries(
            canDelete: canDeleteSpace,
            callbacks: callbacks
        )
    }

    // MARK: - Helper Methods

    private func showDeleteConfirmation() {
        let tabsCount = browserManager.tabManager.userVisibleTabCount(for: space.id)
        let source = windowState.resolveSidebarPresentationSource()

        browserManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabsCount,
                isLastSpace: browserManager.tabManager.spaces.count <= 1,
                onDelete: {
                    browserManager.closeDialog()
                    DispatchQueue.main.async {
                        browserManager.tabManager.removeSpace(space.id)
                    }
                },
                onCancel: {
                    browserManager.closeDialog()
                }
            ),
            source: source
        )
    }

    private func showSpaceEditDialog() {
        let source = windowState.resolveSidebarPresentationSource()
        browserManager.showDialog(
            SpaceEditDialog(
                space: space,
                onSave: { newName, newIcon, newProfileId in
                    browserManager.closeDialog()
                    DispatchQueue.main.async {
                        do {
                            if newIcon != space.icon {
                                try browserManager.tabManager.updateSpaceIcon(
                                    spaceId: space.id,
                                    icon: newIcon
                                )
                            }

                            if newName != space.name {
                                try browserManager.tabManager.renameSpace(
                                    spaceId: space.id,
                                    newName: newName
                                )
                            }

                            if newProfileId != space.profileId, let profileId = newProfileId {
                                browserManager.tabManager.assign(spaceId: space.id, toProfile: profileId)
                            }
                        } catch {
                            RuntimeDiagnostics.emit("⚠️ Failed to update space \(space.id.uuidString):", error)
                        }
                    }
                },
                onCancel: {
                    browserManager.closeDialog()
                }
            ),
            source: source
        )
    }

}

struct SpaceListItemButtonStyle: ButtonStyle {
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    let isHovering: Bool

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tokens.primaryText.opacity(backgroundColorOpacity(isPressed: configuration.isPressed)))

            configuration.label
                .foregroundStyle(tokens.primaryText)
        }
        .frame(height: size)
        .frame(maxWidth: size)
        .opacity(isEnabled ? 1.0 : 0.3)
        
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var size: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }
    
//    private var iconSize: CGFloat {
//        switch controlSize {
//        case .mini: 12
//        case .small: 14
//        case .regular: 16
//        case .large: 18
//        case .extraLarge: 20
//        @unknown default: 16
//        }
//    }
    
    private var cornerRadius: CGFloat {
        8
    }
    
    private func backgroundColorOpacity(isPressed: Bool) -> Double {
        if (isHovering || isPressed) && isEnabled {
            return themeContext.chromeColorScheme == .dark ? 0.2 : 0.1
        } else {
            return 0.0
        }
    }
}
