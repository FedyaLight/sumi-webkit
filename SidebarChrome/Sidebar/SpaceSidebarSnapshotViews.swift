//
//  SpaceSidebarSnapshotViews.swift
//  Sumi
//
//

import SwiftUI

@MainActor
struct SpaceTransitionSnapshotPageView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let includesTopSidebarContent: Bool
    let width: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    private var innerWidth: CGFloat {
        BrowserWindowState.sidebarContentWidth(for: width)
    }

    var body: some View {
        VStack(spacing: 8) {
            if includesTopSidebarContent, let extensionActions = snapshot.extensionActions {
                ExtensionActionSnapshotGrid(
                    snapshot: extensionActions,
                    tokens: tokens
                )
                .padding(.horizontal, 8)
            }

            if includesTopSidebarContent, let essentials = snapshot.essentials {
                EssentialsSnapshotGrid(
                    snapshot: essentials,
                    width: innerWidth,
                    tokens: tokens
                )
                .padding(.horizontal, 8)
            }

            VStack(spacing: 4) {
                SpaceSnapshotTitleView(
                    title: snapshot.title,
                    iconValue: snapshot.iconValue,
                    rowCornerRadius: snapshot.rowCornerRadius,
                    tokens: tokens
                )

                SpaceSnapshotContentView(
                    snapshot: snapshot,
                    innerWidth: innerWidth,
                    tokens: tokens,
                    themeContext: themeContext
                )
            }
            .padding(.horizontal, 8)
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }
}

struct ExtensionActionSnapshotGrid: View {
    let snapshot: ExtensionActionGridSnapshot
    let tokens: ChromeThemeTokens
    private static let gridSpacing: CGFloat = 8

    private func columns(slotCount: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 0, maximum: .infinity),
                spacing: Self.gridSpacing,
                alignment: .center
            ),
            count: max(slotCount, 1)
        )
    }

    var body: some View {
        let slots = snapshot.slots

        LazyVGrid(columns: columns(slotCount: slots.count), alignment: .leading, spacing: Self.gridSpacing) {
            ForEach(slots) { slot in
                ExtensionActionSnapshotButton(slot: slot, tokens: tokens)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("sidebar-extension-action-grid-snapshot")
    }
}

private struct ExtensionActionSnapshotButton: View {
    let slot: ExtensionActionSlotSnapshot
    let tokens: ChromeThemeTokens
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        iconView
            .frame(width: 16, height: 16)
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(tokens.pinnedIdleBackground)
            .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let badgeText = slot.badgeText {
                    Text(badgeText)
                        .font(SidebarThemeTokens.Typography.extensionActionBadge)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 10, minHeight: 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(slot.hasUnreadBadgeText ? 0.95 : 0.78))
                        )
                        .padding(2)
                }
            }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = slot.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(SidebarThemeTokens.Typography.extensionActionFallbackIcon)
                .foregroundStyle(tokens.primaryText)
                .accessibilityHidden(true)
        }
    }
}

private struct SpaceSnapshotContentView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let innerWidth: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        GeometryReader { geometry in
            let viewportHeight = max(geometry.size.height, 0)
            let contentOffsetY = snapshot.scrollViewport.clampedOffset(for: viewportHeight)

            contentStack
                .frame(width: innerWidth, alignment: .topLeading)
                .offset(y: -contentOffsetY)
                .frame(width: innerWidth, alignment: .topLeading)
        }
        .clipped()
        .accessibilityIdentifier("space-transition-snapshot-content-\(snapshot.spaceId.uuidString)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var contentStack: some View {
        VStack(spacing: 8) {
            SpaceSnapshotPinnedSectionView(
                items: snapshot.pinnedItems,
                rowCornerRadius: snapshot.rowCornerRadius,
                tokens: tokens,
                themeContext: themeContext
            )

            SpaceSnapshotRegularTabsSectionView(
                snapshot: snapshot,
                innerWidth: innerWidth,
                tokens: tokens
            )
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
    }
}

private struct SpaceSnapshotTitleView: View {
    let title: String
    let iconValue: String
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        SpaceTitleRowChrome(
            backgroundColor: .clear,
            cornerRadius: rowCornerRadius
        ) {
            SpaceTitleIconView(
                iconValue: iconValue,
                textColor: tokens.primaryText,
                hidesAccessibility: true
            )
            .id(iconValue)
        } title: {
            SpaceTitleTextLabel(
                title: title,
                textColor: tokens.primaryText
            )
        } trailing: {
            Color.clear
                .accessibilityHidden(true)
        }
        .id(SpaceSnapshotTitleIdentity(title: title, iconValue: iconValue))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("space-transition-snapshot-title")
    }
}

private struct SpaceSnapshotTitleIdentity: Hashable {
    let title: String
    let iconValue: String
}

