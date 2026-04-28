import SwiftUI

struct SumiSiteSettingsSiteDetailView: View {
    @StateObject private var viewModel: SumiSiteSettingsSiteDetailViewModel
    let profile: Profile?
    let onBack: () -> Void

    init(
        scope: SumiPermissionSiteScope,
        repository: SumiPermissionSettingsRepository,
        profile: Profile?,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SumiSiteSettingsSiteDetailViewModel(
                scope: scope,
                repository: repository
            )
        )
        self.profile = profile
        self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            dataSection
            permissionsSection
            resetSection

            SumiSiteSettingsStatusMessage(message: viewModel.statusMessage)
            SumiSiteSettingsStatusMessage(message: viewModel.errorMessage, isError: true)
        }
        .task {
            await viewModel.load(profile: profile)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) {
                Label("All sites", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.scope.title)
                    .font(.title3.weight(.semibold))
                Text(viewModel.scope.originSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let profileName = viewModel.detail?.profileName {
                    Text(profileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dataSection: some View {
        SettingsSection(title: "Data") {
            let summary = viewModel.detail?.dataSummary
            SettingsRow(
                title: "Stored site data",
                subtitle: summary?.displayText ?? SumiSiteSettingsStrings.dataDeferred,
                systemImage: "internaldrive"
            ) {
                Button(SumiSiteSettingsStrings.deleteData) {
                    Task { await viewModel.deleteData() }
                }
                .buttonStyle(.bordered)
                .disabled(summary?.canDelete != true || viewModel.isDeletingData)
                .accessibilityLabel("Delete data for \(viewModel.scope.title)")
            }
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: "Permissions") {
            if let detail = viewModel.detail {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.permissionRows) { row in
                        SumiSiteSettingsPermissionControlRow(
                            row: row,
                            onSelect: { option in
                                Task { await viewModel.setOption(option, for: row) }
                            },
                            onOpenSystemSettings: row.showsSystemSettingsAction
                                ? { Task { await viewModel.openSystemSettings(for: row) } }
                                : nil
                        )
                        if row.id != detail.permissionRows.last?.id {
                            SettingsDivider()
                        }
                    }

                    if let filePickerRow = detail.filePickerRow {
                        SettingsDivider()
                        SumiSiteSettingsPermissionControlRow(row: filePickerRow, onSelect: { _ in })
                    }
                }
            } else {
                SettingsEmptyState(
                    systemImage: "hand.raised",
                    title: "No Permissions",
                    detail: "No stored permissions were found for this site."
                )
            }
        }
    }

    private var resetSection: some View {
        SettingsSection(title: "Reset") {
            SettingsActionRow(
                title: SumiSiteSettingsStrings.resetPermissions,
                subtitle: SumiSiteSettingsStrings.resetPermissionsSubtitle,
                systemImage: "arrow.counterclockwise",
                buttonTitle: viewModel.isResetting ? "Resetting..." : SumiSiteSettingsStrings.resetPermissions,
                role: .destructive
            ) {
                Task { await viewModel.resetPermissions() }
            }
            .disabled(viewModel.isResetting)
        }
    }
}
