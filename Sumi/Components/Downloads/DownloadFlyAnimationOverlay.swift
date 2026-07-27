import SwiftUI

struct DownloadFlyAnimationOverlay: View {
    let animationCenter: DownloadFlyAnimationCenter
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry
    let sidebarPosition: SidebarPosition

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var flight: DownloadFlyPresentation?
    @State private var showsBasket = false
    @State private var cleanupTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if showsBasket {
                    DownloadFlyBasket()
                        .position(
                            DownloadFlyPlacement.cornerTarget(
                                canvasSize: proxy.size,
                                sidebarPosition: sidebarPosition
                            )
                        )
                        .transition(
                            DownloadFlyMotion.basketTransition(
                                sidebarPosition: sidebarPosition,
                                reducesMotion: reducesMotion
                            )
                        )
                }

                if let flight {
                    DownloadFlyingGlyph(
                        presentation: flight,
                        reducesMotion: reducesMotion
                    )
                    .id(flight.id)
                }
            }
            .onReceive(animationCenter.requests) { request in
                present(request, canvasSize: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onDisappear {
            cleanupTask?.cancel()
            cleanupTask = nil
        }
    }

    private var reducesMotion: Bool {
        accessibilityReduceMotion || sumiSettings.shouldReduceChromeMotion
    }

    private func present(
        _ request: DownloadFlyAnimationRequest,
        canvasSize: CGSize
    ) {
        guard let window = windowState.shellWindow(in: windowRegistry),
              window.windowNumber == request.windowNumber
        else {
            return
        }

        var usesBasket = !windowState.isSidebarVisible
        let target: CGPoint
        if !usesBasket,
           let targetRect = downloadsPopoverPresenter.downloadAnimationTargetRect(
               in: windowState.id
           ) {
            target = DownloadFlyPlacement.swiftUIPoint(
                for: targetRect,
                canvasHeight: canvasSize.height
            )
        } else {
            usesBasket = true
            target = DownloadFlyPlacement.cornerTarget(
                canvasSize: canvasSize,
                sidebarPosition: sidebarPosition
            )
        }

        let start = DownloadFlyPlacement.swiftUIPoint(
            for: request.sourceRectInWindow,
            canvasHeight: canvasSize.height
        )
        let nextFlight = DownloadFlyPresentation(
            id: request.id,
            arc: DownloadFlyPlacement.arc(
                start: start,
                end: target
            ),
            icon: request.icon
        )

        cleanupTask?.cancel()
        if usesBasket, !showsBasket {
            withAnimation(DownloadFlyMotion.basketEntryAnimation(reducesMotion: reducesMotion)) {
                showsBasket = true
            }
        } else if !usesBasket, showsBasket {
            withAnimation(DownloadFlyMotion.basketExitAnimation(reducesMotion: reducesMotion)) {
                showsBasket = false
            }
        }
        flight = nextFlight

        cleanupTask = Task {
            try? await Task.sleep(for: .seconds(DownloadFlyMotion.totalLifetime))
            guard !Task.isCancelled, flight?.id == nextFlight.id else { return }

            flight = nil
            if usesBasket {
                withAnimation(DownloadFlyMotion.basketExitAnimation(reducesMotion: reducesMotion)) {
                    showsBasket = false
                }
            }
        }
    }
}

private struct DownloadFlyBasket: View {
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ZStack {
            NativeChromeMaterialBackground(role: .inWindowPopover)

                Image(systemName: "archivebox")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: 20, height: 20)
        }
        .frame(width: DownloadFlyPlacement.basketSize, height: DownloadFlyPlacement.basketSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tokens.floatingSurfaceBorder, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }
}

struct DownloadFlyingGlyph: View {
    let presentation: DownloadFlyPresentation
    let reducesMotion: Bool

    @State private var animationTrigger = false