@MainActor
struct EssentialsSnapshotGrid: View {
    let snapshot: EssentialsSnapshot
    let width: CGFloat
    let tokens: ChromeThemeTokens

    private var rows: [EssentialsSnapshotRow] {
        let columns = capacityColumnCount
        guard !snapshot.items.isEmpty else { return [] }

        return stride(from: 0, to: snapshot.items.count, by: columns).map { index in
            let rowItems = Array(snapshot.items[index..<min(index + columns, snapshot.items.count)])
            let visualColumnCount = max(1, min(rowItems.count, columns))
            let tileSize = visualTileSize(visualColumnCount: visualColumnCount)
            return EssentialsSnapshotRow(items: rowItems, tileSize: tileSize)
        }
    }

    private var capacityColumnCount: Int {
        guard width > 0 else { return 1 }

        var columns = SidebarEssentialsProjectionPolicy.maxColumns
        while columns > 1 {
            let neededWidth = CGFloat(columns) * PinnedTileMetrics.minWidth
                + CGFloat(columns - 1) * PinnedTileMetrics.gridSpacing
            if neededWidth <= width {
                break
            }
            columns -= 1
        }
        return max(1, columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PinnedTileMetrics.gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: PinnedTileMetrics.gridSpacing) {
                    ForEach(row.items) { item in
                        SpaceSnapshotPinnedTileView(
                            item: item,
                            tileSize: row.tileSize,
                            tokens: tokens
                        )
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(height: rows.isEmpty ? 6 : nil, alignment: .top)
    }

    private func visualTileSize(visualColumnCount: Int) -> CGSize {
        let columns = max(visualColumnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * PinnedTileMetrics.gridSpacing), 0)
        let tileWidth = max(availableWidth / CGFloat(columns), PinnedTileMetrics.minWidth)
        return CGSize(width: tileWidth, height: PinnedTileMetrics.height)
    }

    private struct EssentialsSnapshotRow {
        let items: [SpaceShortcutSnapshot]
        let tileSize: CGSize
    }
}

private struct SpaceSnapshotPinnedSectionView: View {
    let items: [SpacePinnedItemSnapshot]
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        Group {
            if items.isEmpty {
                Color.clear
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: SidebarInsertionGuide.visualCenterY)

                    ForEach(items) { item in
                        SpaceSnapshotPinnedItemView(
                            item: item,
                            rowCornerRadius: rowCornerRadius,
                            tokens: tokens,
                            themeContext: themeContext
                        )
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SpaceSnapshotPinnedItemView: View {
    let item: SpacePinnedItemSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        switch item {
        case .folder(let folder):
            SpaceSnapshotFolderView(
                folder: folder,
                rowCornerRadius: rowCornerRadius,
                tokens: tokens,
                themeContext: themeContext
            )
        case .shortcut(let shortcut):
            SpaceSnapshotShortcutRowView(
                shortcut: shortcut,
                rowCornerRadius: rowCornerRadius,
                tokens: tokens
            )
        }
    }
}

private struct SpaceSnapshotFolderView: View {
    let folder: SpaceFolderSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    private var showsBody: Bool {
        folder.isOpen || !folder.bodyChildren.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear
                        .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
                    SumiFolderGlyphView(
                        presentation: SumiFolderGlyphPresentationState(
                            iconValue: folder.iconValue,
                            isOpen: folder.isOpen,
                            hasActiveProjection: folder.hasActiveSelection
                        ),
                        palette: folderPalette
                    )
                    .frame(
                        width: SidebarRowLayout.folderGlyphSize,
                        height: SidebarRowLayout.folderGlyphSize,
                        alignment: .center
                    )
                    .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
                }
                .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)

            SidebarFadingRowTitleLabel(
                title: folder.title,
                font: SidebarThemeTokens.Typography.folderTitle,
                color: tokens.primaryText
            )

                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))

