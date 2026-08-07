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
    @Environment(\.sidebarPresentationContext) private var presentationContext

    let space: Space
    let browserContext: SidebarBrowserContext
    let spaceLifecycle: SidebarSpaceLifecycle
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
        spaceLifecycle: SidebarSpaceLifecycle,
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
        self.spaceLifecycle = spaceLifecycle
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
        .modifier(
            SpacesListItemHoverModifier(
                isHovered: $isHovered,
                usesNativeHover: presentationContext.isCollapsedOverlay,
                isEnabled: presentationContext.allowsInteractiveWork
            )
        )
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
            let icon = SumiPersistentGlyph.normalizedSpaceIconValue(newValue)
            do {
                try spaceLifecycle.updateSpaceIcon(space.id, to: icon)
            } catch {
                RuntimeDiagnostics.emit("⚠️ Failed to update space icon \(space.id.uuidString):", error)
            }
        }
    }

    private var iconColor: Color {
        themeContext.tokens(settings: sumiSettings).primaryText
    }

    private var displayIsHovering: Bool {
        isHovered
    }

    // MARK: - Context Menu

    private func spaceContextMenuEntries() -> [SidebarContextMenuEntry] {
        let deleteSpaceAction: (() -> Void)?
        let clearSpaceAction: (() -> Void)?
        if spaceLifecycle.canDeleteSpace() {
            deleteSpaceAction = { showDeleteConfirmation() }
            clearSpaceAction = nil
        } else {
            deleteSpaceAction = nil
            clearSpaceAction = { showClearConfirmation() }
        }

        let actions = SidebarSpaceMenuActions(
            edit: {
                browserContext.spaceEditorPresentation.show(
                    space: space,
                    in: windowState,
                    themeContext: themeContext,
                    source: windowState.resolveSidebarPresentationSource(
                        in: windowRegistry
                    )
                )
            },
            changeTheme: {
                browserContext.workspaceThemeEditor.showGradientEditor(
                    for: space,
                    source: windowState.resolveSidebarPresentationSource(
                        in: windowRegistry
                    )
                )
            },
            deleteSpace: deleteSpaceAction,
            clearSpace: clearSpaceAction
        )

        return makeSpaceContextMenuEntries(actions: actions)
    }

    // MARK: - Helper Methods

    private func showDeleteConfirmation() {
        browserContext.spaceDeletionPresentation.confirmDelete(
            space,
            in: windowState
        )
    }

    private func showClearConfirmation() {
        browserContext.spaceDeletionPresentation.confirmClear(
            space,
            in: windowState
        )
    }
}

/// The nested collapsed host needs SwiftUI's native tracking path; docked mode
/// keeps the shared sidebar hover session and its scroll/drag suppression.
private struct SpacesListItemHoverModifier: ViewModifier {
    @Binding var isHovered: Bool
    let usesNativeHover: Bool
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesNativeHover {
            content
                .onHover { hovering in
                    isHovered = isEnabled && hovering
                }
                .onChange(of: isEnabled) { _, enabled in
                    if !enabled {
                        isHovered = false
                    }
                }
        } else {
            content.sidebarHover($isHovered, isEnabled: isEnabled)
        }
    }
}
