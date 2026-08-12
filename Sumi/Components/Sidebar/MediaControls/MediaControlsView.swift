//
//  MediaControlsView.swift
//  Sumi
//

import AppKit
import Foundation
import SwiftUI

enum SidebarMediaCardPresentationPolicy {
    static func shouldPresentCard(
        hasCardState: Bool,
        presentationContext: SidebarPresentationContext
    ) -> Bool {
        hasCardState && presentationContext.allowsInteractiveWork
    }
}

enum SidebarMediaCardStackMetrics {
    static let collapsedCardHeight: CGFloat = 34
    static let expandedCardHeight: CGFloat = 68
    static let expandedHeaderHeight: CGFloat = 30
    static let expandedHeaderTopInset: CGFloat = 4
    static let expandedMetadataBottomSpacing: CGFloat = 4
    static let headerControlsOffset: CGFloat = -2
    static let stackPeek: CGFloat = 8
    static let stackGap: CGFloat = 6

    static func metadataSlotHeight(isExpanded: Bool) -> CGFloat {
        isExpanded ? expandedHeaderHeight + expandedMetadataBottomSpacing : 0
    }

    static func reservedHeight(cardCount: Int) -> CGFloat {
        guard cardCount > 0 else { return 0 }
        return collapsedCardHeight + CGFloat(cardCount - 1) * stackPeek
    }

    static func expandedHeight(cardCount: Int) -> CGFloat {
        guard cardCount > 0 else { return 0 }
        return expandedCardHeight * CGFloat(cardCount)
            + stackGap * CGFloat(cardCount - 1)
    }

    static func verticalOffset(index: Int, isExpanded: Bool) -> CGFloat {
        -CGFloat(index) * (isExpanded ? expandedCardHeight + stackGap : stackPeek)
    }
}

enum SidebarMediaCardStackMotion {
    static let duration: TimeInterval = 0.25

    static func expansionAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(0.25, 1, 0.5, 1, duration: duration)
    }
}

enum SidebarMediaCardPresenceMotion {
    static let duration: TimeInterval = 0.18
    static let verticalOffset: CGFloat = 6

    static func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(y: verticalOffset))
    }

    static let animation = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: duration
    )
}

private enum SidebarMediaCardHoverLayers {
    static let stack = SidebarHoverLayer(
        priority: 40,
        occludesLowerPriority: true
    )
    static let control = SidebarHoverLayer(priority: 50)
}

struct MediaControlsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.sumiSettings) private var settings

    let cardStates: [SumiBackgroundMediaCardState]
    let controller: SumiNativeNowPlayingController
    private let faviconImageReader: any BrowserFaviconImageReading

    init(
        cardStates: [SumiBackgroundMediaCardState],
        controller: SumiNativeNowPlayingController,
        faviconImageReader: any BrowserFaviconImageReading
    ) {
        self.cardStates = cardStates
        self.controller = controller
        self.faviconImageReader = faviconImageReader
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if SidebarMediaCardPresentationPolicy.shouldPresentCard(
                hasCardState: !cardStates.isEmpty,
                presentationContext: sidebarPresentationContext
            ) {
                SumiBackgroundMediaCardStack(
                    cardStates: cardStates,
                    controller: controller,
                    faviconImageReader: faviconImageReader
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .transition(presenceTransition)
            }
        }
        .animation(
            SidebarMediaCardPresenceMotion.animation,
            value: cardStates.map(\.id)
        )
    }

    private var presenceTransition: AnyTransition {
        SidebarMediaCardPresenceMotion.transition(
            reduceMotion: reduceMotion || settings.shouldReduceChromeMotion
        )
    }
}

private struct SumiBackgroundMediaCardStack: View {
    private static let shieldRoutingPriorityBoost = 39

    let cardStates: [SumiBackgroundMediaCardState]
    let controller: SumiNativeNowPlayingController
    let faviconImageReader: any BrowserFaviconImageReading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var isHovered = false

    private var reservedHeight: CGFloat {
        SidebarMediaCardStackMetrics.reservedHeight(cardCount: cardStates.count)
    }

    private var hoverHeight: CGFloat {
        isHovered
            ? SidebarMediaCardStackMetrics.expandedHeight(cardCount: cardStates.count)
            : reservedHeight
    }

