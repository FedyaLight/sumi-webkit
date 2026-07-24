//
//  ShortcutSidebarRowChromePresentation.swift
//  Sumi
//

import SwiftUI
import SumiDomain

extension ShortcutSidebarRowChrome {
    var rowIcon: some View {
        Group {
            if let launcherIconAsset = pin.iconAsset {
                launcherGlyph(for: launcherIconAsset)
            } else if let systemName = chromeTemplateSystemImageName {
                Image(systemName: systemName)
                    .font(SidebarThemeTokens.Typography.chromeTemplateIcon(size: SidebarRowLayout.faviconSize))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(textColor)
            } else {
                displayFavicon
            }
        }
        .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
        .saturation(runtimeAffordance.shouldDesaturateIcon ? 0.0 : 1.0)
        .opacity(runtimeAffordance.shouldDesaturateIcon ? 0.8 : 1.0)
    }

    var iconPresentation: SidebarShortcutIconPresentation {
        SidebarShortcutIconResolver.resolve(
            pin: pin,
            liveTab: liveTab,
            loadedStoredFavicon: currentLoadedStoredFavicon,
            partition: faviconPartition,
            imageReader: faviconImageReader
        )
    }

    var displayFavicon: Image {
        iconPresentation.image
            ?? Image(systemName: SumiPersistentGlyph.launcherSystemImageFallback)
    }

    var chromeTemplateSystemImageName: String? {
        iconPresentation.systemImageName
    }

    @ViewBuilder
    func launcherGlyph(for iconAsset: String) -> some View {
        if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
            Text(iconAsset)
                .font(SidebarThemeTokens.Typography.launcherEmoji(size: SidebarRowLayout.faviconSize))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .multilineTextAlignment(.center)
                .frame(
                    width: SidebarRowLayout.faviconSize,
                    height: SidebarRowLayout.faviconSize,
                    alignment: .center
                )
        } else {
            Image(systemName: SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
                .font(SidebarThemeTokens.Typography.chromeTemplateIcon(size: SidebarRowLayout.faviconSize))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(textColor)
        }
    }

    var resetLeadingButtonContent: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                rowIcon
                    .padding(.leading, SidebarRowLayout.changedLauncherResetIconLeading)
                Spacer(minLength: 0)
            }
            .frame(
                width: SidebarRowLayout.changedLauncherResetWidth,
                height: SidebarRowLayout.changedLauncherResetHeight,
                alignment: .leading
            )
            .background(displayIsResetHovering ? actionBackground : Color.clear)
            .clipShape(SidebarRowLayout.leadingActionShape(cornerRadius: rowCornerRadius))

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tokens.secondaryText.opacity(displayIsResetHovering ? 0 : 0.3))
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

    var rowCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(SidebarRowLayout.defaultCornerRadius)
    }

    @ViewBuilder
    var titleStack: some View {
        titleLabel
            .frame(height: SidebarRowLayout.titleHeight, alignment: .center)
    }

    @ViewBuilder
    var titleLabel: some View {
        SumiTabTitleLabel(
            title: resolvedTitle,
            font: SidebarThemeTokens.Typography.rowTitle,
            textColor: textColor,
            reservedTrailingWidth: reservedTrailingWidth,
            animated: liveTab != nil
        )
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}
