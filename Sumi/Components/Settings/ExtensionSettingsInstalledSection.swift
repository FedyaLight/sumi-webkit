//
//  ExtensionSettingsInstalledSection.swift
//  Sumi
//

import AppKit
import Observation
import SwiftUI

struct ExtensionSettingsInstalledProjection {
    let enabledRows: [ExtensionSettingsInstalledRow]
    let disabledRows: [ExtensionSettingsInstalledRow]

    init(
        extensions: [InstalledExtension],
        siteAccessPoliciesByExtensionID: [String: SafariExtensionSiteAccessPolicy]
    ) {
        let rows = extensions.map { extensionRecord in
            ExtensionSettingsInstalledRow(
                extensionRecord: extensionRecord,
                siteAccessPolicy:
                    siteAccessPoliciesByExtensionID[extensionRecord.id]
            )
        }
        enabledRows = rows.filter(\.extensionRecord.isEnabled)
        disabledRows = rows.filter { $0.extensionRecord.isEnabled == false }
    }

    var isEmpty: Bool {
        enabledRows.isEmpty && disabledRows.isEmpty
    }
}

struct ExtensionSettingsInstalledRow: Identifiable {
    var id: String { extensionRecord.id }

    let extensionRecord: InstalledExtension
    let siteAccessPolicy: SafariExtensionSiteAccessPolicy?
}

enum ExtensionSettingsSiteAccessMutationAdmission {
    static func shouldPersist<Value: Equatable>(
        oldValue: Value,
        newValue: Value,
        persistedValue: Value?
    ) -> Bool {
        guard let persistedValue else { return false }
        return oldValue != newValue && newValue != persistedValue
    }
}

struct ExtensionSettingsInstalledSection: View {
    let projection: ExtensionSettingsInstalledProjection
    let commands: ExtensionSettingsInstalledCommands

    @State private var actionSession = ExtensionSettingsInstalledActionSession()

    var body: some View {
        SettingsSection(title: "Extensions") {
            if projection.isEmpty {
                Text("No extensions added.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ExtensionSettingsInstalledGroup(
                        title: "Enabled",
                        rows: projection.enabledRows,
                        busyExtensionIDs: actionSession.busyExtensionIDs,
                        commands: commands,
                        actionSession: actionSession
                    )
                    ExtensionSettingsInstalledGroup(
                        title: "Disabled",
                        rows: projection.disabledRows,
                        busyExtensionIDs: actionSession.busyExtensionIDs,
                        commands: commands,
                        actionSession: actionSession
                    )
                }
            }
        }
        .onDisappear {
            actionSession.cancelAll()
        }
    }
}

private struct ExtensionSettingsInstalledGroup: View {
    let title: LocalizedStringResource
    let rows: [ExtensionSettingsInstalledRow]
    let busyExtensionIDs: Set<String>
    let commands: ExtensionSettingsInstalledCommands
    let actionSession: ExtensionSettingsInstalledActionSession