            if showsBody {
                VStack(spacing: 0) {
                    ForEach(folder.bodyChildren) { child in
                        SpaceSnapshotPinnedItemView(
                            item: child,
                            rowCornerRadius: rowCornerRadius,
                            tokens: tokens,
                            themeContext: themeContext
                        )
                    }
                }
                .padding(.leading, SpaceSidebarSnapshotFolderLayout.contentLeadingPadding)
                .padding(.vertical, SpaceSidebarSnapshotFolderLayout.contentVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(tokens.separator.opacity(0.55))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                        .offset(x: 6)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var folderPalette: SumiFolderGlyphPalette {
        SumiFolderGlyphPalette.sidebarFolder(
            accent: themeContext.gradient.primaryColor,
            chromeColorScheme: themeContext.chromeColorScheme,
            primaryText: tokens.primaryText
        )
    }
}

private struct SpaceSnapshotShortcutRowView: View {
    let shortcut: SpaceShortcutSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        HStack(spacing: 0) {
            SpaceSnapshotIconView(
                icon: shortcut.icon,
                size: SidebarRowLayout.faviconSize,
                foregroundColor: tokens.primaryText
            )
            .saturation(shortcut.presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
            .opacity(shortcut.presentationState.shouldDesaturateIcon ? 0.8 : 1.0)
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)

            if shortcut.showsAudioButton {
                SpaceSnapshotRowAudioGlyph(isMuted: shortcut.isMuted, tokens: tokens)
                    .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
            }

            SidebarFadingRowTitleLabel(
                title: shortcut.title,
                font: SidebarThemeTokens.Typography.rowTitle,
                color: tokens.primaryText,
                height: SidebarRowLayout.titleHeight
            )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowSurface(
            background: shortcut.presentationState.isSelected ? tokens.sidebarRowActive : .clear,
            cornerRadius: rowCornerRadius,
            tokens: tokens,
            isVisible: shortcut.presentationState.isSelected,
            drawsSelectionShadow: shortcut.presentationState.isSelected
        )
    }
}

private struct SpaceSnapshotRegularTabsSectionView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let innerWidth: CGFloat
    let tokens: ChromeThemeTokens

    private var showsBottomNewTabButton: Bool {
        snapshot.showsNewTabButtonInList && !snapshot.showsTopNewTabButton
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 100)
                .fill(tokens.separator.opacity(0.82))
                .frame(height: 1)
                .padding(.horizontal, 8)
                .frame(height: 2)

            VStack(spacing: 2) {
                if snapshot.showsNewTabButtonInList && snapshot.showsTopNewTabButton {
                    newTabRow
                        .padding(.top, 4)
                }

                VStack(spacing: 2) {
                    ForEach(snapshot.regularTabs) { tab in
                        SpaceSnapshotRegularTabRowView(
                            tab: tab,
                            rowCornerRadius: snapshot.rowCornerRadius,
                            tokens: tokens
                        )
                    }
                }
                .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)

                if showsBottomNewTabButton {
                    newTabRow
                }
            }
            .padding(.top, 8)

            Color.clear
                .frame(height: snapshot.regularTabs.isEmpty ? 48 : 24)
        }
    }

    private var newTabRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .accessibilityHidden(true)
            Text("New Tab")
            Spacer(minLength: 0)
        }
        .font(SidebarThemeTokens.Typography.newTabRow)
        .foregroundStyle(tokens.primaryText)
        .padding(.horizontal, 10)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SpaceSnapshotRegularTabRowView: View {
    let tab: SpaceTabRowSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        HStack(spacing: 8) {
            favicon

            if tab.showsAudioButton {
                SpaceSnapshotRowAudioGlyph(isMuted: tab.isMuted, tokens: tokens)
            }

            SidebarFadingRowTitleLabel(
                title: tab.title,
                font: SidebarThemeTokens.Typography.rowTitle,
                color: tokens.primaryText,
                height: SidebarRowLayout.titleHeight
            )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowSurface(
            background: tab.isSelected ? tokens.sidebarRowActive : .clear,
            cornerRadius: rowCornerRadius,
            tokens: tokens,
            isVisible: tab.isSelected,
            drawsSelectionShadow: tab.isSelected
        )
    }

    @ViewBuilder
    private var favicon: some View {
        if tab.showsUnloadedIndicator {
            SidebarUnloadedRegularTabFaviconIndicator(
                size: SidebarRowLayout.faviconSize
            ) {
                SpaceSnapshotIconView(
                    icon: tab.icon,
                    size: SidebarRowLayout.faviconSize,
                    foregroundColor: tokens.primaryText
                )
            }
        } else {
            SpaceSnapshotIconView(
                icon: tab.icon,
                size: SidebarRowLayout.faviconSize,
                foregroundColor: tokens.primaryText
            )
        }
    }
}

/// Static mute/unmute glyph for snapshot rows (regular tabs and shortcuts).
/// The live rows use interactive audio buttons; snapshots only need the glyph.
struct SpaceSnapshotRowAudioGlyph: View {
    let isMuted: Bool
    let tokens: ChromeThemeTokens

    var body: some View {
        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(SidebarThemeTokens.Typography.rowAccessory)
            .foregroundStyle(isMuted ? tokens.secondaryText : tokens.primaryText)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

struct SpaceSnapshotIconView: View {
    let icon: SpaceSidebarSnapshotIcon
    let size: CGFloat
    let foregroundColor: Color

    var body: some View {
        Group {
            switch icon {
            case .image(let image):
                image
            case .system(let systemName):
                Image(systemName: systemName)
                    .font(SidebarThemeTokens.Typography.chromeTemplateIcon(size: size))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foregroundColor)
                    .accessibilityHidden(true)
            case .emoji(let emoji):
                Text(emoji)
                    .font(SidebarThemeTokens.Typography.launcherEmoji(size: size))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
    }
}
