import SwiftUI

struct SumiSiteSettingsView: View {
    enum Route: Equatable {
        case main
        case siteList
        case category(SumiSiteSettingsPermissionCategory)
        case siteDetail(SumiPermissionSiteScope)
    }

    @StateObject private var viewModel: SumiSiteSettingsViewModel
    @State private var route: Route = .main
    @State private var didApplyInitialFilter = false

    let profile: Profile?
    let initialFilter: SumiSettingsSiteSettingsFilter?
    let onBack: () -> Void

    init(
        repository: SumiPermissionSettingsRepository,
        profile: Profile?,
        initialFilter: SumiSettingsSiteSettingsFilter? = nil,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SumiSiteSettingsViewModel(repository: repository))
        self.profile = profile
        self.initialFilter = initialFilter
        self.onBack = onBack
    }

    var body: some View {
        Group {
            switch route {
            case .main:
                mainPage
            case .siteList:
                siteListPage
            case .category(let category):
                SumiSiteSettingsCategoryView(
                    category: category,
                    repository: viewModel.repository,
                    profile: profile,
                    onBack: { route = .main },
                    onOpenSite: { route = .siteDetail($0) }
                )
            case .siteDetail(let scope):
                SumiSiteSettingsSiteDetailView(
                    scope: scope,
                    repository: viewModel.repository,
                    profile: profile,
                    onBack: { route = .siteList }
                )
            }
        }
        .task {
            await viewModel.load(profile: profile)
            await applyInitialFilterIfNeeded()
        }
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onBack) {
                Label("Privacy & Security", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            SumiSiteSettingsRecentActivityView(items: viewModel.recentActivity)

            SettingsSection(title: "Sites") {
                SumiSiteSettingsNavigationRow(
                    title: SumiSiteSettingsStrings.viewSitesTitle,
                    subtitle: SumiSiteSettingsStrings.viewSitesSubtitle,
                    systemImage: "globe",
                    action: { route = .siteList }
                )
            }

            permissionsSection
            unsupportedSection
            cleanupSection

            SumiSiteSettingsStatusMessage(message: viewModel.errorMessage, isError: true)
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: SumiSiteSettingsStrings.permissions) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.categoryRows) { row in
                    SumiSiteSettingsNavigationRow(
                        title: row.title,
                        subtitle: row.subtitle,
                        systemImage: row.systemImage,
                        accessibilityLabel: "\(row.title), \(row.subtitle)"
                    ) {
                        route = .category(row.category)
                    }

                    if row.id != viewModel.categoryRows.last?.id {
                        SettingsDivider()
                    }
                }
            }
        }
    }

    private var unsupportedSection: some View {
        SettingsSection(
            title: SumiSiteSettingsStrings.moreContentSettings,
            subtitle: SumiSiteSettingsStrings.unsupportedContentCopy
        ) {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }

    private var cleanupSection: some View {
        SettingsSection(
            title: SumiSiteSettingsStrings.automaticCleanup,
            subtitle: SumiSiteSettingsStrings.automaticCleanupCopy
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(
                    title: "Automatic cleanup",
                    subtitle: "Removes saved allow permissions for sites not used in the last \(viewModel.cleanupSettings.thresholdDays) days.",
                    systemImage: "clock.arrow.circlepath"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.cleanupSettingsBinding().isAutomaticCleanupEnabled },
                            set: { isEnabled in
                                Task {
                                    await viewModel.setAutomaticCleanupEnabled(
                                        isEnabled,
                                        profile: profile
                                    )
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Automatic permission cleanup")
                }

                if let cleanupStatusText = viewModel.cleanupStatusText {
                    Text(cleanupStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
        }
    }

    private var siteListPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                route = .main
            } label: {
                Label(SumiSiteSettingsStrings.title, systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            SettingsSection(title: SumiSiteSettingsStrings.siteListTitle) {
                VStack(alignment: .leading, spacing: 12) {
                    SumiSiteSettingsSearchField(
                        placeholder: "Search sites",
                        text: $viewModel.searchText
                    )
                    .onChange(of: viewModel.searchText) { _, _ in
                        Task { await viewModel.updateSearch(profile: profile) }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.siteRows.isEmpty {
                        SettingsEmptyState(
                            systemImage: "globe",
                            title: "No Sites",
                            detail: SumiSiteSettingsStrings.siteListEmpty
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.siteRows) { row in
                                SumiSiteSettingsNavigationRow(
                                    title: row.title,
                                    subtitle: row.subtitle,
                                    systemImage: "globe"
                                ) {
                                    route = .siteDetail(row.scope)
                                }
                                if row.id != viewModel.siteRows.last?.id {
                                    SettingsDivider()
                                }
                            }
                        }
                    }
                }
            }

            SumiSiteSettingsStatusMessage(message: viewModel.errorMessage, isError: true)
        }
    }

    private func applyInitialFilterIfNeeded() async {
        guard !didApplyInitialFilter, let initialFilter else { return }
        didApplyInitialFilter = true
        if let domain = initialFilter.displayDomain, !domain.isEmpty {
            viewModel.searchText = domain
            await viewModel.updateSearch(profile: profile)
        }

        let matchingRow = viewModel.siteRows.first { row in
            let requestingMatches = initialFilter.requestingOriginIdentity.map {
                $0 == row.scope.requestingOrigin.identity
            } ?? true
            let topMatches = initialFilter.topOriginIdentity.map {
                $0 == row.scope.topOrigin.identity
            } ?? true
            return requestingMatches && topMatches
        }

        if let matchingRow {
            route = .siteDetail(matchingRow.scope)
        } else {
            route = .siteList
        }
    }
}
