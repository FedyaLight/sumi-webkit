import SwiftUI

struct SumiSiteSettingsCategoryView: View {
    @StateObject private var viewModel: SumiSiteSettingsCategoryViewModel
    let profile: Profile?
    let onBack: () -> Void
    let onOpenSite: (SumiPermissionSiteScope) -> Void

    init(
        category: SumiSiteSettingsPermissionCategory,
        repository: SumiPermissionSettingsRepository,
        profile: Profile?,
        onBack: @escaping () -> Void,
        onOpenSite: @escaping (SumiPermissionSiteScope) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SumiSiteSettingsCategoryViewModel(
                category: category,
                repository: repository
            )
        )
        self.profile = profile
        self.onBack = onBack
        self.onOpenSite = onOpenSite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SettingsSection(
                title: "Default behavior",
                subtitle: viewModel.detail?.defaultBehaviorText ?? viewModel.category.defaultBehaviorText
            ) {
                SettingsRow(title: "Global default", subtitle: "Global default editing is not available yet.", systemImage: "slider.horizontal.3") {
                    Text("Read only")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = viewModel.detail?.systemSnapshot {
                systemStatusSection(snapshot)
            }

            SettingsSection(title: "Site exceptions") {
                SumiSiteSettingsSearchField(
                    placeholder: "Search sites",
                    text: $viewModel.searchText
                )

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let detail = viewModel.detail, detail.rows.isEmpty {
                    SettingsEmptyState(
                        systemImage: "globe.badge.chevron.backward",
                        title: "No Exceptions",
                        detail: SumiSiteSettingsStrings.categoryExceptionsEmpty
                    )
                } else if let detail = viewModel.detail {
                    exceptionGroups(detail.rows)
                }
            }

            SumiSiteSettingsStatusMessage(message: viewModel.statusMessage)
            SumiSiteSettingsStatusMessage(message: viewModel.errorMessage, isError: true)
        }
        .task {
            await viewModel.load(profile: profile)
        }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) {
                Label("Site Settings", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: viewModel.category.systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.category.title)
                        .font(.title3.weight(.semibold))
                    Text(viewModel.category.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func systemStatusSection(_ snapshot: SumiSystemPermissionSnapshot) -> some View {
        SettingsSection(title: "macOS access") {
            SettingsRow(title: snapshot.kind.displayLabel, subtitle: snapshot.reason, systemImage: "gearshape") {
                if snapshot.shouldOpenSystemSettings {
                    Button("Open System Settings") {
                        Task { await viewModel.openSystemSettings() }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text(systemStateTitle(snapshot.state))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exceptionGroups(_ rows: [SumiSiteSettingsPermissionRow]) -> some View {
        let allowRows = rows.filter { $0.currentOption == .allow || $0.currentOption == .allowAll }
        let blockRows = rows.filter {
            $0.currentOption == .block
                || $0.currentOption == .blockAudible
                || $0.currentOption == .blockAll
        }
        let askRows = rows.filter {
            $0.currentOption == .ask || $0.currentOption == .default || $0.currentOption == nil
        }

        return VStack(alignment: .leading, spacing: 14) {
            exceptionGroup(title: "Allow", rows: allowRows)
            exceptionGroup(title: "Block", rows: blockRows)
            exceptionGroup(title: "Ask or default", rows: askRows)
        }
    }

    private func exceptionGroup(
        title: String,
        rows: [SumiSiteSettingsPermissionRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
            if rows.isEmpty {
                Text("No sites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            onOpenSite(row.scope)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.scope.title)
                                    .lineLimit(1)
                                if let subtitle = row.scope.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if let option = row.currentOption {
                            Menu(option.shortTitle) {
                                ForEach(row.availableOptions) { newOption in
                                    Button(newOption.title) {
                                        Task { await viewModel.setOption(newOption, for: row) }
                                    }
                                }
                                Divider()
                                Button("Remove exception") {
                                    Task { await viewModel.removeException(row) }
                                }
                            }
                            .menuStyle(.button)
                            .fixedSize()
                        }
                    }
                    .accessibilityLabel(row.accessibilityLabel)
                }
            }
        }
    }

    private func systemStateTitle(_ state: SumiSystemPermissionAuthorizationState) -> String {
        switch state {
        case .authorized:
            return "System authorized"
        case .notDetermined:
            return "Not determined"
        case .denied, .restricted:
            return "Blocked by macOS"
        case .systemDisabled:
            return "Location Services disabled"
        case .unavailable:
            return "Unavailable"
        case .missingUsageDescription:
            return "Unavailable"
        case .missingEntitlement:
            return "Unavailable"
        }
    }
}