    private var shieldSourceID: String {
        let windowID = cardStates.first?.windowId.uuidString ?? "empty"
        return "sidebar-mini-player-stack-shield-\(windowID)"
    }

    var body: some View {
        Color.clear
            .frame(height: reservedHeight)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    ForEach(Array(cardStates.enumerated()), id: \.element.id) { index, cardState in
                        SumiBackgroundMediaCardView(
                            cardState: cardState,
                            controller: controller,
                            faviconImageReader: faviconImageReader,
                            isExpanded: isHovered
                        )
                        .offset(
                            y: SidebarMediaCardStackMetrics.verticalOffset(
                                index: index,
                                isExpanded: isHovered
                            )
                        )
                        .scaleEffect(
                            isHovered ? 1 : max(0.92, 1 - CGFloat(index) * 0.04),
                            anchor: .top
                        )
                        .opacity(isHovered ? 1 : max(0.4, 1 - Double(index) * 0.3))
                        .transition(presenceTransition)
                        .zIndex(Double(cardStates.count - index))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: hoverHeight, alignment: .bottom)
                .sidebarHover(layer: SidebarMediaCardHoverLayers.stack) { hovering in
                    updateHoverState(hovering)
                }
                .sidebarAppKitPrimaryAction(
                    sourceID: shieldSourceID,
                    routingPriorityBoost: Self.shieldRoutingPriorityBoost,
                    action: {}
                )
            }
            .zIndex(100)
    }

    private var presenceTransition: AnyTransition {
        SidebarMediaCardPresenceMotion.transition(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
    }

    private func updateHoverState(_ hovering: Bool) {
        guard isHovered != hovering else { return }

        let animation = SidebarMediaCardStackMotion.expansionAnimation(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        guard let animation else {
            SidebarMotionTransaction.withoutAnimation {
                isHovered = hovering
            }
            return
        }

        withAnimation(animation) {
            isHovered = hovering
        }
    }
}

private struct SumiBackgroundMediaCardView: View {
    private static let cardSurfaceRoutingPriorityBoost = 40
    private static let controlRoutingPriorityBoost = 50

    let cardState: SumiBackgroundMediaCardState
    let controller: SumiNativeNowPlayingController
    let faviconImageReader: any BrowserFaviconImageReading
    let isExpanded: Bool

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var cardBackground: Color {
        tokens.floatingSurfaceBackground
    }

    private var cardBorder: Color {
        themeContext.nativeSurfaceColorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.clear
    }

    private var cardCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(12)
    }

    private var cardShadow: Color {
        .black.opacity(themeContext.nativeSurfaceColorScheme == .dark ? 0.30 : 0.10)
    }

    private var sourceIDComponent: String {
        "\(cardState.windowId.uuidString)-\(cardState.tabId.uuidString)"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            SumiBackgroundMediaCardMetadataSlot(
                isExpanded: isExpanded,
                title: cardState.title,
                subtitle: cardState.subtitle,
                canPictureInPicture: cardState.canPictureInPicture,
                tokens: tokens,
                sourceIDComponent: sourceIDComponent,
                routingPriorityBoost: Self.controlRoutingPriorityBoost,
                onTogglePictureInPicture: {
                    Task {
                        await controller.togglePictureInPicture(cardID: cardState.id)
                    }
                },
                onDismiss: {
                    Task { await controller.dismiss(cardID: cardState.id) }
                }
            )

            controlsRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(
            height: isExpanded
                ? SidebarMediaCardStackMetrics.expandedCardHeight
                : SidebarMediaCardStackMetrics.collapsedCardHeight
        )
        .background { shape.fill(cardBackground) }
        .clipShape(shape)
        .overlay { shape.stroke(cardBorder, lineWidth: 1) }
        .shadow(color: cardShadow, radius: 6)
        .contentShape(Rectangle())
        .sidebarAppKitPrimaryAction(
            sourceID: "sidebar-mini-player-card-\(sourceIDComponent)",
            routingPriorityBoost: Self.cardSurfaceRoutingPriorityBoost,
            action: focusSource
        )
    }

    private var controlsRow: some View {
        ZStack {
            HStack(spacing: 0) {
                focusButton
                Spacer(minLength: 0)
                mediaButton(
                    systemName: cardState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: cardState.isMuted ? "Unmute Audio" : "Mute Audio",
                    isEnabled: cardState.canMute,
                    sourceID: "sidebar-mini-player-mute-\(sourceIDComponent)",
                    action: {
                        Task { await controller.toggleMute(cardID: cardState.id) }
                    }
                )
            }

            mediaButton(
                systemName: cardState.isPlaying ? "pause.fill" : "play.fill",
                help: cardState.isPlaying ? "Pause" : "Play",
                isEnabled: cardState.canPlayPause,
                isPrimary: true,
                sourceID: "sidebar-mini-player-play-pause-\(sourceIDComponent)",
                action: {
                    Task { await controller.togglePlayPause(cardID: cardState.id) }
                }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
    }

    private var focusButton: some View {
        let sourceID = "sidebar-mini-player-focus-\(sourceIDComponent)"

        return Button(action: focusSource) {
            SumiMediaSourceIconView(
                sourceHost: cardState.sourceHost,
                faviconSource: cardState.faviconSource,
                faviconImageReader: faviconImageReader
            )
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .modifier(SumiMediaControlHoverModifier(
            isEnabled: true,
            sourceID: sourceID,
            hoverBackground: tokens.chromeControlHoverBackground
        ))
        .sidebarAppKitPrimaryAction(
            sourceID: sourceID,
            routingPriorityBoost: Self.controlRoutingPriorityBoost,
            action: focusSource
        )
        .help("Focus source tab")
    }

    private func focusSource() {
        controller.activateOwner(cardID: cardState.id)
    }

    private func mediaButton(
        systemName: String,
        help: String,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        sourceID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(SidebarThemeTokens.Typography.MiniPlayer.control)
                .foregroundStyle(isPrimary ? tokens.primaryText : tokens.secondaryText)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .modifier(SumiMediaControlHoverModifier(
            isEnabled: isEnabled,
            sourceID: sourceID,
            hoverBackground: tokens.chromeControlHoverBackground
        ))
        .sidebarAppKitPrimaryAction(
            isEnabled: isEnabled,
            sourceID: sourceID,
            routingPriorityBoost: Self.controlRoutingPriorityBoost,
            action: action
        )
        .help(help)
    }
}

private struct SumiBackgroundMediaCardMetadataSlot: View {
    let isExpanded: Bool
    let title: String
    let subtitle: String
    let canPictureInPicture: Bool
    let tokens: ChromeThemeTokens
    let sourceIDComponent: String
    let routingPriorityBoost: Int
    let onTogglePictureInPicture: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                SumiBackgroundMediaCardHeader(
                    title: title,
                    subtitle: subtitle,
                    canPictureInPicture: canPictureInPicture,
                    tokens: tokens,
                    sourceIDComponent: sourceIDComponent,
                    routingPriorityBoost: routingPriorityBoost,
                    onTogglePictureInPicture: onTogglePictureInPicture,
                    onDismiss: onDismiss
                )
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: SidebarMediaCardStackMetrics.metadataSlotHeight(
                isExpanded: isExpanded
            ),
            alignment: .top
        )
        .clipped()
    }
}

private struct SumiBackgroundMediaCardHeader: View {
    let title: String
    let subtitle: String
    let canPictureInPicture: Bool
    let tokens: ChromeThemeTokens
    let sourceIDComponent: String
    let routingPriorityBoost: Int
    let onTogglePictureInPicture: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SidebarThemeTokens.Typography.MiniPlayer.title)
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SidebarThemeTokens.Typography.MiniPlayer.subtitle)
                        .foregroundStyle(tokens.secondaryText.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if canPictureInPicture {
                    headerButton(
                        systemName: "pip.enter",
                        help: "Picture in Picture",
                        sourceID: "sidebar-mini-player-pip-\(sourceIDComponent)",
                        action: onTogglePictureInPicture
                    )
                }

                headerButton(
                    systemName: "xmark",
                    help: "Close Mini Player",
                    sourceID: "sidebar-mini-player-close-\(sourceIDComponent)",
                    action: onDismiss
                )
            }
            .offset(y: SidebarMediaCardStackMetrics.headerControlsOffset)
        }
        .padding(.top, SidebarMediaCardStackMetrics.expandedHeaderTopInset)
        .frame(maxWidth: .infinity)
        .frame(
            height: SidebarMediaCardStackMetrics.expandedHeaderHeight,
            alignment: .top
        )
    }

    private func headerButton(
        systemName: String,
        help: String,
        sourceID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(SidebarThemeTokens.Typography.MiniPlayer.headerAction)
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .modifier(SumiMediaControlHoverModifier(
            isEnabled: true,
            sourceID: sourceID,
            hoverBackground: tokens.chromeControlHoverBackground
        ))
        .sidebarAppKitPrimaryAction(
            sourceID: sourceID,
            routingPriorityBoost: routingPriorityBoost,
            action: action
        )
        .help(help)
    }
}