    var body: some View {
        KeyframeAnimator(
            initialValue: DownloadFlyAnimationValues(
                progress: reducesMotion ? 1 : 0,
                scale: reducesMotion ? 0.55 : 0.85,
                opacity: reducesMotion ? 0.7 : 0.9
            ),
            trigger: animationTrigger
        ) { values in
            let position = presentation.arc.point(at: values.progress)

            Image(nsImage: presentation.icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
                .scaleEffect(values.scale)
                .opacity(values.opacity)
                .position(position)
        } keyframes: { _ in
            KeyframeTrack(\.progress) {
                CubicKeyframe(
                    1,
                    duration: DownloadFlyMotion.flightDuration,
                    startVelocity: 0,
                    endVelocity: 0
                )
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(
                    reducesMotion ? 0.55 : 1.03,
                    duration: DownloadFlyMotion.arcRiseDuration
                )
                CubicKeyframe(0.38, duration: DownloadFlyMotion.arcFallDuration)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: DownloadFlyMotion.fadeInDuration)
                LinearKeyframe(
                    1,
                    duration: DownloadFlyMotion.flightDuration
                        - DownloadFlyMotion.fadeInDuration
                        - DownloadFlyMotion.fadeOutDuration
                )
                LinearKeyframe(0, duration: DownloadFlyMotion.fadeOutDuration)
            }
        }
        .onAppear {
            animationTrigger.toggle()
        }
    }
}

private struct DownloadFlyAnimationValues {
    var progress: CGFloat
    var scale: CGFloat
    var opacity: CGFloat
}

struct DownloadFlyPresentation: Equatable, Identifiable {
    let id: UUID
    let arc: DownloadFlyArc
    let icon: NSImage
}

struct DownloadFlyArc: Equatable {
    let start: CGPoint
    let departureControl: CGPoint
    let arrivalControl: CGPoint
    let end: CGPoint

    func point(at progress: CGFloat) -> CGPoint {
        let inverseProgress = 1 - progress
        let inverseSquared = inverseProgress * inverseProgress
        let progressSquared = progress * progress
        let startWeight = inverseSquared * inverseProgress
        let departureWeight = 3 * inverseSquared * progress
        let arrivalWeight = 3 * inverseProgress * progressSquared
        let endWeight = progressSquared * progress

        return CGPoint(
            x: startWeight * start.x
                + departureWeight * departureControl.x
                + arrivalWeight * arrivalControl.x
                + endWeight * end.x,
            y: startWeight * start.y
                + departureWeight * departureControl.y
                + arrivalWeight * arrivalControl.y
                + endWeight * end.y
        )
    }
}

enum DownloadFlyPlacement {
    static let basketSize: CGFloat = 40
    static let cornerInset: CGFloat = 24

    static func swiftUIPoint(
        for windowRect: CGRect,
        canvasHeight: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: windowRect.midX,
            y: canvasHeight - windowRect.midY
        )
    }

    static func cornerTarget(
        canvasSize: CGSize,
        sidebarPosition: SidebarPosition
    ) -> CGPoint {
        let centerInset = cornerInset + basketSize / 2
        return CGPoint(
            x: sidebarPosition == .left
                ? centerInset
                : canvasSize.width - centerInset,
            y: canvasSize.height - centerInset
        )
    }

    static func arc(
        start: CGPoint,
        end: CGPoint
    ) -> DownloadFlyArc {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let topMargin: CGFloat = 40
        let highestEndpoint = min(start.y, end.y)
        let availableLift = max(0, highestEndpoint - topMargin)
        let lift = min(max(distance * 0.2, 56), availableLift, 144)
        let desiredMidpointY = highestEndpoint - lift
        let endpointMidpointContribution = (start.y + end.y) * 0.125
        let controlY = max(
            topMargin,
            (desiredMidpointY - endpointMidpointContribution) / 0.75
        )

        return DownloadFlyArc(
            start: start,
            departureControl: CGPoint(x: start.x, y: controlY),
            arrivalControl: CGPoint(x: end.x, y: controlY),
            end: end
        )
    }
}

private enum DownloadFlyMotion {
    static let arcRiseDuration = 0.375
    static let arcFallDuration = 0.625
    static let flightDuration = arcRiseDuration + arcFallDuration
    static let fadeInDuration = 0.12
    static let fadeOutDuration = 0.08
    static let totalLifetime = flightDuration + 0.35

    static func basketEntryAnimation(reducesMotion: Bool) -> Animation? {
        reducesMotion ? nil : .spring(duration: 0.35, bounce: 0.18)
    }

    static func basketExitAnimation(reducesMotion: Bool) -> Animation? {
        reducesMotion ? nil : .easeIn(duration: 0.24)
    }

    static func basketTransition(
        sidebarPosition: SidebarPosition,
        reducesMotion: Bool
    ) -> AnyTransition {
        guard !reducesMotion else { return .opacity }
        let edge: Edge = sidebarPosition == .left ? .leading : .trailing
        return .move(edge: edge)
            .combined(with: .scale(scale: 0.8))
            .combined(with: .opacity)
    }
}
