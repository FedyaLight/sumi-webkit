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
        if tab.representsSumiBookmarksSurface {
            return SumiSurface.bookmarksTabFaviconSystemImageName
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
                    .frame(width: size, height: size)
            }
        }
    }
}

struct SidebarUnloadedRegularTabFaviconIndicator<Icon: View>: View {
    let size: CGFloat
    private let icon: () -> Icon

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    init(
        size: CGFloat,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.size = size
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: max(3, size * 0.17)) {
            Circle()
                .fill(indicatorColor)
                .frame(width: indicatorSize, height: indicatorSize)
                .accessibilityHidden(true)

            icon()
                .saturation(0.0)
                .opacity(0.8)
                .frame(width: size, height: size)
        }
        .fixedSize()
    }

    private var indicatorSize: CGFloat {
        max(4, size * 0.24)
    }

    private var indicatorColor: Color {
        themeContext.tokens(settings: sumiSettings).secondaryText.opacity(0.72)
    }
}
