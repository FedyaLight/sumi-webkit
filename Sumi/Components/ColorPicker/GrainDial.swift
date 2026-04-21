import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct GrainDial: View {
    @Binding var grain: Double

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @State private var isDragging = false
    @State private var isHoveringHandle = false
    @State private var lastHapticStep = SumiTextureRingMetrics.quantized(0)

    private let size: CGFloat = 76

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var quantizedValue: Double {
        SumiTextureRingMetrics.quantized(grain)
    }


    var body: some View {
        GeometryReader { proxy in
            let dialSize = CGSize(
                width: min(proxy.size.width, size),
                height: min(proxy.size.height, size)
            )
            let innerDiameter = min(dialSize.width, dialSize.height) * SumiTextureRingMetrics.innerDiameterRatio
            let handlePoint = SumiTextureRingMetrics.handlerPoint(in: dialSize, value: quantizedValue)

            ZStack {
                ForEach(0..<SumiTextureRingMetrics.stepCount, id: \.self) { index in
                    Circle()
                        .fill(
                            tokens.separator.opacity(
                                SumiTextureRingMetrics.isActive(index: index, value: quantizedValue)
                                    ? 0.95
                                    : 0.32
                            )
                        )
                        .frame(
                            width: SumiTextureRingMetrics.dotSize,
                            height: SumiTextureRingMetrics.dotSize
                        )
                        .position(SumiTextureRingMetrics.dotPoint(index: index, in: dialSize))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: quantizedValue)
                }

                ZStack {
                    Circle()
                        .fill(tokens.fieldBackground.opacity(0.98))

                    TiledNoiseTexture(
                        opacity: quantizedValue,
                        blendMode: .hardLight
                    )
                    .clipShape(Circle())

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    tokens.primaryText.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())

                    Circle()
                        .strokeBorder(tokens.separator.opacity(0.42), lineWidth: 1)
                }
                .frame(width: innerDiameter, height: innerDiameter)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        themeContext.chromeColorScheme == .dark
                            ? Color(white: 0.82)
                            : Color(white: 0.46)
                    )
                    .frame(
                        width: SumiTextureRingMetrics.handlerWidth,
                        height: isHoveringHandle || isDragging ? SumiTextureRingMetrics.handlerHoverHeight : SumiTextureRingMetrics.handlerHeight
                    )
                    .rotationEffect(.degrees(SumiTextureRingMetrics.rotationDegrees(for: quantizedValue) + 90))
                    .position(handlePoint)
                    .shadow(color: Color.black.opacity(0.08), radius: 1, y: 0.5)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHoveringHandle || isDragging)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: quantizedValue)
                    .onHover { isHoveringHandle = $0 }
            }
            .frame(width: dialSize.width, height: dialSize.height)
            .contentShape(Rectangle())
            .gesture(textureDragGesture(in: dialSize))
        }
        .frame(width: size, height: size)
        .onAppear {
            lastHapticStep = quantizedValue
        }
        .onChange(of: grain) { _, newValue in
            lastHapticStep = SumiTextureRingMetrics.quantized(newValue)
        }
    }

    private func textureDragGesture(in dialSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                updateValue(for: value.location, in: dialSize)
            }
            .onEnded { value in
                updateValue(for: value.location, in: dialSize)
                isDragging = false
            }
    }

    private func updateValue(for location: CGPoint, in dialSize: CGSize) {
        let nextValue = SumiTextureRingMetrics.quantizedValue(for: location, in: dialSize)
        guard abs(nextValue - grain) > 0.0005 else { return }

        grain = nextValue
        playHapticIfNeeded(for: nextValue)
    }

    private func playHapticIfNeeded(for value: Double) {
        let step = SumiTextureRingMetrics.quantized(value)
        guard abs(step - lastHapticStep) > 0.0005 else { return }
        lastHapticStep = step

        #if canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        #endif
    }
}
