//
//  SidebarTabFaviconView.swift
//  Sumi
//
//  Aligns template SF Symbol tab icons (new tab globe and native surfaces) with
//  `NavButtonStyle` / top bar navigation controls (`ChromeThemeTokens.primaryText`).
//

import SwiftUI
import SumiDomain

struct SidebarTabFaviconView: View {
    @ObservedObject var tab: Tab
    var size: CGFloat

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    /// Fresh `Image(systemName:)` so SF Symbol rendering mode is not "baked in" from `Tab.favicon` storage.
    private var chromeSystemImageName: String {
        if tab.representsSumiHistorySurface {
            return SumiSurface.historyTabFaviconSystemImageName
        }
        if tab.representsSumiBookmarksSurface {
            return SumiSurface.bookmarksTabFaviconSystemImageName
        }
        return "globe"
    }

    var body: some View {
        Group {
            if tab.usesChromeThemedTemplateFavicon {
                Image(systemName: chromeSystemImageName)
                    .font(SidebarThemeTokens.Typography.chromeTemplateIcon(size: size))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: size, height: size)
            } else {
                tab.favicon
                    .frame(width: size, height: size)
            }
        }
    }
}
