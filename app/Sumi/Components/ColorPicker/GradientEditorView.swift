import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct GradientEditorView: View {
    static let panelWidth: CGFloat = 380

    @Binding var workspaceTheme: WorkspaceTheme
    var onThemeChange: ((WorkspaceTheme) -> Void)? = nil

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @StateObject private var editorPreview = WorkspaceThemeEditorPreview()
    @State private var presetPageIndex: Int = 0
    @State private var editorHarmony: SumiThemePickerHarmony = .floating
    @State private var editorLightness: Double = 0.8
    @State private var editorColorType: WorkspaceThemeColorType = .explicitLightness

    private let panelPadding: CGFloat = 10
    private let canvasSize: CGFloat = 358
    private let layoutAnimation = Animation.spring(duration: 0.4, bounce: 0.3)

    private var tokens: ChromeThemeTokens {
        pickerThemeContext.tokens(settings: sumiSettings)
    }

    private var gradientThemeBinding: Binding<WorkspaceGradientTheme> {
        Binding(
            get: { workspaceTheme.gradientTheme },
            set: { workspaceTheme.gradientTheme = $0 }
        )
    }

    private var textureBinding: Binding<Double> {
        Binding(
            get: { workspaceTheme.gradientTheme.texture },
            set: { newValue in
                var updated = workspaceTheme.gradientTheme
                updated.updateTexture(newValue)
                workspaceTheme.gradientTheme = updated
            }
        )
    }

    private var currentPresetGroup: SumiWorkspaceThemePresetGroup {
        let groups = SumiWorkspaceThemePresets.groups
        guard groups.indices.contains(presetPageIndex) else {
            return groups.first ?? SumiWorkspaceThemePresetGroup(name: "Presets", presets: [])
        }
        return groups[presetPageIndex]
    }

    private var colors: [WorkspaceThemeColor] {
        workspaceTheme.gradientTheme.normalizedColors
    }

    private var actionState: SumiThemePickerActionState {
        SumiThemePickerActionState.resolve(dotCount: colors.count)
    }

    private var canvasGeometry: SumiThemePickerFieldGeometry {
        SumiThemePickerFieldGeometry(size: CGSize(width: canvasSize, height: canvasSize))
    }

    /// Zen uses filled / high-contrast scheme controls only on the grayscale (last) preset page; other pages keep minimal `light-dark` icon chrome.
    private var isLastPresetPage: Bool {
        let groups = SumiWorkspaceThemePresets.groups
        guard !groups.isEmpty else { return false }
        return presetPageIndex == groups.count - 1
    }

    /// Forces chrome tokens to follow the window’s global appearance while editing the workspace gradient.
    /// Without this, `ThemeContrastResolver`-driven chrome could flip on every draft color change and make the picker chrome “breathe”; the live page still previews via `onThemeChange` / `previewWorkspaceThemePickerDraft`.
    private var pickerThemeContext: ResolvedThemeContext {
        var copy = themeContext
        copy.chromeColorScheme = themeContext.globalColorScheme
        copy.sourceChromeColorScheme = themeContext.globalColorScheme
        copy.targetChromeColorScheme = themeContext.globalColorScheme
        return copy
    }

    private var editorCanvasHoverReferenceScheme: ColorScheme {
        pickerThemeContext.globalColorScheme
    }

    private func editorCanvasActionIconTint(isDisabled: Bool) -> Color {
        SumiGradientPickerControlChrome.iconTint(
            colorScheme: pickerThemeContext.globalColorScheme,
            isDisabled: isDisabled
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            canvasSection
            presetSection
            controlSection
        }
        .padding(panelPadding)
        .frame(width: Self.panelWidth, alignment: .top)
        .background(tokens.commandPaletteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("workspace-theme-picker-panel")
        .environment(\.resolvedThemeContext, pickerThemeContext)
        .preferredColorScheme(pickerThemeContext.globalColorScheme)
        .onAppear {
            syncEditorState(with: workspaceTheme)
            editorPreview.beginInteractivePreview()
            editorPreview.setImmediate(workspaceTheme.gradient)
            onThemeChange?(workspaceTheme)
        }
        .onChange(of: workspaceTheme) { _, newValue in
            syncEditorState(with: newValue)
            editorPreview.setImmediate(newValue.gradient)
            onThemeChange?(newValue)
        }
        .onDisappear {
            editorPreview.endInteractivePreview()
        }
    }

    private var canvasSection: some View {
            GradientCanvasEditor(
                gradientTheme: gradientThemeBinding,
                harmony: $editorHarmony,
                editorLightness: $editorLightness,
                editorColorType: $editorColorType,
                canvasHeight: canvasSize,
                gridSpacing: 6,
                gridDotSize: 2
            )
            .environmentObject(editorPreview)
            .frame(width: canvasSize, height: canvasSize)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .top) {
                HStack(spacing: 5) {
                    ForEach(WindowSchemeMode.allCases) { mode in
                        ThemeSchemeButton(
                            mode: mode,
                            isSelected: sumiSettings.windowSchemeMode == mode,
                            useFilledChipStyle: isLastPresetPage,
                            globalColorScheme: pickerThemeContext.globalColorScheme,
                            tokens: tokens
                        ) {
                            sumiSettings.windowSchemeMode = mode
                        }
                    }
                }
                .padding(.top, 15)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 5) {
                    SumiPickerActionButton(
                        chromeIconName: "plus",
                        isDisabled: !actionState.canAdd,
                        iconTint: editorCanvasActionIconTint(isDisabled: !actionState.canAdd),
                        hoverReferenceScheme: editorCanvasHoverReferenceScheme
                    ) {
                        addColorPoint()
                    }

                    SumiPickerActionButton(
                        chromeIconName: "unpin",
                        isDisabled: !actionState.canRemove,
                        iconTint: editorCanvasActionIconTint(isDisabled: !actionState.canRemove),
                        hoverReferenceScheme: editorCanvasHoverReferenceScheme
                    ) {
                        removeColorPoint()
                    }

                    SumiPickerActionButton(
                        chromeIconName: "algorithm",
                        isDisabled: !actionState.canCycleHarmony,
                        iconTint: editorCanvasActionIconTint(isDisabled: !actionState.canCycleHarmony),
                        hoverReferenceScheme: editorCanvasHoverReferenceScheme
                    ) {
                        cycleHarmony()
                    }
                }
                .padding(.bottom, 22)
            }
            .frame(width: canvasSize, height: canvasSize)
    }

    private var presetSection: some View {
        HStack(spacing: 10) {
            pagerButton(systemName: "chevron.left") {
                presetPageIndex = max(0, presetPageIndex - 1)
            }
            .opacity(presetPageIndex == 0 ? 0.45 : 1)
            .disabled(presetPageIndex == 0)

            HStack(spacing: 12) {
                ForEach(currentPresetGroup.presets) { preset in
                    Button {
                        workspaceTheme = preset.workspaceTheme
                        syncEditorState(with: preset.workspaceTheme)
                    } label: {
                        SumiPresetSwatch(
                            preset: preset,
                            isSelected: workspaceTheme.visuallyEquals(preset.workspaceTheme),
                            tokens: tokens
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            pagerButton(systemName: "chevron.right") {
                presetPageIndex = min(SumiWorkspaceThemePresets.groups.count - 1, presetPageIndex + 1)
            }
            .opacity(presetPageIndex >= SumiWorkspaceThemePresets.groups.count - 1 ? 0.45 : 1)
            .disabled(presetPageIndex >= SumiWorkspaceThemePresets.groups.count - 1)
        }
        .frame(height: 28)
    }

    private var controlSection: some View {
        HStack(alignment: .center, spacing: 6) {
            TransparencySlider(gradientTheme: gradientThemeBinding)
                .environmentObject(editorPreview)
                .frame(maxWidth: .infinity)

            GrainDial(grain: textureBinding)
                .frame(width: 96, height: 96)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private func syncEditorState(with theme: WorkspaceTheme) {
        let currentColors = theme.gradientTheme.normalizedColors
        editorHarmony = SumiThemePickerHarmony.infer(from: currentColors)
        editorPreview.preferredPrimaryNodeID = currentColors.first?.id
        editorPreview.activePrimaryNodeID = currentColors.first?.id

        if let primary = currentColors.first {
            editorLightness = primary.lightness
            editorColorType = primary.type
        }
    }

    private func addColorPoint() {
        guard actionState.canAdd else { return }

        let nextHarmony = SumiThemePickerHarmony.addedHarmony(
            from: editorHarmony,
            currentDotCount: colors.count
        )
        let rebuiltColors = SumiThemePickerHarmony.rebuildColors(
            from: colors,
            targetCount: colors.count + 1,
            harmony: nextHarmony,
            geometry: canvasGeometry
        )

        applyGradientColors(rebuiltColors, harmony: nextHarmony, animate: true)
    }

    private func removeColorPoint() {
        guard actionState.canRemove else { return }

        if colors.count == 1 {
            applyGradientColors([], harmony: .floating, animate: true)
            return
        }

        let remainingColors = Array(colors.dropLast())
        let nextHarmony = SumiThemePickerHarmony.removedHarmony(
            resultingDotCount: remainingColors.count
        )
        let rebuiltColors = SumiThemePickerHarmony.rebuildColors(
            from: remainingColors,
            harmony: nextHarmony,
            geometry: canvasGeometry
        )

        applyGradientColors(rebuiltColors, harmony: nextHarmony, animate: true)
    }

    private func cycleHarmony() {
        guard actionState.canCycleHarmony else { return }

        let nextHarmony = SumiThemePickerHarmony.next(after: editorHarmony, dotCount: colors.count)
        let rebuiltColors = SumiThemePickerHarmony.rebuildColors(
            from: colors,
            harmony: nextHarmony,
            geometry: canvasGeometry
        )

        applyGradientColors(rebuiltColors, harmony: nextHarmony, animate: true)
    }

    private func applyGradientColors(
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

            var updatedGradientTheme = workspaceTheme.gradientTheme
            updatedGradientTheme.replaceColors(
                updatedColors,
                algorithm: resolvedHarmony.persistedAlgorithm
            )
            workspaceTheme.gradientTheme = updatedGradientTheme
            editorHarmony = resolvedHarmony
            editorPreview.preferredPrimaryNodeID = updatedColors.first?.id
            editorPreview.activePrimaryNodeID = updatedColors.first?.id
        }

        if animate {
            withAnimation(layoutAnimation, apply)
        } else {
            apply()
        }
    }

    private func pagerButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSchemeButton: View {
    let mode: WindowSchemeMode
    let isSelected: Bool
    /// When `true` (Grayscale preset page only), use Sumi token “chips” like accent-filled selection. Otherwise match Zen `#PanelUI-zen-gradient-generator-scheme` minimal buttons.
    let useFilledChipStyle: Bool
    let globalColorScheme: ColorScheme
    let tokens: ChromeThemeTokens
    let action: () -> Void

    @State private var isHovered = false

    private var chromeIconName: String {
        switch mode {
        case .auto:
            return "sparkles"
        case .light:
            return "face-sun"
        case .dark:
            return "moon-stars"
        }
    }

    private var chromeIcon: NSImage? {
        SumiZenFolderIconCatalog.chromeImage(named: chromeIconName)
    }

    private var fallbackSystemName: String {
        switch mode {
        case .auto:
            return "sparkles"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.stars.fill"
        }
    }

    private var iconTint: Color {
        if useFilledChipStyle {
            return isSelected ? tokens.buttonPrimaryText : tokens.primaryText
        }
        return SumiGradientPickerControlChrome.iconTint(colorScheme: globalColorScheme, isDisabled: false)
    }

    private var baseFill: Color {
        if useFilledChipStyle {
            return isSelected ? tokens.buttonPrimaryBackground : tokens.fieldBackground
        }
        return isSelected
            ? SumiGradientPickerControlChrome.minimalSelectedFill(colorScheme: globalColorScheme)
            : Color.clear
    }

    private let hitShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: action) {
            ZStack {
                hitShape.fill(baseFill)
                if isHovered {
                    hitShape.fill(SumiGradientPickerControlChrome.hoverHighlightFill(colorScheme: globalColorScheme))
                }
                Group {
                    if let chromeIcon {
                        SumiZenBundledIconView(
                            image: chromeIcon,
                            size: 14,
                            tint: iconTint
                        )
                    } else {
                        Image(systemName: fallbackSystemName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(hitShape)
            .overlay {
                hitShape.strokeBorder(
                    useFilledChipStyle
                        ? (isSelected
                            ? tokens.buttonPrimaryBackground.opacity(0.92)
                            : tokens.separator.opacity(0.55))
                        : (isSelected
                            ? iconTint.opacity(0.45)
                            : Color.clear),
                    lineWidth: useFilledChipStyle ? (isSelected ? 1.2 : 0.5) : (isSelected ? 1 : 0)
                )
            }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(mode.displayName)
    }
}

private struct SumiPickerActionButton: View {
    let chromeIconName: String
    var size: CGFloat = 30
    var isDisabled: Bool = false
    let iconTint: Color
    let hoverReferenceScheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    private var chromeIcon: NSImage? {
        SumiZenFolderIconCatalog.chromeImage(named: chromeIconName)
    }

    private var fallbackSystemName: String {
        switch chromeIconName {
        case "plus":
            return "plus"
        case "unpin":
            return "minus"
        case "algorithm":
            return "circle.hexagongrid"
        default:
            return "circle"
        }
    }

    private var hitShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isHovered && !isDisabled {
                    hitShape.fill(SumiGradientPickerControlChrome.hoverHighlightFill(colorScheme: hoverReferenceScheme))
                }
                Group {
                    if let chromeIcon {
                        SumiZenBundledIconView(
                            image: chromeIcon,
                            size: size == 30 ? 14 : 12,
                            tint: iconTint
                        )
                    } else {
                        Image(systemName: fallbackSystemName)
                            .font(.system(size: size == 30 ? 14 : 12, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }
                }
            }
            .frame(width: size, height: size)
            .contentShape(hitShape)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            guard !isDisabled else {
                isHovered = false
                return
            }
            isHovered = hovering
        }
        .onChange(of: isDisabled) { _, disabled in
            if disabled { isHovered = false }
        }
    }
}

private struct SumiPresetSwatch: View {
    let preset: SumiWorkspaceThemePreset
    let isSelected: Bool
    let tokens: ChromeThemeTokens

    var body: some View {
        ZStack {
            Circle()
                .fill(tokens.fieldBackground)
            BarycentricGradientView(gradient: preset.workspaceTheme.gradient)
                .clipShape(Circle())
                .padding(2)
        }
        .frame(width: 26, height: 26)
        .overlay {
            Circle()
                .strokeBorder(
                    isSelected ? tokens.primaryText : tokens.separator.opacity(0.55),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .shadow(
            color: isSelected ? tokens.sidebarSelectionShadow : Color.black.opacity(0.1),
            radius: isSelected ? 1.5 : 1,
            y: 1
        )
    }
}

// MARK: - External gradient-generator CSS parity (visual reference only)

private enum SumiGradientPickerControlChrome {
    /// `#PanelUI-zen-gradient-generator-color-actions` / `-scheme` `button:hover` — `light-dark(rgba(0, 0, 0, 0.1), rgba(255, 255, 255, 0.1))`
    static func hoverHighlightFill(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.1)
        case .dark:
            return Color.white.opacity(0.1)
        @unknown default:
            return Color.primary.opacity(0.08)
        }
    }

    /// `#PanelUI-zen-gradient-generator-color-actions` / `-scheme` — `color: light-dark(rgba(0, 0, 0, 0.7), rgba(255, 255, 255, 0.9))`
    static func iconTint(colorScheme: ColorScheme, isDisabled: Bool) -> Color {
        let base: Color = switch colorScheme {
        case .light:
            Color.black.opacity(0.7)
        case .dark:
            Color.white.opacity(0.9)
        @unknown default:
            Color.primary
        }
        return base.opacity(isDisabled ? 0.5 : 1)
    }

    static func minimalSelectedFill(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.1)
        case .light:
            return Color.black.opacity(0.08)
        @unknown default:
            return Color.gray.opacity(0.15)
        }
    }
}
