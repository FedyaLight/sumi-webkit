//
//  PinnedButtonView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

enum PinnedTileFaviconLayout {
    static let cornerRadius: CGFloat = 6
}

struct PinnedTabView: View {
    private enum TileBackgroundState {
        case active
        case hover
        case idle
    }

    var tabIcon: SwiftUI.Image
    var glyphText: String? = nil
    /// Draw with `ChromeThemeTokens.primaryText` + monochrome (new-tab globe, settings gear, uncached globe fallback).
    var chromeTemplateSystemImageName: String? = nil
    var presentationState: ShortcutPresentationState
    var liveTab: Tab? = nil
    var dragSourceConfiguration: SidebarDragSourceConfiguration? = nil
    var accessibilityID: String? = nil
    var isAppKitInteractionEnabled: Bool = true
    var showsUnloadIndicator: Bool = false
    var showsSplitGroupOutline: Bool = false
    var supportsMiddleClickUnload: Bool = false
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    var action: () -> Void
    var onUnload: () -> Void
    var accentSourceURL: URL? = nil

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isTileHovered = false
    @State private var isActionHovered = false

    var body: some View {
        let pinnedTabsConfiguration: PinnedTabsConfiguration = .large
        let cornerRadius = sumiSettings.resolvedCornerRadius(pinnedTabsConfiguration.cornerRadius)
        ZStack {
            PinnedTileVisual(
                tabIcon: tabIcon,
                glyphText: glyphText,
                chromeTemplateSystemImageName: chromeTemplateSystemImageName,
                presentationState: presentationState,
                isHovered: displayIsHovered,
                isLoading: liveTab?.isLoading ?? false,
                showsSplitGroupOutline: showsSplitGroupOutline,
                configuration: pinnedTabsConfiguration,
                accentSourceURL: accentSourceURL ?? liveTab?.url
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
                                        .fill(backgroundColor.opacity(displayIsActionHovering ? 1 : 0.92))
                                )
                        }
                        .buttonStyle(
                            SidebarZenActionButtonStyle(
                                isEnabled: shouldShowActionButton && !freezesHoverState
                            )
                        )
                        .opacity(shouldShowActionButton ? 1 : 0)
                        .sidebarZenActionOpacity(shouldShowActionButton)
                        .allowsHitTesting(shouldShowActionButton && !freezesHoverState)
                        .accessibilityHidden(!shouldShowActionButton)
                        .accessibilityIdentifier(actionAccessibilityID ?? "pinned-tile-action")
                        .sidebarDDGHover(
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
        .frame(height: pinnedTabsConfiguration.height)
        .frame(minWidth: pinnedTabsConfiguration.minWidth)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityIdentifier(accessibilityID ?? "pinned-tile")
        .accessibilityValue(presentationState.isSelected ? "selected" : "not selected")
        .sidebarDDGHover($isTileHovered, isEnabled: isAppKitInteractionEnabled)
        .sidebarZenPressEffect(sourceID: tileSourceID, isEnabled: isAppKitInteractionEnabled)
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            dragSource: dragSourceConfiguration,
            primaryAction: action,
            onMiddleClick: supportsMiddleClickUnload ? onUnload : nil,
            sourceID: tileSourceID,
            entries: contextMenuEntries
        )
        .shadow(
            color: presentationState.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: presentationState.isSelected ? 2 : 0,
            y: presentationState.isSelected ? 1 : 0
        )
    }
    
