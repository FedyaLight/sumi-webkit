//
//  SpaceSidebarSnapshotViews.swift
//  Sumi
//
//

import SwiftUI

@MainActor
struct SpaceTransitionSnapshotPageView: View, @preconcurrency Equatable {
    let snapshot: SpaceSidebarPageSnapshot
    let includesEssentials: Bool
    let width: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    static func == (lhs: SpaceTransitionSnapshotPageView, rhs: SpaceTransitionSnapshotPageView) -> Bool {
        lhs.snapshot.spaceId == rhs.snapshot.spaceId &&
               lhs.snapshot.title == rhs.snapshot.title &&
               lhs.includesEssentials == rhs.includesEssentials &&
               lhs.width == rhs.width &&
               lhs.themeContext.chromeColorScheme == rhs.themeContext.chromeColorScheme
    }

    private var innerWidth: CGFloat {
        max(width - BrowserWindowState.sidebarHorizontalPadding, 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            if includesEssentials, let extensionActions = snapshot.extensionActions {
                ExtensionActionSnapshotGrid(
                    snapshot: extensionActions,
                    tokens: tokens
                )
                .padding(.horizontal, 8)
            }

            if includesEssentials, let essentials = snapshot.essentials {
                EssentialsSnapshotGrid(
                    snapshot: essentials,
                    width: innerWidth,
                    configuration: snapshot.pinnedTabsConfiguration,
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
                        .font(.system(size: 8, weight: .bold, design: .rounded))
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
        switch slot.kind {
        case .sumiScriptsManager:
            Image(systemName: "curlybraces.square")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .accessibilityHidden(true)
        case .webExtension:
            if let icon = slot.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct SpaceSnapshotContentView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let innerWidth: CGFloat
    let tokens: ChromeThemeTokens
    let themeContext: ResolvedThemeContext

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
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
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("space-transition-snapshot-scroll-\(snapshot.spaceId.uuidString)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SpaceSnapshotTitleView: View {
    let title: String
    let iconValue: String
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    private var spaceIconFontSize: CGFloat {
        SidebarRowLayout.faviconSize * 0.78
    }

    var body: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            Group {
                if SumiPersistentGlyph.presentsAsEmoji(iconValue) {
                    Text(iconValue)
                        .font(.system(size: spaceIconFontSize))
                } else {
                    Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(iconValue))
                        .font(.system(size: spaceIconFontSize, weight: .medium))
                        .foregroundStyle(tokens.primaryText)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(
                    width: SpaceSidebarSnapshotTitleLayout.trailingControlSize,
                    height: SpaceSidebarSnapshotTitleLayout.trailingControlSize
                )
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.vertical, SpaceSidebarSnapshotTitleLayout.verticalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: SpaceSidebarSnapshotTitleLayout.minimumHeight)
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .accessibilityIdentifier("space-transition-snapshot-title")
    }
}

struct EssentialsSnapshotGrid: View {
    let snapshot: EssentialsSnapshot
    let width: CGFloat
    let configuration: PinnedTabsConfiguration
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
            let neededWidth = CGFloat(columns) * configuration.minWidth
                + CGFloat(columns - 1) * configuration.gridSpacing
            if neededWidth <= width {
                break
            }
            columns -= 1
        }
        return max(1, columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: configuration.gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: configuration.gridSpacing) {
                    ForEach(row.items) { item in
                        SpaceSnapshotPinnedTileView(
                            item: item,
                            tileSize: row.tileSize,
                            configuration: configuration,
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
        let availableWidth = max(width - (CGFloat(columns - 1) * configuration.gridSpacing), 0)
        let tileWidth = max(availableWidth / CGFloat(columns), configuration.minWidth)
        return CGSize(width: tileWidth, height: configuration.height)
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
                LazyVStack(spacing: 0) {
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

                Text(folder.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

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
        let accent = themeContext.gradient.primaryColor

        let backFill: Color
        let frontFill: Color
        let stroke: Color

        switch themeContext.chromeColorScheme {
        case .light:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        case .dark:
            backFill = accent.mixed(with: Color(hex: "C1C1C1"), amount: 0.4)
            frontFill = accent.mixed(with: .black, amount: 0.4)
            stroke = Color(hex: "EBEBEB").mixed(with: tokens.primaryText, amount: 0.15)
        @unknown default:
            backFill = accent.mixed(with: .gray, amount: 0.4)
            frontFill = accent.mixed(with: .white, amount: 0.7)
            stroke = accent.mixed(with: .black, amount: 0.5)
        }

        let iconForeground = stroke.mixed(with: tokens.primaryText, amount: 0.35)

        return SumiFolderGlyphPalette(
            backFill: backFill,
            frontFill: frontFill,
            stroke: stroke,
            iconForeground: iconForeground,
            backOverlayTop: Color.white.opacity(0.1),
            backOverlayBottom: Color.black.opacity(0.1),
            frontOverlayTop: Color.white.opacity(0.1),
            frontOverlayBottom: Color.black.opacity(0.1)
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
                Image(systemName: shortcut.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(shortcut.isMuted ? tokens.secondaryText : tokens.primaryText)
                    .frame(width: 22, height: 22)
                    .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    .accessibilityHidden(true)
            }

            SpaceSnapshotTitleLabel(
                title: shortcut.title,
                font: .system(size: 13, weight: .medium),
                color: tokens.primaryText
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

                LazyVStack(spacing: 2) {
                    ForEach(snapshot.regularItems) { tab in
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
        .font(.system(size: 13, weight: .regular))
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
                Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tab.isMuted ? tokens.secondaryText : tokens.primaryText)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }

            SpaceSnapshotTitleLabel(
                title: tab.title,
                font: .system(size: 13, weight: .medium),
                color: tokens.primaryText
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

private struct SpaceSnapshotTitleLabel: View {
    let title: String
    let font: Font
    let color: Color
    var trailingPadding: CGFloat = 0
    var height: CGFloat = SidebarRowLayout.titleHeight

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.trailing, trailingPadding)
            .frame(height: height, alignment: .leading)
            .accessibilityLabel(title)
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
                    .font(.system(size: size * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foregroundColor)
                    .accessibilityHidden(true)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: size * 0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
    }
}
