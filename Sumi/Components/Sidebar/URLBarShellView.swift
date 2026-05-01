//
//  URLBarShellView.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension URLBarView {
    @ViewBuilder
    var leadingContent: some View {
        if currentTab != nil {
            Text(displayURL)
                .font(.system(size: presentationMode.fontSize, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: presentationMode.fontSize))
                .foregroundStyle(textColor)

            Text("Search or Enter URL...")
                .font(.system(size: presentationMode.fontSize, weight: .medium))
                .foregroundStyle(textColor)
        }
    }

    var backgroundColor: Color {
        isHovering ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }

    var textColor: Color {
        tokens.secondaryText
    }

    var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var displayURL: String {
        guard let currentTab else { return "" }
        if currentTab.representsSumiSettingsSurface {
            return String(localized: "Settings")
        }
        if currentTab.representsSumiHistorySurface {
            return String(localized: "History")
        }
        if currentTab.representsSumiBookmarksSurface {
            return String(localized: "Bookmarks")
        }
        return formatURL(currentTab.url)
    }

    func formatURL(_ url: URL) -> String {
        if SumiSurface.isSettingsSurfaceURL(url) {
            return String(localized: "Settings")
        }
        if SumiSurface.isHistorySurfaceURL(url) {
            return String(localized: "History")
        }
        if SumiSurface.isBookmarksSurfaceURL(url) {
            return String(localized: "Bookmarks")
        }
        guard let host = url.host else {
            return url.absoluteString
        }

        return host.hasPrefix("www.")
            ? String(host.dropFirst(4))
            : host
    }

}
