import SwiftUI
import SumiDomain

struct SumiPermissionPromptSystemStateView: View {
    let title: String
    let message: String
    let canOpenSystemSettings: Bool
    let isPerformingAction: Bool
    let openSystemSettings: () -> Void
    let dismiss: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(SumiPermissionRuntimeControlsThemeTokens.Typography.promptSystemIcon)
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SumiPermissionRuntimeControlsThemeTokens.Typography.promptSystemTitle)
                        .foregroundStyle(tokens.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(SumiPermissionRuntimeControlsThemeTokens.Typography.promptSystemMessage)
                        .foregroundStyle(tokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                if canOpenSystemSettings {
                    Button("Open System Settings") {
                        openSystemSettings()
                    }
                    .buttonStyle(SumiPermissionPromptButtonStyle(role: .primary))
                    .disabled(isPerformingAction)
                    .accessibilityLabel("Open System Settings")
                }

                Button("Not now") {
                    dismiss()
                }
                .buttonStyle(SumiPermissionPromptButtonStyle(role: .cancel))
                .disabled(isPerformingAction)
                .accessibilityLabel("Not now")
            }
        }
    }
}
