//
//  SpaceSidebarSnapshotViews.swift
//  Sumi
//
//

import SwiftUI

struct SpaceSnapshotSplitGroupView: View {
    let splitGroup: SpaceSplitGroupSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens
    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore

    var body: some View {
        rowContent
        .padding(
            .horizontal,
            SplitGroupSidebarVisualLayout.outerRowInset
        )
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: splitGroup.isSelected ? tokens.sidebarRowActive : .clear,
            cornerRadius: rowCornerRadius,
            tokens: tokens,
            isVisible: splitGroup.isSelected,
            drawsSelectionShadow: splitGroup.isSelected
        )
        .sidebarZenPressEffectRestingGeometry()
        .task(id: memberIconLoadKey) {
            for member in splitGroup.members {
                await member.icon.load(using: faviconImageStore)
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if let customIcon = splitGroup.customIcon {
            customIconRow(customIcon)
        } else {
            segmentedRow
        }
    }

    private var segmentedRow: some View {
        SplitGroupSegmentedRow(
            slots: splitGroup.members,
            material: .settled(isSelected: splitGroup.isSelected),
            tokens: tokens,
            departingIDs: []
        ) { _, member, metrics in
            SplitGroupSegmentLabel(
                title: member.title,
                showsTitle: metrics.showsTitle(
                    member.title,
                    trailingPadding:
                        SplitGroupSidebarVisualLayout.standardTrailingPadding
                ),
                trailingPadding:
                    SplitGroupSidebarVisualLayout.standardTrailingPadding,
                textColor: tokens.primaryText
            ) {
                SplitGroupRowIconView(
                    icon: member.icon
                        .resolved(using: faviconImageStore)
                        .splitGroupRowIcon,
                    foregroundColor: tokens.primaryText,
                    desaturates: member.desaturatesIcon
                )
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func customIconRow(
        _ icon: SpaceSidebarSnapshotIcon
    ) -> some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            SpaceSnapshotIconView(
                icon: icon,
                size: SidebarRowLayout.faviconSize,
                foregroundColor: tokens.primaryText
            )
            .saturation(splitGroup.isLoaded ? 1 : 0)
            .opacity(splitGroup.isLoaded ? 1 : 0.8)

            SidebarRowTitleLabel(
                title: splitGroup.displayTitle,
                font: SidebarThemeTokens.Typography.rowTitle,
                color: tokens.primaryText
            )
        }
        .padding(
            .leading,
            SplitGroupSidebarVisualLayout.customIconLeadingInset
        )
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
    }

    private var memberIconLoadKey: String {
        splitGroup.members.map {
            $0.icon.loadKey(using: faviconImageStore)
        }.joined(separator: "|")
    }
}

private extension SpaceSidebarSnapshotIcon {
    var splitGroupRowIcon: SplitGroupRowIcon {
        switch self {
        case .image(let image):
            return .image(image)
        case .system(let systemName):
            return .system(systemName)
        case .emoji(let emoji):
            return .emoji(emoji)
        case .resolvable(_, _, let fallback):
            return fallback.splitGroupRowIcon
        }
    }
}

struct SpaceSnapshotFolderView: View {
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

            SidebarRowTitleLabel(
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
                VStack(spacing: SidebarRowLayout.rowGap) {
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

struct SpaceSnapshotShortcutRowView: View {
    let shortcut: SpaceShortcutSnapshot
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        HStack(spacing: 0) {
            if shortcut.showsChangedURLSlash {
                changedURLLeadingAction
            }

            HStack(spacing: 0) {
                if !shortcut.showsChangedURLSlash {
                    shortcutIcon
                        .padding(.leading, SidebarRowLayout.leadingInset)
                        .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                }

                if shortcut.showsAudioButton {
                    SpaceSnapshotRowAudioGlyph(isMuted: shortcut.isMuted, tokens: tokens)
                        .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                }

                SidebarRowTitleLabel(
                    title: shortcut.title,
                    font: SidebarThemeTokens.Typography.rowTitle,
                    color: tokens.primaryText,
                    height: SidebarRowLayout.titleHeight
                )
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(
                .leading,
                shortcut.showsChangedURLSlash
                    ? SidebarRowLayout.changedLauncherTitleLeading
                    : 0
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
        .sidebarZenPressEffectRestingGeometry()
    }

    private var shortcutIcon: some View {
        SpaceSnapshotIconView(
            icon: shortcut.icon,
            size: SidebarRowLayout.faviconSize,
            foregroundColor: tokens.primaryText
        )
        .saturation(shortcut.presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
        .opacity(shortcut.presentationState.shouldDesaturateIcon ? 0.8 : 1.0)
        .frame(
            width: SidebarRowLayout.faviconSize,
            height: SidebarRowLayout.faviconSize
        )
    }

    private var changedURLLeadingAction: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                shortcutIcon
                    .padding(.leading, SidebarRowLayout.changedLauncherResetIconLeading)
                Spacer(minLength: 0)
            }
            .frame(
                width: SidebarRowLayout.changedLauncherResetWidth,
                height: SidebarRowLayout.changedLauncherResetHeight,
                alignment: .leading
            )

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tokens.secondaryText.opacity(0.3))
                .frame(
                    width: SidebarRowLayout.changedLauncherSeparatorWidth,
                    height: SidebarRowLayout.changedLauncherSeparatorHeight
                )
                .rotationEffect(.degrees(15))
        }
        .frame(
            width: SidebarRowLayout.changedLauncherResetWidth,
            height: SidebarRowLayout.changedLauncherResetHeight,
            alignment: .leading
        )
        .padding(.trailing, SidebarRowLayout.changedLauncherResetTrailingGap)
    }
}

struct SpaceSnapshotRegularTabsSectionView: View {
    let snapshot: SpaceSidebarPageSnapshot
    let innerWidth: CGFloat
    let tokens: ChromeThemeTokens

    private var showsBottomNewTabButton: Bool {
        snapshot.showsNewTabButtonInList && !snapshot.showsTopNewTabButton
    }

    private var showsTopNewTabButton: Bool {
        snapshot.showsNewTabButtonInList && snapshot.showsTopNewTabButton
    }

    var body: some View {
        VStack(spacing: 0) {
            SpaceTabSectionBoundary(layout: snapshot.tabSectionBoundaryLayout) {
                RoundedRectangle(cornerRadius: 100)
                    .fill(tokens.separator.opacity(0.82))
                    .padding(.horizontal, 8)
            }

            contentColumn
        }
    }

    /// Mirrors the live `contentColumn`: rows + New-Tab at the uniform row rhythm,
    /// with the gap present only when regular rows exist (empty list stays flush).
    @ViewBuilder
    private var contentColumn: some View {
        VStack(spacing: 0) {
            if showsTopNewTabButton {
                newTabRow
                if !snapshot.regularRows.isEmpty {
                    Color.clear.frame(height: SidebarRowLayout.rowGap)
                }
            }

            VStack(spacing: SidebarRowLayout.rowGap) {
                ForEach(snapshot.regularRows) { row in
                    switch row {
                    case .tab(let tab):
                        SpaceSnapshotRegularTabRowView(
                            tab: tab,
                            rowCornerRadius: snapshot.rowCornerRadius,
                            tokens: tokens
                        )
                    case .splitGroup(let splitGroup):
                        SpaceSnapshotSplitGroupView(
                            splitGroup: splitGroup,
                            rowCornerRadius: snapshot.rowCornerRadius,
                            tokens: tokens
                        )
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)

            if showsBottomNewTabButton {
                if !snapshot.regularRows.isEmpty {
                    Color.clear.frame(height: SidebarRowLayout.rowGap)
                }
                newTabRow
            }
        }
    }

    private var newTabRow: some View {
        SidebarNewTabRowLabel(tokens: tokens)
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

            SidebarRowTitleLabel(
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
        .sidebarZenPressEffectRestingGeometry()
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
    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore

    var body: some View {
        Group {
            switch icon.resolved(using: faviconImageStore) {
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
            case .resolvable:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .task(id: icon.loadKey(using: faviconImageStore)) {
            await icon.load(using: faviconImageStore)
        }
    }
}
