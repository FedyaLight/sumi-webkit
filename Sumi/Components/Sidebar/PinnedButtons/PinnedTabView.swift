//
//  PinnedButtonView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct PinnedTabView: View {
    private enum TileBackgroundState {
        case active
        case hover
        case idle
    }

    var tabIcon: SwiftUI.Image
    var glyphText: String?
    /// Draw with `ChromeThemeTokens.primaryText` + monochrome (new-tab globe, settings gear, uncached globe fallback).
    var chromeTemplateSystemImageName: String?
    var presentationState: ShortcutPresentationState
    var liveTab: Tab?
    var dragSourceConfiguration: SidebarDragSourceConfiguration?
    var accessibilityID: String?
    var isAppKitInteractionEnabled: Bool = true
    var showsUnloadIndicator: Bool = false
    var showsSplitGroupOutline: Bool = false
    var supportsMiddleClickUnload: Bool = false
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    var action: () -> Void
    var onUnload: () -> Void
    var accentSourceURL: URL?
    var accentSourcePartition: SumiFaviconPartition?
    var faviconImageReader: (any BrowserFaviconImageReading)?
    var favoriteBackdropReader: (any BrowserFavoriteBackdropReading)?

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var isTileHovered = false
    @State private var isActionHovered = false
    @State private var backdropLoader = SidebarFavoriteBackdropLoader()

    var body: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(PinnedTileMetrics.cornerRadius)
        return ZStack {
            PinnedTileVisual(
                tabIcon: tabIcon,
                glyphText: glyphText,
                chromeTemplateSystemImageName: chromeTemplateSystemImageName,
                presentationState: presentationState,
                isHovered: displayIsHovered,
                showsSplitGroupOutline: showsSplitGroupOutline,
                accentSourceURL: accentSourceURL ?? liveTab?.url,
                accentSourcePartition: accentSourcePartition,
                faviconImageReader: faviconImageReader,
                selectionBackdrop: selectionBackdrop
            )

            if supportsActionButton {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onUnload) {
                            Image(systemName: "minus")
                                .font(SidebarThemeTokens.Typography.pinnedTileAction)
                                .foregroundStyle(tokens.primaryText)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(backgroundColor.opacity(displayIsActionHovering ? 1 : 0.92))
                                )
                        }
                        .buttonStyle(
                            SidebarZenActionButtonStyle(
                                isEnabled: shouldShowActionButton && !freezesHoverState
                            )
                        )
                        .opacity(shouldShowActionButton ? 1 : 0)
                        .allowsHitTesting(shouldShowActionButton && !freezesHoverState)
                        .accessibilityHidden(!shouldShowActionButton)
                        .accessibilityIdentifier(actionAccessibilityID ?? "pinned-tile-action")
                        .sidebarHover(
                            $isActionHovered,
                            isEnabled: shouldShowActionButton && isAppKitInteractionEnabled
                        )
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
        .frame(height: PinnedTileMetrics.height)
        .frame(minWidth: PinnedTileMetrics.minWidth)
        // Flatten the drawn tile before the selection shadow below: an
        // unflattened `shadow` is inherited by every drawn element, so the
        // favicon would cast its own shadow onto the translucent selection
        // plate instead of only the tile lifting off the sidebar.
        .compositingGroup()
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityIdentifier(accessibilityID ?? "pinned-tile")
        .accessibilityValue(presentationState.isSelected ? "selected" : "not selected")
        .accessibilityAction(.default, action)
        .sidebarHover($isTileHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: tileSourceID)
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            dragSource: dragSourceConfiguration,
            primaryActionExclusionZones: primaryActionExclusionZones,
            pageActivation: action,
            onMiddleClick: supportsMiddleClickUnload ? onUnload : nil,
            sourceID: tileSourceID,
            entries: contextMenuEntries
        )
        .shadow(
            color: presentationState.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: presentationState.isSelected ? 2 : 0,
            y: presentationState.isSelected ? 1 : 0
        )
        .task(id: selectionBackdropLoadKey) {
            await loadSelectionBackdropIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .favoriteBackdropUpdated)
        ) { notification in
            guard let accentSourceURL, let accentSourcePartition else { return }
            backdropLoader.invalidateIfNeeded(
                for: notification,
                launchURL: accentSourceURL,
                partition: accentSourcePartition
            )
        }
    }

    // MARK: - Colors
    private var backgroundColor: Color {
        let state = backgroundState
        switch state {
        case .active:
            return tokens.pinnedActiveBackground
        case .hover:
            return tokens.pinnedHoverBackground
        case .idle:
            return tokens.pinnedIdleBackground
        }
    }

    private var tileSourceID: String {
        accessibilityID ?? "pinned-tile"
    }

    private var backgroundState: TileBackgroundState {
        switch SidebarHoverChrome.visualState(
            isSelected: presentationState.isSelected,
            isHovered: displayIsHovered
        ) {
        case .selected:
            return .active
        case .hovered:
            return .hover
        case .idle:
            return .idle
        }
    }
    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var shouldShowActionButton: Bool {
        supportsActionButton && (displayIsHovered || presentationState.isSelected)
    }

    private var supportsActionButton: Bool {
        showsUnloadIndicator && presentationState.isOpenLive
    }

    private var primaryActionExclusionZones: [SidebarDragSourceExclusionZone] {
        var zones: [SidebarDragSourceExclusionZone] = []
        if supportsActionButton {
            zones.append(.topTrailingSquare(size: 22, inset: 6))
        }
        if liveTab?.audioState.showsTabAudioButton == true {
            zones.append(.topLeadingSquare(size: 22, inset: 6))
        }
        return zones
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovered: Bool {
        isTileHovered
    }

    private var displayIsActionHovering: Bool {
        isActionHovered
    }

    private var actionAccessibilityID: String? {
        accessibilityActionID(suffix: "action")
    }

    private var audioAccessibilityID: String? {
        accessibilityActionID(suffix: "audio")
    }

    private func accessibilityActionID(suffix: String) -> String? {
        guard let accessibilityID else { return nil }
        if let id = accessibilityID.replacingPrefix("favorite-shortcut-", with: "favorite-shortcut-\(suffix)-") {
            return id
        }
        if let id = accessibilityID.replacingPrefix("space-pinned-shortcut-", with: "space-pinned-shortcut-\(suffix)-") {
            return id
        }
        return "\(accessibilityID)-\(suffix)"
    }

    private var selectionBackdrop: Image? {
        guard presentationState.isSelected,
              glyphText == nil,
              chromeTemplateSystemImageName == nil,
              let accentSourceURL,
              let accentSourcePartition,
              let favoriteBackdropReader
        else { return nil }
        return backdropLoader.image(
            for: accentSourceURL,
            partition: accentSourcePartition
        ) ?? favoriteBackdropReader.cachedBackdrop(
            for: accentSourceURL,
            partition: accentSourcePartition
        ).map(Image.init(nsImage:))
    }

    private var selectionBackdropLoadKey: String {
        guard let accentSourceURL, let accentSourcePartition else {
            return "no-backdrop-source"
        }
        return backdropLoader.loadKey(
            launchURL: accentSourceURL,
            partition: accentSourcePartition,
            isEnabled: presentationState.isSelected
                && glyphText == nil
                && chromeTemplateSystemImageName == nil
                && favoriteBackdropReader != nil
        )
    }

    private func loadSelectionBackdropIfNeeded() async {
        guard presentationState.isSelected,
              glyphText == nil,
              chromeTemplateSystemImageName == nil,
              let accentSourceURL,
              let accentSourcePartition,
              let favoriteBackdropReader
        else { return }
        await backdropLoader.load(
            launchURL: accentSourceURL,
            partition: accentSourcePartition,
            reader: favoriteBackdropReader,
            isCurrentLaunchURL: { accentSourceURL == $0 }
        )
    }
}

