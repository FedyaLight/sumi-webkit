//
//  SidebarTabFaviconView.swift
//  Sumi
//
//  Aligns template SF Symbol tab icons (new tab globe, settings/history symbols) with
//  `NavButtonStyle` / top bar navigation controls (`ChromeThemeTokens.primaryText`).
//

import SwiftUI

struct SidebarTabFaviconView: View {
    @ObservedObject var tab: Tab
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    /// Fresh `Image(systemName:)` so SF Symbol rendering mode is not "baked in" from `Tab.favicon` storage.
    private var chromeSystemImageName: String {
        if tab.representsSumiSettingsSurface {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if tab.representsSumiHistorySurface {
            return SumiSurface.historyTabFaviconSystemImageName
        }
        return "globe"
    }

    var body: some View {
        Group {
            if tab.usesChromeThemedTemplateFavicon {
                Image(systemName: chromeSystemImageName)
                    .font(.system(size: size * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: size, height: size)
            } else {
                tab.favicon
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
