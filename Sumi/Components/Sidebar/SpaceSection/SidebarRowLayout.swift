//
//  SidebarRowLayout.swift
//  Sumi
//

import SwiftUI

enum SidebarRowLayout {
    static let rowHeight: CGFloat = 36
    static let selectionZIndex: Double = 1
    static let selectionShadowRadius: CGFloat = 1.5
    static let selectionShadowYOffset: CGFloat = 0.8
    static let selectionShadowBleed: CGFloat = 3
    static let titleLineBoxHeight: CGFloat = 16
    static let titleHeight: CGFloat = titleLineBoxHeight
    static let faviconSize: CGFloat = 18
    static let leadingInset: CGFloat = 12
    static let iconTrailingSpacing: CGFloat = 8
    static let trailingInset: CGFloat = 10
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
}

enum SidebarSelectionElevation {
    static func zIndex(isElevated: Bool) -> Double {
        isElevated ? SidebarRowLayout.selectionZIndex : 0
    }

    static func splitGroupContainsCurrentTab(_ group: SplitGroup, currentTabId: UUID?) -> Bool {
        guard let currentTabId else { return false }
        return group.contains(currentTabId)
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

        let surface = rowSurface(content: content, shape: shape, drawsShadow: drawsShadow)

        if drawsShadow {
            surface
                .padding(SidebarRowLayout.selectionShadowBleed)
                .padding(-SidebarRowLayout.selectionShadowBleed)
                .zIndex(SidebarRowLayout.selectionZIndex)
        } else {
            surface
        }
    }

    private func rowSurface(
        content: Content,
        shape: RoundedRectangle,
        drawsShadow: Bool
    ) -> some View {
        ZStack {
            if isVisible {
                shape
                    .fill(background)
                    .shadow(
                        color: drawsShadow ? tokens.sidebarSelectionShadow : .clear,
                        radius: SidebarRowLayout.selectionShadowRadius,
                        x: 0,
                        y: SidebarRowLayout.selectionShadowYOffset
                    )
                    .allowsHitTesting(false)
            }

            content
        }
        .contentShape(shape)
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
}
