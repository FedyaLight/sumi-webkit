//
//  PinnedButtonView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct PinnedTabView: View {
    private enum TileBackgroundState {
        case active
        case hover
        case idle
    }

    var tabIcon: SwiftUI.Image
    /// Draw with `ChromeThemeTokens.primaryText` + monochrome (new-tab globe, settings gear, uncached globe fallback).
    var chromeTemplateSystemImageName: String? = nil
    var presentationState: ShortcutPresentationState
    var liveTab: Tab? = nil
    var dragSourceConfiguration: SidebarDragSourceConfiguration? = nil
    var accessibilityID: String? = nil
    var isAppKitInteractionEnabled: Bool = true
    var showsUnloadIndicator: Bool = false
    var supportsMiddleClickUnload: Bool = false
    var contextMenuEntries: [SidebarContextMenuEntry] = []
    var action: () -> Void
    var onUnload: () -> Void

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        let pinnedTabsConfiguration: PinnedTabsConfiguration = sumiSettings.pinnedTabsLook
        let cornerRadius = sumiSettings.resolvedCornerRadius(pinnedTabsConfiguration.cornerRadius)
        ZStack {
            PinnedTileVisual(
                tabIcon: tabIcon,
                chromeTemplateSystemImageName: chromeTemplateSystemImageName,
                presentationState: presentationState,
                isHovered: displayIsHovered,
                configuration: pinnedTabsConfiguration
            )

            if supportsActionButton {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onUnload) {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(tokens.primaryText)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(backgroundColor.opacity(0.92))
                                )
                        }
                        .buttonStyle(.plain)
                        .opacity(shouldShowActionButton ? 1 : 0)
                        .allowsHitTesting(shouldShowActionButton && !freezesHoverState)
                        .accessibilityHidden(!shouldShowActionButton)
                        .accessibilityIdentifier(actionAccessibilityID ?? "pinned-tile-action")
                        .sidebarAppKitPrimaryAction(
                            isEnabled: shouldShowActionButton && !freezesHoverState,
                            isInteractionEnabled: isAppKitInteractionEnabled,
                            action: onUnload
                        )
                    }
                    Spacer()
                }
                .padding(6)
            }

            if let liveTab {
                VStack {
                    HStack {
                        PinnedTileAudioButton(
                            tab: liveTab,
                            foregroundColor: tokens.primaryText,
                            mutedForegroundColor: tokens.secondaryText,
                            backgroundColor: backgroundColor.opacity(0.92),
                            accessibilityID: audioAccessibilityID,
                            isAppKitInteractionEnabled: isAppKitInteractionEnabled
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: pinnedTabsConfiguration.height)
        .frame(minWidth: pinnedTabsConfiguration.minWidth)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityIdentifier(accessibilityID ?? "pinned-tile")
        .accessibilityValue(presentationState.isSelected ? "selected" : "not selected")
        .sidebarHoverTarget(
            tileHoverTarget,
            isEnabled: isAppKitInteractionEnabled,
            animation: .easeInOut(duration: 0.12)
        )
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            dragSource: dragSourceConfiguration,
            primaryAction: action,
            onMiddleClick: supportsMiddleClickUnload ? onUnload : nil,
            sourceID: accessibilityID ?? "pinned-tile",
            entries: { contextMenuEntries }
        )
        .shadow(
            color: presentationState.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: presentationState.isSelected ? 2 : 0,
            y: presentationState.isSelected ? 1 : 0
        )
    }
    
    //MARK: - Colors
    private var backgroundColor: Color {
        let state: TileBackgroundState
        if presentationState.isSelected {
            state = .active
        } else if displayIsHovered {
            state = .hover
        } else {
            state = .idle
        }
        switch state {
        case .active:
            return tokens.pinnedActiveBackground
        case .hover:
            return tokens.pinnedHoverBackground
        case .idle:
            return tokens.pinnedIdleBackground
        }
    }
    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var shouldShowActionButton: Bool {
        supportsActionButton && (displayIsHovered || presentationState.isSelected)
    }

    private var supportsActionButton: Bool {
        showsUnloadIndicator && presentationState.isOpenLive
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovered: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(tileHoverTarget)
            && !freezesHoverState
    }

    private var tileHoverTarget: SidebarHoverTarget {
        let fallbackID = dragSourceConfiguration?.item.tabId.uuidString ?? "pinned-tile"
        return .row(accessibilityID ?? "pinned-tile-\(fallbackID)")
    }

    private var actionAccessibilityID: String? {
        accessibilityActionID(suffix: "action")
    }

    private var audioAccessibilityID: String? {
        accessibilityActionID(suffix: "audio")
    }

    private func accessibilityActionID(suffix: String) -> String? {
        guard let accessibilityID else { return nil }
        if let id = accessibilityID.replacingPrefix("essential-shortcut-", with: "essential-shortcut-\(suffix)-") {
            return id
        }
        if let id = accessibilityID.replacingPrefix("space-pinned-shortcut-", with: "space-pinned-shortcut-\(suffix)-") {
            return id
        }
        return "\(accessibilityID)-\(suffix)"
    }
}

struct PinnedTileVisual: View {
    private enum TileBackgroundState {
        case active
        case hover
        case idle
    }

