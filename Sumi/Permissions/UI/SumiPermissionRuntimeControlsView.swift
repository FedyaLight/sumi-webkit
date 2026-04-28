import SwiftUI

struct SumiPermissionRuntimeControlsView: View {
    @ObservedObject var model: SumiPermissionRuntimeControlsViewModel
    let onAction: (SumiPermissionRuntimeControl.Action.Kind) async -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(model.controls) { control in
                SumiPermissionRuntimeControlRow(
                    control: control,
                    onAction: onAction
                )
            }

            if let result = model.lastResult {
                Text(result.message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(result.isError ? Color.red.opacity(0.9) : tokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(result.message)
            }
        }
    }
}

private struct SumiPermissionRuntimeControlRow: View {
    let control: SumiPermissionRuntimeControl
    let onAction: (SumiPermissionRuntimeControl.Action.Kind) async -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            icon

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(control.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)

                    Text(control.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(tokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !control.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(control.actions) { action in
                            Button {
                                Task {
                                    await onAction(action.kind)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(action.title)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                    if control.inProgressActionKind == action.kind {
                                        ProgressView()
                                            .controlSize(.small)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(
                                SumiPermissionRuntimeActionButtonStyle(
                                    isDestructive: action.isDestructive
                                )
                            )
                            .disabled(control.isOperationInProgress)
                            .help(action.accessibilityLabel)
                            .accessibilityLabel(action.accessibilityLabel)
                        }
                    }
                } else if let disabledReason = control.disabledReason {
                    Text(disabledReason)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(control.accessibilityLabel)
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.commandPaletteBackground.opacity(0.8))

            SumiZenChromeIcon(
                iconName: control.iconName,
                fallbackSystemName: control.fallbackSystemName,
                size: 16,
                tint: tokens.primaryText
            )
        }
        .frame(width: 34, height: 34)
    }
}

private struct SumiPermissionRuntimeActionButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let isDestructive: Bool

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var foregroundColor: Color {
        guard isDestructive else { return tokens.primaryText }
        return Color.red.opacity(0.88)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isDestructive {
            if isPressed {
                return Color.red.opacity(0.16)
            }
            if isHovered {
                return Color.red.opacity(0.12)
            }
        }
        return ThemeChromeRecipeBuilder.urlBarPillFieldBackground(
            tokens: tokens,
            isPressed: isPressed,
            isHovering: isHovered,
            isEnabled: isEnabled
        )
    }
}
