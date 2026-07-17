import SwiftUI
import SumiDomain

struct SumiPermissionPromptDeviceListView: View {
    let text: String

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(SumiPermissionRuntimeControlsThemeTokens.Typography.promptDeviceIcon)
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 14, height: 14)

            Text(text)
                .font(SumiPermissionRuntimeControlsThemeTokens.Typography.promptDeviceText)
                .foregroundStyle(tokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