    var tabIcon: SwiftUI.Image
    var chromeTemplateSystemImageName: String? = nil
    var presentationState: ShortcutPresentationState
    var isHovered: Bool = false
    var configuration: PinnedTabsConfiguration? = nil

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private let faviconScale: CGFloat = 6.0
    private let faviconBlur: CGFloat = 30.0

    var body: some View {
        let pinnedTabsConfiguration = configuration ?? sumiSettings.pinnedTabsLook
        let cornerRadius = sumiSettings.resolvedCornerRadius(pinnedTabsConfiguration.cornerRadius)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    if presentationState.isSelected {
                        resolvedFaviconSymbol(height: pinnedTabsConfiguration.faviconHeight)
                            .blur(radius: 30)
                            .opacity(0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    resolvedFaviconSymbol(height: pinnedTabsConfiguration.faviconHeight)
                        .saturation(presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
                        .opacity(presentationState.shouldDesaturateIcon ? 0.8 : 1.0)
                    Spacer()
                }
                Spacer()
            }

            if presentationState.isSelected {
                faviconStrokeOverlay(
                    corner: cornerRadius,
                    thickness: pinnedTabsConfiguration.strokeWidth,
                    scale: faviconScale,
                    blur: faviconBlur
                )
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: pinnedTabsConfiguration.height)
        .frame(minWidth: pinnedTabsConfiguration.minWidth)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var backgroundColor: Color {
        let state: TileBackgroundState
        if presentationState.isSelected {
            state = .active
        } else if isHovered {
            state = .hover
        } else {
            state = .idle
        }
        switch state {
        case .active:
            return tokens.pinnedActiveBackground
        case .hover:
            return tokens.pinnedHoverBackground
        case .idle:
            return tokens.pinnedIdleBackground
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    @ViewBuilder
    private func resolvedFaviconSymbol(height: CGFloat) -> some View {
        if let systemName = chromeTemplateSystemImageName {
            Image(systemName: systemName)
                .font(.system(size: height * 0.78, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tokens.primaryText)
                .frame(height: height)
        } else {
            tabIcon
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(height: height)
        }
    }

    @ViewBuilder
    private func strokeFaviconSource(
        size: CGSize,
        scale: CGFloat,
        blur: CGFloat,
        ringMask: some View
    ) -> some View {
        let dim = min(size.width, size.height) * scale
        Group {
            if let systemName = chromeTemplateSystemImageName {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: dim, height: dim)
            } else {
                tabIcon
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: dim, height: dim)
            }
        }
        .blur(radius: blur)
        .frame(width: size.width, height: size.height)
        .mask(ringMask.frame(width: size.width, height: size.height))
    }

    private func faviconStrokeOverlay(
        corner: CGFloat,
        thickness: CGFloat,
        scale: CGFloat,
        blur: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let outerRect = RoundedRectangle(cornerRadius: corner - thickness, style: .continuous)
            let innerRect = RoundedRectangle(cornerRadius: max(0, corner - thickness), style: .continuous)

            ZStack {
                let ringMask = ZStack {
                    outerRect
                        .fill(Color.white)
                        .shadow(color: .clear, radius: 0)

                    innerRect
                        .inset(by: thickness)
                        .fill(Color.black)
                        .compositingGroup()
                        .blendMode(.destinationOut)
                }

                strokeFaviconSource(
                    size: size,
                    scale: scale,
                    blur: blur,
                    ringMask: ringMask
                )
            }
        }
    }
}

private struct PinnedTileAudioButton: View {
    @ObservedObject var tab: Tab
    let foregroundColor: Color
    let mutedForegroundColor: Color
    let backgroundColor: Color
    let accessibilityID: String?
    let isAppKitInteractionEnabled: Bool
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        Group {
            if tab.audioState.showsTabAudioButton {
                Button {
                    tab.toggleMute()
                } label: {
                    Image(systemName: tab.audioState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tab.audioState.isMuted ? mutedForegroundColor : foregroundColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(backgroundColor.opacity(displayIsHovering ? 1 : 0.86))
                        )
                        .id(tab.audioState.isMuted)
                }
                .buttonStyle(.plain)
                .sidebarHoverTarget(
                    hoverTarget,
                    isEnabled: isAppKitInteractionEnabled,
                    animation: .easeInOut(duration: 0.1)
                )
                .accessibilityIdentifier(accessibilityID ?? "pinned-tile-audio")
                .sidebarAppKitPrimaryAction(
                    isEnabled: !windowState.sidebarInteractionState.freezesSidebarHoverState,
                    isInteractionEnabled: isAppKitInteractionEnabled,
                    action: tab.toggleMute
                )
                .help(tab.audioState.isMuted ? "Unmute Audio" : "Mute Audio")
                .animation(.easeInOut(duration: 0.1), value: tab.audioState.isMuted)
            }
        }
    }

    private var displayIsHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(hoverTarget)
            && !windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var hoverTarget: SidebarHoverTarget {
        .action(accessibilityID ?? "pinned-tile-audio-\(tab.id.uuidString)")
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return replacement + String(dropFirst(prefix.count))
    }
}