    //MARK: - Colors
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
        SidebarHoverChrome.displayHover(isTileHovered, freezesHoverState: freezesHoverState)
    }

    private var displayIsActionHovering: Bool {
        SidebarHoverChrome.displayHover(isActionHovered, freezesHoverState: freezesHoverState)
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
    var glyphText: String? = nil
    var chromeTemplateSystemImageName: String? = nil
    var presentationState: ShortcutPresentationState
    var isHovered: Bool = false
    var isLoading: Bool = false
    var showsSplitGroupOutline: Bool = false
    var faviconOpacity: Double = 1
    var configuration: PinnedTabsConfiguration? = nil
    var accentSourceURL: URL? = nil

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectionAccentColor: Color {
        PinnedTileAccentResolver.resolve(
            launchURL: accentSourceURL,
            glyphText: glyphText,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            tokens: tokens
        )
    }

    var body: some View {
        let pinnedTabsConfiguration = configuration ?? .large
        let cornerRadius = sumiSettings.resolvedCornerRadius(pinnedTabsConfiguration.cornerRadius)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    if presentationState.isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(selectionAccentColor.opacity(0.35 * faviconOpacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    resolvedFaviconSymbol(height: pinnedTabsConfiguration.faviconHeight)
                        .saturation(presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
                        .opacity((presentationState.shouldDesaturateIcon ? 0.8 : 1.0) * faviconOpacity)
                    Spacer()
                }
                Spacer()
            }

            if showsSplitGroupOutline {
                PinnedTileSplitGroupOutlineMask(
                    corner: cornerRadius,
                    thickness: max(1.25, pinnedTabsConfiguration.strokeWidth * 0.7),
                    strokeColor: selectionAccentColor
                )
                .conditionally(
                    if: isLoading && !reduceMotion
                        && !sumiSettings.shouldDisableDecorativeLoadingEffects
                ) { view in
                    view.mask {
                        PinnedTileLoadingAlphaWaveLayerMask()
                            .padding(-pinnedTabsConfiguration.outlineMaskBleed)
                    }
                }
                .allowsHitTesting(false)
            } else if presentationState.isSelected {
                accentSelectionRingOverlay(
                    corner: cornerRadius,
                    thickness: pinnedTabsConfiguration.strokeWidth,
                    color: selectionAccentColor
                )
                .conditionally(
                    if: isLoading && !reduceMotion
                        && !sumiSettings.shouldDisableDecorativeLoadingEffects
                ) { view in
                    view.mask {
                        PinnedTileLoadingAlphaWaveLayerMask()
                            .padding(-pinnedTabsConfiguration.outlineMaskBleed)
                    }
                }
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
        Group {
            if let glyphText {
                Text(glyphText)
                    .font(.system(size: height * 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)
            } else if let systemName = chromeTemplateSystemImageName {
                Image(systemName: systemName)
                    .font(.system(size: height * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.primaryText)
            } else {
                tabIcon
            }
        }
        .frame(width: height, height: height)
    }

    private func accentSelectionRingOverlay(
        corner: CGFloat,
        thickness: CGFloat,
        color: Color
    ) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let strokeInset = thickness / 2
            let rect = RoundedRectangle(
                cornerRadius: max(0, corner - strokeInset),
                style: .continuous
            )
            .inset(by: strokeInset)

            rect.stroke(color, lineWidth: thickness)
            .frame(width: size.width, height: size.height)
        }
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

private struct PinnedTileLoadingAlphaWaveLayerMask: View {
    var body: some View {
        GeometryReader { proxy in
            PinnedTileLoadingAlphaWaveMaskRepresentable()
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct PinnedTileLoadingAlphaWaveMaskRepresentable: NSViewRepresentable {
    func makeNSView(context _: Context) -> PinnedTileLoadingAlphaWaveMaskView {
        PinnedTileLoadingAlphaWaveMaskView()
    }

    func updateNSView(_ nsView: PinnedTileLoadingAlphaWaveMaskView, context _: Context) {
        nsView.updateAnimation()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PinnedTileLoadingAlphaWaveMaskView,
        context _: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.fittingSize.width,
            height: proposal.height ?? nsView.fittingSize.height
        )
    }
}

private final class PinnedTileLoadingAlphaWaveMaskView: NSView {
    private let gradientLayer = CAGradientLayer()
    private var lastConfiguredSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimation()
        } else {
            updateAnimation()
        }
    }

    func updateAnimation() {
        guard bounds.width > 1,
              bounds.height > 1,
              LoadingWaveController.shared.shouldStartAnimation(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                energySaverDisablesDecorativeEffects: false
              )
        else {
            stopAnimation()
            return
        }

        guard lastConfiguredSize != bounds.size
                || gradientLayer.animation(forKey: SumiTabTitleAnimation.loadingAlphaWaveKey) == nil
        else {
            return
        }

        if gradientLayer.animation(forKey: SumiTabTitleAnimation.loadingAlphaWaveKey) == nil {
            LoadingWaveController.shared.beginAnimation()
        }

        lastConfiguredSize = bounds.size
        configureGradientLayer()
        gradientLayer.add(buildAnimation(), forKey: SumiTabTitleAnimation.loadingAlphaWaveKey)
    }

    private func stopAnimation() {
        if gradientLayer.animation(forKey: SumiTabTitleAnimation.loadingAlphaWaveKey) != nil {
            LoadingWaveController.shared.endAnimation()
        }
        gradientLayer.removeAnimation(forKey: SumiTabTitleAnimation.loadingAlphaWaveKey)
        lastConfiguredSize = .zero
    }

    private func configureGradientLayer() {
        let halfWidth = SumiTabTitleAnimation.loadingAlphaWaveRelativeHalfWidth(for: bounds.width)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        gradientLayer.frame = bounds
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.colors = SumiTabTitleAnimation.loadingAlphaWaveMaskColors
        gradientLayer.locations = SumiTabTitleAnimation.loadingAlphaWaveLocations(
            centerX: -halfWidth,
            width: bounds.width
        )
        gradientLayer.opacity = 1

        CATransaction.commit()
    }

    private func buildAnimation() -> CABasicAnimation {
        let halfWidth = SumiTabTitleAnimation.loadingAlphaWaveRelativeHalfWidth(for: bounds.width)
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = SumiTabTitleAnimation.loadingAlphaWaveLocations(
            centerX: -halfWidth,
            width: bounds.width
        )
        animation.toValue = SumiTabTitleAnimation.loadingAlphaWaveLocations(
            centerX: 1 + halfWidth,
            width: bounds.width
        )
        animation.duration = SumiTabTitleAnimation.loadingAlphaWaveCycleDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
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
                        .font(.system(size: 11, weight: .bold))
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
                .sidebarDDGHover($isHovering, isEnabled: isAppKitInteractionEnabled)
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
        SidebarHoverChrome.displayHover(
            isHovering,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return replacement + String(dropFirst(prefix.count))
    }
}
