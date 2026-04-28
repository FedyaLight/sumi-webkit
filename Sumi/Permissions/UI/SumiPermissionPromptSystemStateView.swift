import SwiftUI

struct SumiPermissionPromptSystemStateView: View {
    let title: String
    let message: String
    let canOpenSystemSettings: Bool
    let isPerformingAction: Bool
    let openSystemSettings: () -> Void
    let dismiss: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.system(size: 12))
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