struct FavoriteBackdropSelectionChrome: View {
    let image: Image
    let cornerRadius: CGFloat
    let plateColor: Color
    let isHovered: Bool
    var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .overlay {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .opacity(opacity)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: max(0, cornerRadius - 2),
                    style: .continuous
                )
                .fill(plateColor.opacity(isHovered ? 0.94 : 1))
                .padding(2)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

/// Accent stroke drawn inside a selected pinned/favorite tile. Shared by the
/// live `PinnedTileVisual` and the transition-snapshot tile so both keep an
/// identical selection ring. Fills the available frame (no `GeometryReader`
/// needed — a `Shape` already sizes to its container).
struct PinnedTileSelectionRing: View {
    let corner: CGFloat
    let thickness: CGFloat
    var color: Color

    var body: some View {
        let strokeInset = thickness / 2
        RoundedRectangle(
            cornerRadius: max(0, corner - strokeInset),
            style: .continuous
        )
        .inset(by: strokeInset)
        .stroke(color, lineWidth: thickness)
    }
}

struct PinnedTileSplitGroupOutlineMask: View {
    let corner: CGFloat
    let thickness: CGFloat
    var strokeColor: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dash = max(3.8, size.height * 0.1)
            let gap = max(3.4, size.height * 0.085)
            let strokeStyle = StrokeStyle(
                lineWidth: thickness,
                lineCap: .round,
                lineJoin: .round,
                dash: [dash, gap]
            )
            let verticalTop = max(size.height * 0.24, thickness * 4)
            let verticalBottom = min(size.height * 0.76, size.height - thickness * 4)

            ZStack {
                RoundedRectangle(cornerRadius: max(0, corner - thickness), style: .continuous)
                    .inset(by: thickness)
                    .stroke(strokeColor, style: strokeStyle)

                verticalRule(
                    x: size.width * 0.3,
                    top: verticalTop,
                    bottom: verticalBottom,
                    style: strokeStyle
                )

                verticalRule(
                    x: size.width * 0.7,
                    top: verticalTop,
                    bottom: verticalBottom,
                    style: strokeStyle
                )
            }
        }
    }

    private func verticalRule(
        x: CGFloat,
        top: CGFloat,
        bottom: CGFloat,
        style: StrokeStyle
    ) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
        }
        .stroke(strokeColor, style: style)
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
    @State private var isHovering = false

    var body: some View {
        Group {
            if tab.audioState.showsTabAudioButton {
                Button {
                    tab.toggleMute()
                } label: {
                    Image(systemName: tab.audioState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(SidebarThemeTokens.Typography.pinnedTileAction)
                        .foregroundStyle(tab.audioState.isMuted ? mutedForegroundColor : foregroundColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(backgroundColor.opacity(displayIsHovering ? 1 : 0.86))
                        )
                        .id(tab.audioState.isMuted)
                }
                .buttonStyle(
                    SidebarZenActionButtonStyle(
                        isEnabled: isAppKitInteractionEnabled
                            && !windowState.sidebarInteractionState.freezesSidebarHoverState
                    )
                )
                .sidebarHover(
                    $isHovering,
                    isEnabled: isAppKitInteractionEnabled
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
        isHovering
    }
}
