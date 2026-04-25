//
//  SumiSettingsTabRootView.swift
//  Sumi
//
//  In-tab settings: sidebar + detail (layout inspired by DuckDuckGo macOS
//  Preferences — see references/Duckduckgo/macOS/DuckDuckGo/Preferences/View/).
//

import AppKit
import SwiftUI

struct SumiSettingsTabRootView: View {
    @Environment(\.sumiSettings) private var sumiSettingsModel
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject var browserManager: BrowserManager
    /// When `nil` (e.g. standalone preview), sidebar still works; tab URL sync is skipped.
    var windowState: BrowserWindowState?

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarMaxWidth: CGFloat = 300
        static let compactBreakpoint: CGFloat = 760
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 24
    }

    var body: some View {
        @Bindable var sumiSettings = sumiSettingsModel
        GeometryReader { proxy in
            let isCompact = proxy.size.width < Layout.compactBreakpoint
            Group {
                if isCompact {
                    compactLayout(sumiSettings: sumiSettings)
                } else {
                    regularLayout(
                        sumiSettings: sumiSettings,
                        sidebarWidth: sidebarWidth(for: proxy.size.width)
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(tokens.windowBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.resolvedThemeContext, surfaceThemeContext)
        .environment(\.colorScheme, surfaceThemeContext.chromeColorScheme)
        .onChange(of: sumiSettings.currentSettingsTab) { _, _ in
            syncSettingsURLToActiveTab(sumiSettings: sumiSettings)
        }
        .onChange(of: sumiSettings.extensionsSettingsSubPane) { _, _ in
            if sumiSettings.currentSettingsTab == .extensions {
                syncSettingsURLToActiveTab(sumiSettings: sumiSettings)
            }
        }
        .onAppear {
            syncSettingsURLToActiveTab(sumiSettings: sumiSettings)
        }
    }

    private var surfaceThemeContext: ResolvedThemeContext {
        themeContext.nativeSurfaceThemeContext
    }

    private var tokens: ChromeThemeTokens {
        surfaceThemeContext.tokens(settings: sumiSettingsModel)
    }

    private var selectionBackground: Color {
        surfaceThemeContext.nativeSurfaceSelectionBackground
    }

    private func sidebarWidth(for availableWidth: CGFloat) -> CGFloat {
        min(
            Layout.sidebarMaxWidth,
            max(Layout.sidebarMinWidth, availableWidth * 0.24)
        )
    }

    private func regularLayout(sumiSettings: SumiSettingsService, sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            sidebar(sumiSettings: sumiSettings, width: sidebarWidth)
            Divider()
                .overlay(tokens.separator)
            detail(sumiSettings: sumiSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
    }

    private func compactLayout(sumiSettings: SumiSettingsService) -> some View {
        VStack(spacing: 0) {
            compactNavigation(sumiSettings: sumiSettings)
            Divider()
                .overlay(tokens.separator)
            detail(sumiSettings: sumiSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
    }

    private func sidebar(sumiSettings: SumiSettingsService, width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTabs.ordered, id: \.self) { pane in
                    sidebarRow(pane, sumiSettings: sumiSettings)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(width: width, alignment: .leading)
    }

    private func compactNavigation(sumiSettings: SumiSettingsService) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SettingsTabs.ordered, id: \.self) { pane in
                    compactNavigationRow(pane, sumiSettings: sumiSettings)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarRow(_ pane: SettingsTabs, sumiSettings: SumiSettingsService) -> some View {
        let selected = sumiSettings.currentSettingsTab == pane
        return Button {
            sumiSettings.currentSettingsTab = pane
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .frame(width: 18, alignment: .center)
                Text(pane.name)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? selectionBackground : Color.clear)
        )
        .foregroundStyle(tokens.primaryText)
    }

    private func compactNavigationRow(_ pane: SettingsTabs, sumiSettings: SumiSettingsService) -> some View {
        let selected = sumiSettings.currentSettingsTab == pane
        return Button {
            sumiSettings.currentSettingsTab = pane
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .frame(width: 16, alignment: .center)
                Text(pane.name)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            Capsule(style: .continuous)
                .fill(selected ? selectionBackground : tokens.fieldBackground)
        )
        .foregroundStyle(tokens.primaryText)
    }

    private func detail(sumiSettings: SumiSettingsService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch sumiSettings.currentSettingsTab {
                case .appearance:
                    SettingsAppearanceTab()
                case .general:
                    SettingsGeneralTab()
                case .performance:
                    SettingsPerformanceTab()
                case .privacy:
                    PrivacySettingsView()
                case .profiles:
                    SumiProfilesSettingsPane()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .extensions, .userScripts:
                    SumiExtensionsSettingsPane()
                case .advanced:
                    SumiDataRecoverySettingsPane()
                case .about:
                    SettingsAboutTab()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
        }
        .background(tokens.windowBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func syncSettingsURLToActiveTab(sumiSettings: SumiSettingsService) {
        guard let windowState,
              let tab = browserManager.currentTab(for: windowState),
              tab.representsSumiSettingsSurface
        else { return }
        let newURL = sumiSettings.settingsSurfaceURLForCurrentNavigation()
        guard tab.url != newURL else { return }
        tab.url = newURL
        browserManager.tabManager.scheduleRuntimeStatePersistence(for: tab)
    }
}
