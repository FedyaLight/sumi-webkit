//
//  SidebarRowLayout.swift
//  Sumi
//

import SumiDomain
import SwiftUI

enum SidebarRowLayout {
    static let rowHeight: CGFloat = 36
    static let defaultCornerRadius: CGFloat = 12
    static let selectionZIndex: Double = 1
    static let selectionShadowRadius: CGFloat = 1.5
    static let selectionShadowYOffset: CGFloat = 0.8
    static let selectionShadowBleed: CGFloat = 3
    static let titleHeight: CGFloat = 16
    static let faviconSize: CGFloat = 18
    static let leadingInset: CGFloat = 12
    static let iconTrailingSpacing: CGFloat = 8
    static let trailingInset: CGFloat = 10
    /// Uniform vertical gap between adjacent rows (pinned, regular, New-Tab) —
    /// matches Zen's 4px row rhythm.
    static let rowGap: CGFloat = 4
    /// Exact visual pitch between two stacked uniform rows (row height + gap).
    /// Drop geometry uses this constant directly rather than reverse-engineering
    /// it from a measured frame, so the indicator/resolver can never drift from
    /// the rendered layout.
    static let rowPitch: CGFloat = rowHeight + rowGap
    static let folderBodyPadding: CGFloat = 4
    static let trailingActionSize: CGFloat = 24
    static let trailingActionGap: CGFloat = 4
    static let trailingActionPadding: CGFloat = trailingActionSize + trailingActionGap
    static let folderGlyphSize: CGFloat = 28
    /// Centers the 28pt folder glyph on the 18pt favicon column (layout width before title stays `folderTitleLeading`).
    static let folderHeaderGlyphCenteringOffset: CGFloat = (faviconSize - folderGlyphSize) * 0.5
    /// Horizontal offset from row leading to folder title text (matches favicon column + gap before title).
    static let folderTitleLeading: CGFloat = faviconSize + iconTrailingSpacing
    static let changedLauncherResetWidth: CGFloat = 42
    static let changedLauncherTitleLeading: CGFloat = 4
    static let changedLauncherSeparatorWidth: CGFloat = 2.5
    static let changedLauncherSeparatorHeight: CGFloat = 14
    static let changedLauncherResetHeight: CGFloat = rowHeight
    static let changedLauncherResetIconLeading: CGFloat = 12
    static let changedLauncherResetTrailingGap: CGFloat = 4

    static func leadingActionShape(cornerRadius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: cornerRadius,
                bottomLeading: cornerRadius
            ),
            style: .continuous
        )
    }
}

/// Single-line sidebar title that absorbs the width left by row accessories.
struct SidebarRowTitleLabel: View {
    let title: String
    let font: Font
    let color: Color
    var height: CGFloat = SidebarRowLayout.titleHeight

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .leading)
            .layoutPriority(1)
            .accessibilityLabel(title)
    }
}

enum SidebarSelectionElevation {
    static func zIndex(isElevated: Bool) -> Double {
        isElevated ? SidebarRowLayout.selectionZIndex : 0
    }

    static func splitGroupIsSelected(
        _ group: SplitGroup,
        selectedGroupID: UUID?
    ) -> Bool {
        group.id == selectedGroupID
    }

    static func folderContainsSelection(
        folderId: UUID,
        visited: Set<UUID> = [],
        folderPins: (UUID) -> [ShortcutPin],
        childFolders: (UUID) -> [TabFolder],
        splitGroups: (UUID) -> [SplitGroup],
        isShortcutElevated: (ShortcutPin) -> Bool,
        isSplitGroupElevated: (SplitGroup) -> Bool
    ) -> Bool {
        guard !visited.contains(folderId) else {
            return false
        }
        var nextVisited = visited
        nextVisited.insert(folderId)

        if folderPins(folderId).contains(where: isShortcutElevated) {
            return true
        }
        if splitGroups(folderId).contains(where: isSplitGroupElevated) {
            return true
        }
        return childFolders(folderId).contains { childFolder in
            folderContainsSelection(
                folderId: childFolder.id,
                visited: nextVisited,
                folderPins: folderPins,
                childFolders: childFolders,
                splitGroups: splitGroups,
                isShortcutElevated: isShortcutElevated,
                isSplitGroupElevated: isSplitGroupElevated
            )
        }
    }
}

private struct SidebarRowSurfaceModifier: ViewModifier {
    let background: Color
    let cornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let isVisible: Bool
    let drawsSelectionShadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let drawsShadow = isVisible && drawsSelectionShadow
        let bleed = drawsShadow ? SidebarRowLayout.selectionShadowBleed : 0

        rowSurface(content: content, shape: shape, drawsShadow: drawsShadow)
            .padding(bleed)
            .padding(-bleed)
            .zIndex(drawsShadow ? SidebarRowLayout.selectionZIndex : 0)
    }

    private func rowSurface(
        content: Content,
        shape: RoundedRectangle,
        drawsShadow: Bool
    ) -> some View {
        content
            .background {
                shape
                    .fill(background)
                    .opacity(isVisible ? 1 : 0)
                    .shadow(
                        color: drawsShadow ? tokens.sidebarSelectionShadow : .clear,
                        radius: SidebarRowLayout.selectionShadowRadius,
                        x: 0,
                        y: SidebarRowLayout.selectionShadowYOffset
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

private struct SidebarDropContainmentBackdropModifier: ViewModifier {
    let isVisible: Bool

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var color: Color {
        (scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings))
            .sidebarRowHover
    }

    func body(content: Content) -> some View {
        content.background {
            if isVisible {
                Rectangle()
                    .fill(color)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func sidebarRowSurface(
        background: Color,
        cornerRadius: CGFloat,
        tokens: ChromeThemeTokens,
        isVisible: Bool,
        drawsSelectionShadow: Bool
    ) -> some View {
        modifier(
            SidebarRowSurfaceModifier(
                background: background,
                cornerRadius: cornerRadius,
                tokens: tokens,
                isVisible: isVisible,
                drawsSelectionShadow: drawsSelectionShadow
            )
        )
    }

    func sidebarDropContainmentBackdrop(isVisible: Bool) -> some View {
        modifier(
            SidebarDropContainmentBackdropModifier(isVisible: isVisible)
        )
    }
}
