import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct TransparencySlider: View {
    @Binding var gradientTheme: WorkspaceGradientTheme

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @EnvironmentObject private var gradientColorManager: WorkspaceThemeEditorPreview

    @State private var localOpacity: Double = WorkspaceGradientTheme.minimumOpacity
    @State private var lastHapticBucket: Int = Int(WorkspaceGradientTheme.minimumOpacity * 10)

    private let sliderHeight: CGFloat = 96
    private let horizontalPadding: CGFloat = 5

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var normalizedProgress: Double {
        SumiOpacityWaveMetrics.normalizedProgress(for: localOpacity)
    }

    var body: some View {
        GeometryReader { proxy in
            let viewWidth = max(proxy.size.width, 1)
            let trackWidth = max(viewWidth - horizontalPadding * 2, 1)
            let progress = normalizedProgress
            let thumbSize = SumiOpacityWaveMetrics.thumbSize(for: progress)
            let rawLineBounds = SumiOpacityWaveMetrics.lineBounds(
                trackWidth: trackWidth,
                horizontalPadding: horizontalPadding
            )
            let lineBounds = SumiOpacityWaveMetrics.interactiveLineBounds(
                trackWidth: trackWidth,
                horizontalPadding: horizontalPadding,
                viewWidth: viewWidth
            )
            let travelWidth = max(lineBounds.upperBound - lineBounds.lowerBound, 1)
            let thumbX = lineBounds.lowerBound + travelWidth * progress
            let trackY = proxy.size.height / 2
            let waveWidth = trackWidth * SumiOpacityWaveMetrics.waveWidthMultiplier
            let waveAlignmentOffset = lineBounds.lowerBound - rawLineBounds.lowerBound
            let waveOriginX = horizontalPadding
                + SumiOpacityWaveMetrics.waveLeadingOffset
                + SumiOpacityWaveMetrics.waveMarginLeft
                + waveAlignmentOffset

            // When the slider is stretched (e.g. `maxWidth: .infinity`), the wave stops growing once
            // `fittedScale` caps at 1 — leave dead space on the right. Shift visuals toward the grain dial.
            let thumbHalfMax = SumiOpacityWaveMetrics.thumbSize(for: 1).width / 2
            let visualRight = lineBounds.upperBound + thumbHalfMax + 4
            let trailingSlack = max(0, viewWidth - visualRight)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tokens.separator.opacity(0.16))
                    .frame(
                        width: max(lineBounds.upperBound - lineBounds.lowerBound, 1),
                        height: SumiOpacityWaveMetrics.trackHeight
                    )
                    .position(
                        x: (lineBounds.lowerBound + lineBounds.upperBound) / 2,
                        y: trackY
                    )
                    .allowsHitTesting(false)

                SumiOpacityWaveShape(progress: progress)
                    .stroke(
                        waveStroke(for: progress),
                        style: StrokeStyle(
                            lineWidth: SumiOpacityWaveMetrics.waveStrokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: waveWidth,
                        height: SumiOpacityWaveMetrics.svgViewBox.height
                    )
                    .scaleEffect(SumiOpacityWaveMetrics.waveScale, anchor: .leading)
                    .position(
                        x: waveOriginX + waveWidth / 2,
                        y: trackY
                    )
                    .allowsHitTesting(false)

                Capsule(style: .continuous)
                    .fill(themeContext.chromeColorScheme == .dark ? Color.white : Color.black)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                    .position(x: thumbX, y: trackY)
                    .allowsHitTesting(false)
            }
            .offset(x: trailingSlack)
            .frame(width: viewWidth, height: proxy.size.height)
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateOpacity(
                                    for: value.location.x - trailingSlack,
                                    lineBounds: lineBounds
                                )
                            }
                    )
            }
        }
        .padding(.horizontal, 2)
        .frame(height: sliderHeight)
        .onAppear {
            localOpacity = clamped(gradientTheme.opacity)
            lastHapticBucket = hapticBucket(for: localOpacity)
        }
        .onChange(of: gradientTheme.opacity) { _, newValue in
            localOpacity = clamped(newValue)
            lastHapticBucket = hapticBucket(for: localOpacity)
        }
    }

    private func waveStroke(for progress: Double) -> AnyShapeStyle {
        if SumiOpacityWaveMetrics.usesGradientStroke(for: progress) {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        tokens.primaryText.opacity(0.78),
                        tokens.primaryText.opacity(0.35),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }

        return AnyShapeStyle(tokens.primaryText.opacity(0.35))
    }

    private func updateOpacity(
        for xPosition: CGFloat,
        lineBounds: ClosedRange<CGFloat>
    ) {
        let rawProgress = SumiOpacityWaveMetrics.progress(for: xPosition, in: lineBounds)
        let value = WorkspaceGradientTheme.minimumOpacity
            + Double(rawProgress) * (WorkspaceGradientTheme.maximumOpacity - WorkspaceGradientTheme.minimumOpacity)
        let nextOpacity = clamped(value)

        localOpacity = nextOpacity
        var updated = gradientTheme
        updated.updateOpacity(nextOpacity)
        gradientTheme = updated
        gradientColorManager.setImmediate(updated.renderGradient)
        playHapticIfNeeded(for: nextOpacity)
    }

    private func playHapticIfNeeded(for opacity: Double) {
        let bucket = hapticBucket(for: opacity)
        guard bucket != lastHapticBucket else { return }
        lastHapticBucket = bucket

        #if canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        #endif
    }

    private func hapticBucket(for opacity: Double) -> Int {
        Int((opacity * 10).rounded())
    }

    private func clamped(_ value: Double) -> Double {
        min(
            WorkspaceGradientTheme.maximumOpacity,
            max(WorkspaceGradientTheme.minimumOpacity, value)
        )
    }
}
