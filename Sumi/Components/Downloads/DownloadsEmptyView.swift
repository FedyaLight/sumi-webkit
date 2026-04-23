import SwiftUI

struct DownloadsEmptyView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Text("No downloads for this session.")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(tokens.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 0)
        .frame(maxWidth: .infinity)
    }
}