    var body: some View {
        if rows.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        ExtensionCatalogRow(
                            extensionRecord: row.extensionRecord,
                            siteAccessPolicy: row.siteAccessPolicy,
                            isBusy: busyExtensionIDs.contains(row.id),
                            onToggleEnabled: {
                                actionSession.setEnabled(
                                    row.extensionRecord.isEnabled == false,
                                    extensionID: row.id,
                                    commands: commands
                                )
                            },
                            onDefaultSiteAccessChanged: { access in
                                commands.setDefaultSiteAccess(
                                    access,
                                    for: row.id
                                )
                            },
                            onPrivateAccessChanged: { isAllowed in
                                commands.setPrivateAccess(
                                    isAllowed,
                                    for: row.id
                                )
                            },
                            onConfiguredSiteAccessChanged: {
                                matchPattern, access in
                                commands.setConfiguredSiteAccess(
                                    access,
                                    for: row.id,
                                    matchPattern: matchPattern
                                )
                            },
                            onOpenOptions: {
                                actionSession.openOptions(
                                    extensionID: row.id,
                                    commands: commands
                                )
                            },
                            onUninstall: {
                                actionSession.uninstall(
                                    extensionID: row.id,
                                    commands: commands
                                )
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ExtensionCatalogRow: View {
    let extensionRecord: InstalledExtension
    let siteAccessPolicy: SafariExtensionSiteAccessPolicy?
    let isBusy: Bool
    let onToggleEnabled: () -> Void
    let onDefaultSiteAccessChanged: (SafariExtensionSiteAccessLevel) -> Void
    let onPrivateAccessChanged: (Bool) -> Void
    let onConfiguredSiteAccessChanged: (
        String,
        SafariExtensionSiteAccessLevel
    ) -> Void
    let onOpenOptions: () -> Void
    let onUninstall: () -> Void

    @State private var isEnabled = false
    @State private var defaultSiteAccess: SafariExtensionSiteAccessLevel = .ask
    @State private var privateAccessAllowed = false
    @State private var isDetailsPresented = false
    @State private var isUninstallConfirmationPresented = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            extensionIcon
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(extensionRecord.name)
                        .font(.headline)
                        .lineLimit(1)

                    if extensionRecord.legacyManifestMayUseMoreEnergy {
                        Image(systemName: "battery.100percent.bolt")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.orange)
                            .help(InstalledExtensionRecord.legacyManifestWarningTooltip)
                            .accessibilityLabel(
                                InstalledExtensionRecord.legacyManifestWarningTooltip
                            )
                    }
                }

                Text("Version \(extensionRecord.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Button {
                    isDetailsPresented.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .help("Extension information and permissions")
                .accessibilityIdentifier(
                    "extension-details-\(extensionRecord.id)"
                )
                .popover(isPresented: $isDetailsPresented, arrowEdge: .trailing) {
                    ExtensionCatalogDetailsPopover(
                        extensionRecord: extensionRecord,
                        siteAccessPolicy: siteAccessPolicy,
                        isBusy: isBusy,
                        defaultSiteAccess: $defaultSiteAccess,
                        privateAccessAllowed: $privateAccessAllowed,
                        onConfiguredSiteAccessChanged:
                            onConfiguredSiteAccessChanged,
                        onOpenOptions: onOpenOptions
                    )
                    .frame(width: 430)
                    .padding(16)
                    .sumiNativeSurfaceColorScheme()
                }

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isBusy)
                    .help(
                        extensionRecord.isEnabled
                            ? "Disable extension"
                            : "Enable extension"
                    )
                    .onChange(of: isEnabled) { oldValue, newValue in
                        guard oldValue != newValue,
                              newValue != extensionRecord.isEnabled
                        else { return }
                        onToggleEnabled()
                    }

                SettingsDeleteButton(
                    label: "Delete extension",
                    isDisabled: isBusy
                ) {
                    isUninstallConfirmationPresented = true
                }
                .accessibilityIdentifier(
                    "extension-delete-\(extensionRecord.id)"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear {
            isEnabled = extensionRecord.isEnabled
            syncSiteAccessState()
        }
        .onChange(of: extensionRecord.isEnabled) { _, newValue in
            isEnabled = newValue
        }
        .onChange(of: siteAccessPolicy) { _, _ in
            syncSiteAccessState()
        }
        .onChange(of: defaultSiteAccess) { oldValue, newValue in
            guard ExtensionSettingsSiteAccessMutationAdmission.shouldPersist(
                oldValue: oldValue,
                newValue: newValue,
                persistedValue: siteAccessPolicy?.defaultAccess
            )
            else { return }
            onDefaultSiteAccessChanged(newValue)
        }
        .onChange(of: privateAccessAllowed) { oldValue, newValue in
            guard ExtensionSettingsSiteAccessMutationAdmission.shouldPersist(
                oldValue: oldValue,
                newValue: newValue,
                persistedValue: siteAccessPolicy?.privateAccessAllowed
            )
            else { return }
            onPrivateAccessChanged(newValue)
        }
        .confirmationDialog(
            "Delete Extension?",
            isPresented: $isUninstallConfirmationPresented
        ) {
            Button("Delete", role: .destructive, action: onUninstall)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes \(extensionRecord.name) and all of its data and settings from Sumi. The original extension files will not be changed."
            )
        }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let iconPath = ExtensionManifestIconResolver.iconPath(for: extensionRecord),
           let image = NSImage(contentsOfFile: iconPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
        }
    }

    private func syncSiteAccessState() {
        guard let siteAccessPolicy else { return }
        defaultSiteAccess = siteAccessPolicy.defaultAccess
        privateAccessAllowed = siteAccessPolicy.privateAccessAllowed
    }
}

@MainActor
@Observable
private final class ExtensionSettingsInstalledActionSession {
    private(set) var busyExtensionIDs: Set<String> = []

    @ObservationIgnored private var enablementTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var optionsTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var uninstallTasks: [String: Task<Void, Never>] = [:]

    deinit {
        enablementTasks.values.forEach { $0.cancel() }
        optionsTasks.values.forEach { $0.cancel() }
        uninstallTasks.values.forEach { $0.cancel() }
    }

    func setEnabled(
        _ isEnabled: Bool,
        extensionID: String,
        commands: ExtensionSettingsInstalledCommands
    ) {
        enablementTasks[extensionID]?.cancel()
        busyExtensionIDs.insert(extensionID)
        enablementTasks[extensionID] = Task { @MainActor [weak self] in
            do {
                try await commands.setEnabled(isEnabled, for: extensionID)
            } catch is CancellationError {
            } catch {
                RuntimeDiagnostics.debug(category: "Extensions") {
                    "Extension settings enablement failed id=\(extensionID) error=\(error.localizedDescription)"
                }
            }
            guard Task.isCancelled == false else { return }
            self?.busyExtensionIDs.remove(extensionID)
            self?.enablementTasks[extensionID] = nil
        }
    }

    func openOptions(
        extensionID: String,
        commands: ExtensionSettingsInstalledCommands
    ) {
        optionsTasks[extensionID]?.cancel()
        optionsTasks[extensionID] = Task { @MainActor [weak self] in
            await commands.openOptions(for: extensionID)
            guard Task.isCancelled == false else { return }
            self?.optionsTasks[extensionID] = nil
        }
    }

    func uninstall(
        extensionID: String,
        commands: ExtensionSettingsInstalledCommands
    ) {
        uninstallTasks[extensionID]?.cancel()
        busyExtensionIDs.insert(extensionID)
        uninstallTasks[extensionID] = Task { @MainActor [weak self] in
            do {
                try await commands.uninstall(extensionID)
            } catch is CancellationError {
            } catch {
                RuntimeDiagnostics.debug(category: "Extensions") {
                    "Extension settings uninstall failed id=\(extensionID) error=\(error.localizedDescription)"
                }
            }
            guard Task.isCancelled == false else { return }
            self?.busyExtensionIDs.remove(extensionID)
            self?.uninstallTasks[extensionID] = nil
        }
    }

    func cancelAll() {
        enablementTasks.values.forEach { $0.cancel() }
        enablementTasks.removeAll()
        optionsTasks.values.forEach { $0.cancel() }
        optionsTasks.removeAll()
        uninstallTasks.values.forEach { $0.cancel() }
        uninstallTasks.removeAll()
        busyExtensionIDs.removeAll()
    }
}
