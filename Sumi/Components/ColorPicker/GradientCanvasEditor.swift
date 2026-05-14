import SwiftUI

struct GradientCanvasEditor: View {
    @Binding var gradientTheme: WorkspaceGradientTheme
    @Binding var harmony: SumiThemePickerHarmony
    @Binding var editorLightness: Double
    @Binding var editorColorType: WorkspaceThemeColorType

    var canvasHeight: CGFloat = 300
    var gridSpacing: CGFloat = 6
    var gridDotSize: CGFloat = 2

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @EnvironmentObject private var gradientColorManager: WorkspaceThemeEditorPreview

    @State private var isDraggingPrimary = false
    @State private var isHoveringPrimary = false
    @State private var suppressCanvasTap = false

    private let cornerRadius: CGFloat = 16
    private let layoutAnimation = Animation.spring(duration: 0.4, bounce: 0.3)
    private let canvasCoordinateSpaceName = "zen-theme-picker-canvas"

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var colors: [WorkspaceThemeColor] {
        gradientTheme.normalizedColors
    }

    private var actionState: SumiThemePickerActionState {
        SumiThemePickerActionState.resolve(dotCount: colors.count)
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = SumiThemePickerFieldGeometry(size: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tokens.fieldBackground.opacity(0.92))

                DotGrid(
                    dotColor: tokens.separator.opacity(0.2),
                    spacing: gridSpacing,
                    dotSize: gridDotSize,
                    offset: CGSize(width: -23, height: -23)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)

                if actionState.showsClickToAdd {
                    Text("Click to add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.primaryText.opacity(0.74))
                        .allowsHitTesting(false)
                }

                ForEach(Array(colors.enumerated()), id: \.element.id) { entry in
                    let index = entry.offset
                    let color = entry.element
                    let isPrimary = index == 0
                    let point = geometry.point(for: color.position)

                    if isPrimary {
                        Handle(
                            colorHex: color.hex,
                            size: 38,
                            strokeWidth: 6,
                            outerStroke: tokens.floatingBarBackground
                        )
                        .scaleEffect(primaryScale(isPrimary: true))
                        .position(point)
                        .zIndex(10)
                        .onHover { isHoveringPrimary = $0 }
                        .highPriorityGesture(primaryDragGesture(geometry: geometry))
                    } else {
                        Handle(
                            colorHex: color.hex,
                            size: 22,
                            strokeWidth: 4,
                            outerStroke: tokens.floatingBarBackground
                        )
                        .position(point)
                        .zIndex(2)
                        .allowsHitTesting(false)
                    }
                }

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tokens.separator.opacity(0.72), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .coordinateSpace(name: canvasCoordinateSpaceName)
            .gesture(canvasTapGesture(geometry: geometry))
            .onAppear {
                updatePreview(with: gradientTheme)
            }
            .onChange(of: gradientTheme) { _, updated in
                updatePreview(with: updated)
            }
        }
        .frame(height: canvasHeight)
    }

    private func primaryScale(isPrimary: Bool) -> CGFloat {
        guard isPrimary else { return 1 }
        if isDraggingPrimary {
            return 1.2
        }
        return isHoveringPrimary ? 1.05 : 1
    }

    private func canvasTapGesture(geometry: SumiThemePickerFieldGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpaceName))
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance < 4, !isDraggingPrimary, !suppressCanvasTap else { return }
                handleCanvasTap(at: value.location, geometry: geometry)
            }
    }

    private func primaryDragGesture(geometry: SumiThemePickerFieldGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpaceName))
            .onChanged { value in
                guard !colors.isEmpty else { return }
                isDraggingPrimary = true
                suppressCanvasTap = true
                movePrimary(to: value.location, geometry: geometry)
            }
            .onEnded { value in
                guard !colors.isEmpty else { return }
                movePrimary(to: value.location, geometry: geometry)
                isDraggingPrimary = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    suppressCanvasTap = false
                }
            }
    }

    private func handleCanvasTap(at location: CGPoint, geometry: SumiThemePickerFieldGeometry) {
        let clampedPoint = geometry.clamp(location)

        if colors.isEmpty {
            let primary = SumiThemePickerHarmony.makePrimaryColor(
                at: clampedPoint,
                geometry: geometry,
                lightness: editorLightness,
                type: editorColorType
            )
            applyColors([primary], harmony: .floating, animate: true)
            return
        }

        let rebuilt = SumiThemePickerHarmony.rebuildColors(
            from: colors,
            harmony: harmony,
            geometry: geometry,
            primaryPoint: clampedPoint
        )
        applyColors(rebuilt, harmony: colors.count > 1 ? harmony : .floating, animate: true)
    }

    private func movePrimary(
        to location: CGPoint,
        geometry: SumiThemePickerFieldGeometry
    ) {
        let rebuilt = SumiThemePickerHarmony.rebuildColors(
            from: colors,
            harmony: harmony,
            geometry: geometry,
            primaryPoint: geometry.clamp(location)
        )
        applyColors(rebuilt, harmony: colors.count > 1 ? harmony : .floating, animate: false)
    }

    private func applyColors(
        _ updatedColors: [WorkspaceThemeColor],
        harmony nextHarmony: SumiThemePickerHarmony,
        animate: Bool
    ) {
        let apply = {
            let resolvedHarmony = updatedColors.count > 1 ? nextHarmony : .floating
            if let primary = updatedColors.first {
                editorLightness = primary.lightness
                editorColorType = primary.type
            }

            var updatedTheme = gradientTheme
            updatedTheme.replaceColors(updatedColors, algorithm: resolvedHarmony.persistedAlgorithm)
            gradientTheme = updatedTheme
            harmony = resolvedHarmony
            gradientColorManager.activePrimaryNodeID = updatedColors.first?.id
        }

        if animate {
            withAnimation(layoutAnimation, apply)
        } else {
            apply()
        }
    }

    private func updatePreview(with theme: WorkspaceGradientTheme) {
        gradientColorManager.preferredPrimaryNodeID = theme.normalizedColors.first?.id
        gradientColorManager.activePrimaryNodeID = theme.normalizedColors.first?.id
        gradientColorManager.setImmediate(theme.renderGradient)
    }
}

private struct Handle: View {
    let colorHex: String
    let size: CGFloat
    let strokeWidth: CGFloat
    let outerStroke: Color

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(outerStroke, lineWidth: strokeWidth)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}

private struct DotGrid: View {
    let dotColor: Color
    let spacing: CGFloat
    let dotSize: CGFloat
    let offset: CGSize

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Canvas { context, _ in
                let columns = Int(width / spacing) + 8
                let rows = Int(height / spacing) + 8
                let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: dotSize, height: dotSize))

                for row in -4...rows {
                    for column in -4...columns {
                        let x = CGFloat(column) * spacing + offset.width
                        let y = CGFloat(row) * spacing + offset.height
                        context.translateBy(x: x, y: y)
                        context.fill(dot, with: .color(dotColor))
                        context.translateBy(x: -x, y: -y)
                    }
                }
            }
        }
    }
}
