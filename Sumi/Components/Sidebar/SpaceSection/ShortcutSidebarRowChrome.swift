//
//  ShortcutSidebarRowChrome.swift
//  Sumi
//

import SwiftUI
import SumiDomain

struct ShortcutSidebarRowChrome: View {
    let pin: ShortcutPin
    let liveTab: Tab?
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let resolvedTitle: String
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @Environment(BrowserWindowState.self) var windowState
    @EnvironmentObject var glanceManager: GlanceManager
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.chromeThemeTokens) var scopedChromeTokens
    @State var isRowHovered = false
    @State var isActionHovered = false
    @State var isGlanceCloseHovered = false
    @State var isResetHovered = false
    @State var suppressRegularActionUntilHoverExit = false
    @StateObject var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        HStack(spacing: 0) {
            if runtimeAffordance.usesResetLeadingAction, let onResetToLaunchURL {
                Button(action: onResetToLaunchURL) {
                    resetLeadingButtonContent
                }
                .buttonStyle(
                    SidebarZenActionButtonStyle(
                        isEnabled: dragIsEnabled && !freezesHoverState
                    )
                )
                .sidebarDDGHover($isResetHovered, isEnabled: dragIsEnabled)
                .accessibilityIdentifier(resetActionAccessibilityID ?? "shortcut-sidebar-reset")
                .accessibilityLabel("Back to pinned URL")
                .help("Back to pinned URL")
                .sidebarAppKitPrimaryAction(
                    isInteractionEnabled: dragIsEnabled,
                    action: onResetToLaunchURL
                )
            }

            ZStack {
                HStack(spacing: 0) {
                    if !runtimeAffordance.usesResetLeadingAction {
                        rowIcon
                            .padding(.leading, SidebarRowLayout.leadingInset)
                            .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    }

                    if let liveTab {
                        LauncherAudioButton(
                            tab: liveTab,
                            foregroundColor: textColor,
                            mutedForegroundColor: tokens.secondaryText,
                            hoverBackground: actionBackground,
                            accessibilityID: launcherAudioAccessibilityID,
                            isAppKitInteractionEnabled: dragIsEnabled
                        )
                        .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    }

                    titleStack
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, runtimeAffordance.usesResetLeadingAction ? SidebarRowLayout.changedLauncherTitleLeading : 0)
                .padding(.trailing, SidebarRowLayout.trailingInset)
                .frame(height: SidebarRowLayout.rowHeight)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            rowActivationOverlay
        }
        .overlay(alignment: .trailing) {
            trailingActionButton
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .sidebarRowSurface(
            background: backgroundColor,
            cornerRadius: rowCornerRadius,
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: runtimeAffordance.isSelected
        )
        // Expose the row container itself so the launcher keeps the same source identity
        // when runtime drift replaces the leading favicon with the reset control.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID ?? "shortcut-sidebar-row")
        .accessibilityValue(runtimeAffordance.isSelected ? "selected" : "not selected")
        .sidebarDDGHover($isRowHovered, isEnabled: dragIsEnabled)
        .onChange(of: isRowHovered) { _, hovering in
            if !hovering {
                suppressRegularActionUntilHoverExit = false
            }
        }
        .onChange(of: activeGlanceSessionForRow?.id) { oldValue, newValue in
            if oldValue != nil, newValue == nil, isRowHovered {
                suppressRegularActionUntilHoverExit = true
            } else if newValue != nil {
                suppressRegularActionUntilHoverExit = false
            }
        }
        .sidebarZenPressEffect(sourceID: rowSourceID, isEnabled: dragIsEnabled)
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            guard pin.iconAsset == nil else { return }
            storedFaviconLoader.invalidateIfNeeded(for: notification, launchURL: pin.launchURL)
        }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: dragIsEnabled,
            dragSource: dragSourceConfiguration,
            primaryAction: action,
            onMiddleClick: onUnload,
            sourceID: rowSourceID,
            entries: contextMenuEntries
        )
    }

}
