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
    @ObservedObject var browserManager: BrowserManager
    /// When `nil` (e.g. standalone preview), sidebar still works; tab URL sync is skipped.
    var windowState: BrowserWindowState?

    @State private var searchText = ""

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 224
        static let sidebarMaxWidth: CGFloat = 292
        static let compactBreakpoint: CGFloat = 760
        static let contentMaxWidth: CGFloat = 740
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 22
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
        VStack(alignment: .leading, spacing: 10) {
            settingsSearchField
                .padding(.horizontal, 10)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(tokens.windowBackground)
    }

    private var settingsSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(tokens.secondaryText)
            TextField("Search Settings", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tokens.separator.opacity(0.55), lineWidth: 1)
        )
    }

    private var sidebarEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Results")
                .font(.headline)
            Text("Try a different settings search.")
                .font(.caption)
                .foregroundStyle(tokens.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private func sidebarSection(
        group: SettingsPaneGroup,
        descriptors: [SettingsPaneDescriptor],
        sumiSettings: SumiSettingsService
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 10)

            ForEach(descriptors) { descriptor in
                sidebarRow(descriptor, sumiSettings: sumiSettings)
            }
        }
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
        .background(tokens.windowBackground)
    }

    private func sidebarRow(_ descriptor: SettingsPaneDescriptor, sumiSettings: SumiSettingsService) -> some View {
        let selected = sumiSettings.currentSettingsTab == descriptor.tab
        return Button {
            sumiSettings.currentSettingsTab = descriptor.tab
            if descriptor.tab == .privacy {
                sumiSettings.privacySettingsRoute = .overview
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: descriptor.icon)
                    .foregroundStyle(selected ? tokens.primaryText : tokens.secondaryText)
                    .frame(width: 18, alignment: .center)

                Text(descriptor.title)
                    .font(.body)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
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
                .fill(selected ? selectionBackground : tokens.fieldBackground)
        )
        .foregroundStyle(tokens.primaryText)
    }

    private func detail(sumiSettings: SumiSettingsService) -> some View {
        let selectedTab = sumiSettings.currentSettingsTab
        let descriptor = SettingsPaneDescriptor.descriptor(for: selectedTab)

        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsHeader(descriptor)

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
        .background(tokens.windowBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsHeader(_ descriptor: SettingsPaneDescriptor) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: descriptor.icon)
                .font(.title3)
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tokens.primaryText)
                Text(descriptor.subtitle)
                    .font(.callout)
                    .foregroundStyle(tokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func detailContent(for selectedTab: SettingsTabs) -> some View {
        switch selectedTab {
        case .appearance:
            SettingsAppearanceTab()
        case .general:
            SettingsGeneralTab()
        case .performance:
            SettingsPerformanceTab()
        case .privacy:
            PrivacySettingsView(browserManager: browserManager, windowState: windowState)
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
