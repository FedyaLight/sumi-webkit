//
//  SumiSettingsTabRootView.swift
//  Sumi
//
//  In-tab settings: native browser surface with stable sidebar/detail navigation.
//

import AppKit
import SwiftUI

struct SumiSettingsTabRootView: View {
    @Environment(\.sumiSettings) private var sumiSettingsModel
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(KeyboardShortcutManager.self) private var keyboardShortcutManager
    @ObservedObject var browserManager: BrowserManager
    /// When `nil` (e.g. standalone preview), sidebar still works; tab URL sync is skipped.
    var windowState: BrowserWindowState?

    @State private var searchText = ""

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 260
        static let sidebarMaxWidth: CGFloat = 300
        static let compactBreakpoint: CGFloat = 760
        static let contentMaxWidth: CGFloat = 860
        static let horizontalPadding: CGFloat = 34
        static let verticalPadding: CGFloat = 26
    }

    private var filteredDescriptors: [SettingsPaneDescriptor] {
        SettingsPaneDescriptor.filtered(by: searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .background(SettingsSurfaceStyle.pageBackground)
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
        .onChange(of: sumiSettings.privacySettingsRoute) { _, _ in
            if sumiSettings.currentSettingsTab == .privacy {
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
                .overlay(SettingsSurfaceStyle.separator)
            detail(sumiSettings: sumiSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
    }

    private func compactLayout(sumiSettings: SumiSettingsService) -> some View {
        VStack(spacing: 0) {
            compactNavigation(sumiSettings: sumiSettings)
            Divider()
            detail(sumiSettings: sumiSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
    }

    private func sidebar(sumiSettings: SumiSettingsService, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSearchField
                .padding(.horizontal, 18)
                .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if filteredDescriptors.isEmpty {
                        sidebarEmptyState
                    } else {
                        ForEach(SettingsPaneGroup.allCases, id: \.self) { group in
                            let descriptors = filteredDescriptors.filter { $0.group == group }
                            if descriptors.isEmpty == false {
                                sidebarSection(
                                    group: group,
                                    descriptors: descriptors,
                                    sumiSettings: sumiSettings
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsSurfaceStyle.pageBackground)
    }

    private var settingsSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15, weight: .medium))
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsSurfaceStyle.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsSurfaceStyle.stroke, lineWidth: 1)
        )
    }

    private var sidebarEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Results")
                .font(.headline)
            Text("Try a different settings search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private func sidebarSection(
        group: SettingsPaneGroup,
        descriptors: [SettingsPaneDescriptor],
        sumiSettings: SumiSettingsService
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 10)

            VStack(spacing: 2) {
                ForEach(descriptors) { descriptor in
                    sidebarRow(descriptor, sumiSettings: sumiSettings)
                }
            }
        }
    }

    private func sidebarRow(
        _ descriptor: SettingsPaneDescriptor,
        sumiSettings: SumiSettingsService
    ) -> some View {
        let selected = sumiSettings.currentSettingsTab == descriptor.tab

        return Button {
            sumiSettings.currentSettingsTab = descriptor.tab
            if descriptor.tab == .privacy {
                sumiSettings.privacySettingsRoute = .overview
            }
        } label: {
            HStack(spacing: 10) {
                SettingsPaneIcon(
                    systemImage: descriptor.icon,
                    color: descriptor.iconColor
                )

                Text(descriptor.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)

                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear)
        )
    }

    private func compactNavigation(sumiSettings: SumiSettingsService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSearchField
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filteredDescriptors) { descriptor in
                        compactNavigationRow(descriptor, sumiSettings: sumiSettings)
                    }
                }
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsSurfaceStyle.pageBackground)
    }

    private func compactNavigationRow(
        _ descriptor: SettingsPaneDescriptor,
        sumiSettings: SumiSettingsService
    ) -> some View {
        let selected = sumiSettings.currentSettingsTab == descriptor.tab
        return Button {
            sumiSettings.currentSettingsTab = descriptor.tab
            if descriptor.tab == .privacy {
                sumiSettings.privacySettingsRoute = .overview
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: descriptor.icon)
                    .frame(width: 16, alignment: .center)
                Text(descriptor.title)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            Capsule(style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : SettingsSurfaceStyle.fieldBackground)
        )
        .foregroundStyle(.primary)
    }

    private func detail(sumiSettings: SumiSettingsService) -> some View {
        let selectedTab = sumiSettings.currentSettingsTab

        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    if filteredDescriptors.isEmpty && isSearching {
                        SettingsEmptyState(
                            systemImage: "magnifyingglass",
                            title: "No Settings Found",
                            detail: "No settings match the current search."
                        )
                    } else {
                        detailContent(for: selectedTab)
                    }
                }
                .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
        }
        .background(SettingsSurfaceStyle.pageBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func detailContent(for selectedTab: SettingsTabs) -> some View {
        switch selectedTab {
        case .appearance:
            SettingsAppearanceTab()
        case .general:
            SettingsGeneralTab()
        case .startup:
            SettingsStartupTab()
        case .downloads:
            SettingsDownloadsTab()
        case .performance:
            SettingsPerformanceTab()
        case .privacy:
            PrivacySettingsView(browserManager: browserManager, windowState: windowState)
        case .profiles:
            SumiProfilesSettingsPane()
        case .shortcuts:
            ShortcutsSettingsView(shortcutManager: keyboardShortcutManager)
        case .extensions, .userScripts:
            SumiExtensionsSettingsPane()
        case .advanced:
            SumiDataRecoverySettingsPane()
        case .about:
            SettingsAboutTab()
        }
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

private struct SettingsPaneIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 24
    var imageSize: CGFloat = 14
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.gradient)

            Image(systemName: systemImage)
                .font(.system(size: imageSize, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.14), radius: 1.5, x: 0, y: 1)
    }
}
