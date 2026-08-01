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

            VStack(spacing: SidebarRowLayout.rowGap) {
                SpaceSnapshotTitleView(
                    title: snapshot.title,
                    iconValue: snapshot.iconValue,
                    hasPinnedContent: snapshot.hasPinnedContent,
                    isPinnedContentCollapsed: snapshot.isPinnedContentCollapsed,
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
        VStack(spacing: 0) {
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
    let hasPinnedContent: Bool
    let isPinnedContentCollapsed: Bool
    let rowCornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    var body: some View {
        SpaceTitleRowChrome(
            backgroundColor: .clear,
            cornerRadius: rowCornerRadius
        ) {
            SpaceTitleLeadingGlyphContent(
                iconValue: iconValue,
                displaysChevron: hasPinnedContent && isPinnedContentCollapsed,
                rotationDegrees: SpaceTitleChevronRotationPlan.resolve(
                    isExpanded: !isPinnedContentCollapsed
                ).destinationDegrees,
                textColor: tokens.primaryText,
                visibilityAnimation: nil
            )
        } title: {
            SpaceTitleTextLabel(
                title: title,
                textColor: tokens.primaryText
            )
        } trailing: {
            Color.clear
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("space-transition-snapshot-title")
    }
}

@MainActor
struct EssentialsSnapshotGrid: View {
    let snapshot: EssentialsSnapshot
    let width: CGFloat
    let tokens: ChromeThemeTokens

    @Environment(\.sumiSettings) private var sumiSettings

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
        SidebarEssentialsProjectionPolicy.resolvedCapacityColumnCount(for: width)
    }

    var body: some View {
        Group {
            if snapshot.items.isEmpty {
                emptyState
            } else {
                tileRows
            }
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private var emptyState: some View {
        if snapshot.showsPlaceholder {
            EssentialsPlaceholderView(
                tokens: tokens,
                cornerRadius: sumiSettings.resolvedCornerRadius(PinnedTileMetrics.cornerRadius),
                onDismiss: nil
            )
        } else {
            Color.clear
                .frame(height: PinnedTileMetrics.collapsedEssentialsRevealHeight)
        }
    }

    private var tileRows: some View {
        VStack(alignment: .leading, spacing: PinnedTileMetrics.gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: PinnedTileMetrics.gridSpacing) {
                    ForEach(row.items) { item in
                        switch item {
                        case .shortcut(let shortcut):
                            SpaceSnapshotPinnedTileView(
                                item: shortcut,
                                tileSize: row.tileSize,
                                tokens: tokens
                            )
                        case .splitGroup(let splitGroup):
                            EssentialsSnapshotSplitTileView(
                                splitGroup: splitGroup,
                                tileSize: row.tileSize,
                                tokens: tokens
                            )
                        }
                    }
                }
            }
        }
    }

    private func visualTileSize(visualColumnCount: Int) -> CGSize {
        SidebarEssentialsProjectionPolicy.visualTileSize(
            width: width,
            visualColumnCount: visualColumnCount
        )
    }

    private struct EssentialsSnapshotRow {
        let items: [EssentialsSnapshotItem]
        let tileSize: CGSize
    }
}

private struct EssentialsSnapshotSplitTileView: View {
    let splitGroup: SpaceSplitGroupSnapshot
    let tileSize: CGSize
    let tokens: ChromeThemeTokens

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore

    var body: some View {
        EssentialSplitCompactVisual(
            members: splitGroup.members.map { member in
                EssentialSplitTileMemberPresentation(
                    icon: fallbackImage(for: member.icon),
                    glyphText: member.icon.accentGlyphText,
                    systemImageName: member.icon.accentSystemImageName,
                    accentColor: accentColor(for: member),
                    title: member.title,
                    backdrop: member.essentialBackdrop
                )
            },
            isGroupActive: splitGroup.isSelected,
            cornerRadius: sumiSettings.resolvedCornerRadius(
                PinnedTileMetrics.cornerRadius
            ),
            idleBackground: tokens.pinnedIdleBackground,
            activeBackground: tokens.pinnedActiveBackground,
            desaturatesIcons: !splitGroup.isLoaded
        )
        .frame(width: tileSize.width, height: tileSize.height)
        .sidebarZenPressEffectRestingGeometry()
        .task(id: memberIconLoadKey) {
            for member in splitGroup.members {
                await member.icon.load(using: faviconImageStore)
            }
        }
        .accessibilityIdentifier(
            "essential-split-group-snapshot-\(splitGroup.id.uuidString)"
        )
    }

    private func fallbackImage(for icon: SpaceSidebarSnapshotIcon) -> Image {
        if case .image(let image) = icon.resolved(using: faviconImageStore) {
            return image
        }
        return Image(systemName: "globe")
    }

    private var memberIconLoadKey: String {
        splitGroup.members.map {
            $0.icon.loadKey(using: faviconImageStore)
        }.joined(separator: "|")
    }

    private func accentColor(
        for member: SpaceSplitGroupMemberSnapshot
    ) -> Color {
        guard let source = member.accentSource else { return .accentColor }
        return PinnedTileAccentResolver.resolve(
            launchURL: source.launchURL,
            partition: source.partition,
            glyphText: member.icon.accentGlyphText,
            chromeTemplateSystemImageName: member.icon.accentSystemImageName,
            tokens: tokens
        )
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
                // Match live's idle `emptyRevealStrip` (0px) so the New-Tab button
                // does not sit lower in the snapshot than in the live view.
                Color.clear
                    .frame(height: 0)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: SidebarRowLayout.rowGap) {
                    ForEach(items) { item in
                        SpaceSnapshotPinnedItemView(
                            item: item,
                            rowCornerRadius: rowCornerRadius,
                            tokens: tokens,
                            themeContext: themeContext
                        )
                    }
                }
                .padding(.top, SidebarInsertionGuide.visualCenterY)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SpaceSnapshotPinnedItemView: View {
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
        case .splitGroup(let splitGroup):
            SpaceSnapshotSplitGroupView(
                splitGroup: splitGroup,
                rowCornerRadius: rowCornerRadius,
                tokens: tokens
            )
        }
    }
}
