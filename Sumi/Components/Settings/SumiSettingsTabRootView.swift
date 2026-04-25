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
        static let sidebarWidth: CGFloat = 260
        static let contentMaxWidth: CGFloat = 560
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 24
    }

    var body: some View {
        @Bindable var sumiSettings = sumiSettingsModel
        HStack(spacing: 0) {
            sidebar(sumiSettings: sumiSettings)
            Divider()
            detail(sumiSettings: sumiSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeContext.tokens(settings: sumiSettingsModel).windowBackground)
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

    private func sidebar(sumiSettings: SumiSettingsService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTabs.ordered, id: \.self) { pane in
                    sidebarRow(pane, sumiSettings: sumiSettings)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(width: Layout.sidebarWidth, alignment: .leading)
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
                .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
    }

    private func detail(sumiSettings: SumiSettingsService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch sumiSettings.currentSettingsTab {
                case .appearance:
                    SettingsAppearanceTab()
                case .general:
                    SettingsGeneralTab()
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
            .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
        }
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
