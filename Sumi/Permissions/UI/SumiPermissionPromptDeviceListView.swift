import SwiftUI

struct SumiPermissionPromptDeviceListView: View {
    let text: String

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 14, height: 14)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(tokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