private struct SumiMediaControlHoverModifier: ViewModifier {
    let isEnabled: Bool
    let sourceID: String
    let hoverBackground: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovered && isEnabled ? hoverBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .sidebarZenPressEffect(sourceID: sourceID, kind: .split)
            .sidebarHover(
                $isHovered,
                isEnabled: isEnabled,
                layer: SidebarMediaCardHoverLayers.control
            )
            .animation(hoverAnimation, value: isHovered)
    }

    private var hoverAnimation: Animation? {
        guard !reduceMotion, !sumiSettings.shouldReduceChromeMotion else { return nil }
        return .easeOut(duration: 0.10)
    }
}

private struct SumiMediaSourceIconView: View {
    private struct LoadRequest: Equatable {
        let source: SumiBackgroundMediaFaviconSource?
        let refreshGeneration: UInt64
    }

    private struct LoadedFavicon {
        let source: SumiBackgroundMediaFaviconSource
        let image: NSImage
    }

    let sourceHost: String?
    let faviconSource: SumiBackgroundMediaFaviconSource?
    let faviconImageReader: any BrowserFaviconImageReading

    @State private var loadedFavicon: LoadedFavicon?
    @State private var refreshGeneration: UInt64 = 0

    var body: some View {
        Group {
            if let icon = displayedFavicon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else if sourceHost != nil {
                Image(systemName: "globe")
                    .font(SidebarThemeTokens.Typography.MiniPlayer.fallbackSource)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "waveform")
                    .font(SidebarThemeTokens.Typography.MiniPlayer.fallbackSource)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: faviconLoadID) {
            await loadFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            guard let source = faviconSource,
                  SumiFaviconNotificationMatcher.update(
                    notification,
                    matches: source.documentURL,
                    partition: source.partition
                  )
            else { return }

            loadedFavicon = nil
            refreshGeneration &+= 1
        }
    }

