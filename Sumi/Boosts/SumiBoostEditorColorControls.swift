import SwiftUI

struct SumiBoostColorCanvas: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .red,
                                .orange,
                                .yellow,
                                .green,
                                .cyan,
                                .blue,
                                .purple,
                                .pink,
                                .red,
                            ]),
                            center: .center,
                            angle: .degrees(-100)
                        )
                    )
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(SumiBoostEditorStyle.primaryBackground(for: colorScheme).opacity(0.86))
                            .padding(8)
                            .overlay {
                                SumiBoostDottedOverlay(
                                    color: colorScheme == .dark
                                        ? Color.white.opacity(0.12)
                                        : Color(hex: "#DCE4DE").opacity(0.9)
                                )
                                .padding(8)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                    }
                    .saturation(session.boost.data.enableColorBoost && !session.isMonochromeMode ? 1 : 0)
                    .opacity(session.boost.data.enableColorBoost ? 1 : 0.55)

                Circle()
                    .stroke(Color.gray.opacity(0.28), lineWidth: 1)
                    .frame(
                        width: max(12, CGFloat(session.boost.data.dotDistance) * proxy.size.width * 0.84),
                        height: max(12, CGFloat(session.boost.data.dotDistance) * proxy.size.height * 0.84)
                    )

                Button(action: session.toggleMonochromeMode) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(session.isMonochromeMode ? monochromeIconForeground : SumiBoostEditorStyle.primaryText(for: colorScheme))
                        .frame(width: 24, height: 24)
                        .background(monochromeButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
                .position(x: proxy.size.width / 2, y: 24)
                .help("Monochrome")

                SumiBoostColorDot(color: session.backgroundDotColor, isPrimary: false)
                    .position(point(for: session.boost.data.secondaryDotPos, in: proxy.size))
                    .gesture(dotDrag(in: proxy, setter: session.setSecondaryDot))
                    .help("Background Color")

                SumiBoostColorDot(color: session.primaryDotColor, isPrimary: true)
                    .position(point(for: session.boost.data.dotPos, in: proxy.size))
                    .gesture(dotDrag(in: proxy, setter: session.setPrimaryDot))
                    .help("Boost Color")
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(dotDrag(in: proxy, setter: session.setPrimaryDot))
        }
    }

    /// Monochrome (sparkles) toggle button styling. Mirrors the Zen
    /// magic-theme button (`light-dark(white, #3a3a3a)` inactive, inverted when
    /// active) so the icon is always legible against its background in both
    /// light and dark schemes — never white-on-white.
    private var monochromeButtonBackground: Color {
        if session.isMonochromeMode {
            return colorScheme == .dark ? Color.white : Color(hex: "#3a3a3a")
        }
        return colorScheme == .dark ? Color(hex: "#3a3a3a") : Color.white
    }

    private var monochromeIconForeground: Color {
        // When active the background is inverted, so the icon takes the
        // opposite tone to stay readable.
        colorScheme == .dark ? Color(hex: "#3a3a3a") : Color.white
    }

    private func point(for dotPosition: SumiBoostDotPosition, in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(dotPosition.x) * size.width,
            y: CGFloat(dotPosition.y) * size.height
        )
    }

    private func dotDrag(
        in proxy: GeometryProxy,
        setter: @escaping (SumiBoostDotPosition) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let frame = proxy.frame(in: .global)
                let x = (value.location.x - frame.minX) / max(frame.width, 1)
                let y = (value.location.y - frame.minY) / max(frame.height, 1)
                setter(
                    SumiBoostDotPosition(
                        x: Double(max(0.08, min(0.92, x))),
                        y: Double(max(0.08, min(0.92, y)))
                    )
                )
            }
    }
}

private struct SumiBoostDottedOverlay: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 4
            var x: CGFloat = 2
            while x < size.width {
                var y: CGFloat = 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.9, height: 0.9)),
                        with: .color(color)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
    }
}

private struct SumiBoostColorDot: View {
    let color: Color
    let isPrimary: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: isPrimary ? 32 : 28, height: isPrimary ? 32 : 28)
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }
}

struct SumiBoostIconButton: View {
    let systemImage: String
    var isActive: Bool = false
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var background: Color {
        isActive
            ? SumiBoostEditorStyle.primaryText(for: colorScheme)
            : SumiBoostEditorStyle.buttonBackground(for: colorScheme)
    }

    private var foreground: Color {
        isActive
            ? SumiBoostEditorStyle.primaryBackground(for: colorScheme)
            : SumiBoostEditorStyle.primaryText(for: colorScheme)
    }
}

struct SumiBoostAdvancedColorButton: View {
    @ObservedObject var session: SumiBoostEditorSession
    @State private var isPresented = false

    var body: some View {
        SumiBoostIconButton(
            systemImage: "slider.horizontal.3",
            isActive: isPresented,
            help: "Advanced Color Controls"
        ) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SumiBoostAdvancedColorPopover(session: session)
        }
    }
}

private struct SumiBoostAdvancedColorPopover: View {
    @ObservedObject var session: SumiBoostEditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            slider(
                title: "Contrast",
                value: session.boost.data.contrast,
                range: 0.05...0.9,
                action: session.setContrast
            )
            slider(
                title: "Brightness",
                value: session.boost.data.brightness,
                range: 0...1,
                action: session.setBrightness
            )
            slider(
                title: "Original Saturation",
                value: session.boost.data.saturation,
                range: 0...1,
                action: session.setSaturation
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 224)
    }

    private func slider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        action: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Slider(
                value: Binding(
                    get: { value },
                    set: { action($0) }
                ),
                in: range
            )
        }
    }
}
