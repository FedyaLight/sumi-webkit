import SwiftUI

struct SumiPermissionPromptView: View {
    @ObservedObject var viewModel: SumiPermissionPromptViewModel

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.isSystemBlocked {
                SumiPermissionPromptSystemStateView(
                    title: viewModel.systemBlockedTitle,
                    message: viewModel.systemBlockedMessage,
                    canOpenSystemSettings: viewModel.canOpenSystemSettings,
                    isPerformingAction: viewModel.isPerformingAction,
                    openSystemSettings: { viewModel.perform(.openSystemSettings) },
                    dismiss: { viewModel.perform(.dismiss) }
                )
            } else {
                content
                actions
            }
        }
        .padding(16)
        .frame(width: 344)
        .background(tokens.commandPaletteBackground)
        .onExitCommand {
            viewModel.perform(.dismiss)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission-authorization-popover")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 34, height: 34)
                SumiZenChromeIcon(
                    iconName: viewModel.icon.chromeIconName,
                    fallbackSystemName: viewModel.icon.fallbackSystemName,
                    size: 18,
                    tint: iconTint
                )
            }
            .accessibilityHidden(true)

            Text(viewModel.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 4)

            Button {
                viewModel.perform(.dismiss)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tokens.secondaryText)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tokens.fieldBackground.opacity(0.001))
            )
            .help("Close")
            .accessibilityLabel("Close permission prompt")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let detail = viewModel.detail {
                SumiPermissionPromptDeviceListView(text: detail)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.options) { option in
                Button(option.title) {
                    viewModel.perform(option.action)
                }
                .buttonStyle(SumiPermissionPromptButtonStyle(role: option.role))
                .disabled(!option.isEnabled)
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
    }

    private var iconTint: Color {
        viewModel.isSystemBlocked ? Color.orange.opacity(0.95) : tokens.accent
    }

    private var iconBackground: Color {
        viewModel.isSystemBlocked ? Color.orange.opacity(0.14) : tokens.accent.opacity(0.14)
    }
}

struct SumiPermissionPromptButtonStyle: ButtonStyle {
    let role: SumiPermissionPromptOption.Role

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: role == .primary ? .semibold : .medium))
            .foregroundStyle(foregroundColor)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var foregroundColor: Color {
        switch role {
        case .primary:
            return tokens.buttonPrimaryText
        case .destructive:
            return Color.red.opacity(isEnabled ? 0.95 : 0.55)
        case .normal, .cancel:
            return tokens.primaryText
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .primary:
            return tokens.accent.opacity(isPressed ? 0.82 : 0.94)
        case .destructive:
            if isPressed {
                return Color.red.opacity(0.18)
            }
            return isHovering ? Color.red.opacity(0.12) : tokens.fieldBackground
        case .normal, .cancel:
            if isPressed {
                return tokens.fieldBackgroundHover.opacity(0.96)
            }
            return isHovering ? tokens.fieldBackgroundHover.opacity(0.88) : tokens.fieldBackground
        }
    }
}