    @MainActor
    private var displayedFavicon: NSImage? {
        guard let source = faviconSource else { return nil }
        if let image = cachedFavicon(for: source) { return image }
        guard loadedFavicon?.source == source else { return nil }
        return loadedFavicon?.image
    }

    private var faviconLoadID: LoadRequest {
        LoadRequest(source: faviconSource, refreshGeneration: refreshGeneration)
    }

    @MainActor
    private func loadFavicon() async {
        guard let source = faviconSource else {
            loadedFavicon = nil
            return
        }

        if let cachedImage = cachedFavicon(for: source) {
            loadedFavicon = LoadedFavicon(source: source, image: cachedImage)
            return
        }

        let loadedImage = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: source.documentURL,
            partition: source.partition,
            context: .tabSidebar,
            priority: .visibleSidebarOrTabStrip,
            imageReader: faviconImageReader
        )
        guard !Task.isCancelled else { return }

        if let loadedImage {
            loadedFavicon = LoadedFavicon(source: source, image: loadedImage)
        } else if loadedFavicon?.source != source {
            loadedFavicon = nil
        }
    }

    @MainActor
    private func cachedFavicon(for source: SumiBackgroundMediaFaviconSource) -> NSImage? {
        TabFaviconStore.getCachedImage(
            forDocumentURL: source.documentURL,
            partition: source.partition,
            context: .tabSidebar,
            imageReader: faviconImageReader
        )
    }
}
