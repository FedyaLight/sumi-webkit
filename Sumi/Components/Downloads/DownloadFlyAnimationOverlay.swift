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
    @State private var basketPhase: DownloadFlyBasketPhase = .parked
    @State private var basketTask: Task<Void, Never>?
    @State private var flightTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if showsBasket {
                    DownloadFlyBasket(
                        phase: basketPhase,
                        sidebarPosition: sidebarPosition,
                        reducesMotion: reducesMotion
                    )
                    .position(
                        DownloadFlyPlacement.cornerTarget(
                            canvasSize: proxy.size,
                            sidebarPosition: sidebarPosition
                        )
                    )
                    .transition(.identity)
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
            flightTask?.cancel()
            flightTask = nil
            basketTask?.cancel()
            basketTask = nil
        }
    }

    /// One display frame, long enough for a freshly mounted basket to draw.
    private static let mountFrameDuration: TimeInterval = 1.0 / 60

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
            arc: DownloadFlyArc(
                start: start,
                end: target,
                canvasHeight: canvasSize.height
            ),
            icon: request.icon
        )

        if usesBasket {
            runBasketSequence()
        } else if showsBasket {
            retractBasket()
        }

        flight = nextFlight
        flightTask?.cancel()
        flightTask = Task {
            try? await Task.sleep(for: .seconds(DownloadFlyTiming.flightDuration))
            guard !Task.isCancelled, flight?.id == nextFlight.id else { return }
            flight = nil
        }
    }

    /// Runs the basket from wherever it currently is through to retraction. A
    /// download arriving while it is already at rest only extends its stay.
    private func runBasketSequence() {
        basketTask?.cancel()
        showsBasket = true

        basketTask = Task {
            switch basketPhase {
            case .parked:
                // Let the basket render off screen before animating it in, so
                // the entry starts from the parked metrics rather than popping.
                guard await sleep(Self.mountFrameDuration),
                      await advance(to: .overshoot, holding: DownloadFlyTiming.basketOvershootDuration),
                      await advance(to: .settled, holding: DownloadFlyTiming.basketSettleDuration)
                else { return }
            case .overshoot, .squashed:
                // Caught mid-entry or on the way out: return it to rest first.
                guard await advance(to: .settled, holding: DownloadFlyTiming.basketSettleDuration)
                else { return }
            case .settled:
                break
            }

            guard await sleep(DownloadFlyTiming.basketHoldDuration),
                  await advance(to: .squashed, holding: DownloadFlyTiming.basketSquashDuration),
                  await advance(to: .parked, holding: DownloadFlyTiming.basketRetractDuration)
            else { return }

            showsBasket = false
        }
    }

    /// Sends a visible basket away without waiting out its hold, for when a
    /// later download has a real downloads button to fly to instead.
    private func retractBasket() {
        basketTask?.cancel()
        basketTask = Task {
            if basketPhase != .parked {
                guard await advance(to: .squashed, holding: DownloadFlyTiming.basketSquashDuration),
                      await advance(to: .parked, holding: DownloadFlyTiming.basketRetractDuration)
                else { return }
            } else {
                // Already retracting; just outlive the animation in flight.
                guard await sleep(DownloadFlyTiming.basketRetractDuration) else { return }
            }

            showsBasket = false
        }
    }

    /// Animates the basket into `phase`, then waits for that animation to finish.
    /// Returns `false` once the sequence has been superseded.
    @MainActor
    private func advance(
        to phase: DownloadFlyBasketPhase,
        holding duration: TimeInterval
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        withAnimation(
            DownloadFlyBasketMotion.animation(
                enteringPhase: phase,
                reducesMotion: reducesMotion
            )
        ) {
            basketPhase = phase
        }
        return await sleep(duration)
    }

    @MainActor
    private func sleep(_ duration: TimeInterval) async -> Bool {
        try? await Task.sleep(for: .seconds(duration))
        return !Task.isCancelled
    }
}

private struct DownloadFlyBasket: View {
    let phase: DownloadFlyBasketPhase
    let sidebarPosition: SidebarPosition
    let reducesMotion: Bool

    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var metrics: DownloadFlyBasketMetrics {
        DownloadFlyBasketMotion.metrics(for: phase, reducesMotion: reducesMotion)
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
        .scaleEffect(metrics.scale)
        .opacity(metrics.opacity)
        .offset(
            x: DownloadFlyBasketMotion.offset(
                for: phase,
                sidebarPosition: sidebarPosition,
                reducesMotion: reducesMotion
            )
        )
    }
}

struct DownloadFlyingGlyph: View {
    /// Rasterized size of the file icon. Kept well above the on-screen size so
    /// the glyph stays crisp when the arc swells it at the apex.
    static let renderSize: CGFloat = 64
    /// On-screen size at scale 1.
    static let baseSize: CGFloat = 30

    let presentation: DownloadFlyPresentation
    let reducesMotion: Bool

    @State private var animationTrigger = false

    var body: some View {
        KeyframeAnimator(
            initialValue: CGFloat.zero,
            trigger: animationTrigger
        ) { time in
            let frame = self.frame(atTime: time)

            Image(nsImage: presentation.icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: Self.renderSize, height: Self.renderSize)
                .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
                .scaleEffect(frame.scale * Self.baseSize / Self.renderSize)
                .opacity(frame.opacity)
                .position(frame.position)
        } keyframes: { _ in
            LinearKeyframe(1, duration: DownloadFlyTiming.flightDuration)
        }
        .onAppear {
            animationTrigger.toggle()
        }
    }

    /// Reduced motion drops the arc and the scale pulse: the glyph simply
    /// appears at the target and fades away again.
    private func frame(atTime time: CGFloat) -> DownloadFlyFrame {
        guard reducesMotion else {
            return presentation.arc.frame(atTime: time)
        }
        let fade: CGFloat
        if time < 0.2 {
            fade = time / 0.2
        } else if time < 0.8 {
            fade = 1
        } else {
            fade = max((1 - time) / 0.2, 0)
        }
        return DownloadFlyFrame(
            position: presentation.arc.end,
            scale: 1,
            opacity: fade
        )
    }
}

struct DownloadFlyPresentation: Equatable, Identifiable {
    let id: UUID
    let arc: DownloadFlyArc
    let icon: NSImage
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
}
