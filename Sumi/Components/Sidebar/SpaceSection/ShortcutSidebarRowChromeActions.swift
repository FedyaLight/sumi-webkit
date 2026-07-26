//
//  ShortcutSidebarRowChromeActions.swift
//  Sumi
//

import SumiDomain
import SwiftUI

extension ShortcutSidebarRowChrome {
    @ViewBuilder
    var trailingActionButton: some View {
        if let glanceSession = activeGlanceSessionForRow {
            SidebarGlanceTrailingAccessory(
                session: glanceSession,
                sourceID: pin.id.uuidString,
                accessibilityPrefix: "shortcut-sidebar-glance",
                showsCloseButton: showsGlanceCloseButton,
                isCloseHovered: $isGlanceCloseHovered,
                textColor: textColor,
                closeBackground: actionBackground,
                isEnabled: !freezesHoverState,
                isInteractionEnabled: dragIsEnabled
            )
        } else {
            Button(action: performActionButton) {
                Image(systemName: actionIconName)
                    .font(SidebarThemeTokens.Typography.trailingAction)
                    .foregroundColor(textColor)
                    .frame(
                        width: SidebarRowLayout.trailingActionSize,
                        height: SidebarRowLayout.trailingActionSize
                    )
                    .background(displayIsActionHovering ? actionBackground : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(
                SidebarZenActionButtonStyle(
                    isEnabled: showsActionButton && !freezesHoverState
                )
            )
            .opacity(showsActionButton ? 1 : 0)
            .allowsHitTesting(showsActionButton && !freezesHoverState)
            .accessibilityHidden(!showsActionButton)
            .sidebarHover(
                $isActionHovered,
                isEnabled: showsActionButton && dragIsEnabled
            )
            .accessibilityIdentifier(trailingActionAccessibilityID ?? "shortcut-sidebar-action")
            .sidebarAppKitPrimaryAction(
                isEnabled: showsActionButton && !freezesHoverState,
                isInteractionEnabled: dragIsEnabled,
                action: performActionButton
            )
        }
    }

    var backgroundColor: Color {
        guard projectedSplitTarget == nil else { return .clear }
        if runtimeAffordance.isSelected {
            return tokens.sidebarRowActive
        } else if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    var drawsRowSurface: Bool {
        projectedSplitTarget == nil
            && (runtimeAffordance.isSelected || displayIsHovering)
    }

    var rowSourceID: String {
        accessibilityID ?? "shortcut-sidebar-row"
    }

    var actionBackground: Color {
        runtimeAffordance.isSelected
            ? tokens.fieldBackgroundHover
            : tokens.fieldBackground
    }

    var actionIconName: String {
        runtimeAffordance.isOpenLive ? "minus" : "xmark"
    }

    var trailingActionAccessibilityID: String? {
        actionAccessibilityID(suffix: "action")
    }

    var resetActionAccessibilityID: String? {
        actionAccessibilityID(suffix: "reset")
    }

    var launcherAudioAccessibilityID: String? {
        actionAccessibilityID(suffix: "audio")
    }

    var showsActionButton: Bool {
        activeGlanceSessionForRow == nil
            && !suppressRegularActionUntilHoverExit
            && displayIsHovering
    }

    var activeGlanceSessionForRow: GlanceSession? {
        guard let liveTab,
              let session = glanceManager.sidebarSession(for: windowState),
              session.sourceTab?.id == liveTab.id
        else { return nil }
        return session
    }

    var showsGlanceCloseButton: Bool {
        activeGlanceSessionForRow != nil && displayIsHovering
    }

    var reservedTrailingWidth: CGFloat {
        if activeGlanceSessionForRow != nil {
            return SidebarRowLayout.trailingActionSize
                + (showsGlanceCloseButton ? SidebarRowLayout.trailingActionSize + SidebarRowLayout.trailingActionGap : 0)
        }
        return showsActionButton ? SidebarRowLayout.trailingActionPadding : 0
    }

    var trailingActivationExclusionWidth: CGFloat {
        if activeGlanceSessionForRow != nil {
            return SidebarRowLayout.trailingActionSize
                + SidebarRowLayout.trailingInset
                + (showsGlanceCloseButton ? SidebarRowLayout.trailingActionSize + SidebarRowLayout.trailingActionGap : 0)
        }
        return dragHasTrailingActionExclusion ? 40 : 0
    }

    var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    var displayIsHovering: Bool {
        isRowHovered
    }

    var displayIsActionHovering: Bool {
        isActionHovered
    }

    var displayIsResetHovering: Bool {
        isResetHovered
    }

    var currentLoadedStoredFavicon: Image? {
        storedFaviconLoader.image(
            for: pin.launchURL,
            partition: faviconPartition
        )
    }

    var storedFaviconLoadKey: String {
        storedFaviconLoader.loadKey(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            isEnabled: pin.iconAsset == nil,
            disabledID: pin.id.uuidString
        )
    }

    @MainActor
    func loadStoredFavicon() async {
        guard pin.iconAsset == nil else { return }

        await storedFaviconLoader.load(
            launchURL: pin.launchURL,
            partition: faviconPartition,
            imageReader: faviconImageReader,
            isCurrentLaunchURL: { pin.launchURL == $0 }
        )
    }

    var dragSourceConfiguration: SidebarDragSourceConfiguration? {
        makeShortcutSidebarDragSourceConfiguration(
            pin: pin,
            resolvedTitle: resolvedTitle,
            runtimeAffordance: runtimeAffordance,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            hasLiveAudioExclusion: liveTab?.audioState.showsTabAudioButton == true,
            trailingActionExclusionWidth: trailingActivationExclusionWidth,
            previewIcon: displayFavicon,
            dragIsEnabled: dragIsEnabled
        )
    }

    var primaryActionExclusionZones: [SidebarDragSourceExclusionZone] {
        makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: runtimeAffordance,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            hasLiveAudioExclusion: liveTab?.audioState.showsTabAudioButton == true,
            trailingActionExclusionWidth: trailingActivationExclusionWidth
        )
    }

    var textColor: Color {
        tokens.primaryText
    }

    func performActionButton() {
        if runtimeAffordance.isOpenLive {
            onUnload()
            return
        }
        onRemove()
    }

    var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    func actionAccessibilityID(suffix: String) -> String? {
        guard let accessibilityID else { return nil }
        if let id = accessibilityID.replacingPrefix("space-pinned-shortcut-", with: "space-pinned-shortcut-\(suffix)-") {
            return id
        }
        if let id = accessibilityID.replacingPrefix("folder-shortcut-", with: "folder-shortcut-\(suffix)-") {
            return id
        }
        return "\(accessibilityID)-\(suffix)"
    }
}
