//
//  SafariExtensionImportCandidatesSection.swift
//  Sumi
//

import Observation
import SwiftUI

struct ExtensionSettingsFindingsProjection {
    let candidates: [DiscoveredSafariExtensionCandidate]

    init(
        discoveredCandidates: [DiscoveredSafariExtensionCandidate],
        installedExtensions: [InstalledExtension]
    ) {
        let installedSafariExtensions = installedExtensions.filter {
            $0.sourceKind == .safariAppExtension
        }
        let installedIDs = Set(installedSafariExtensions.map(\.id))
        let installedPaths = Set(
            installedSafariExtensions.lazy.map {
                URL(
                    fileURLWithPath: $0.sourceBundlePath,
                    isDirectory: true
                ).resolvingSymlinksInPath().standardizedFileURL.path
            }
        )
        candidates = discoveredCandidates.filter { candidate in
            let candidatePath = candidate.appexURL
                .resolvingSymlinksInPath()
                .standardizedFileURL.path
            return installedIDs.contains(candidate.extensionBundleIdentifier)
                == false
                && installedPaths.contains(candidatePath) == false
        }
    }
}

struct ExtensionSettingsFindingsSection: View {
    let candidates: [DiscoveredSafariExtensionCandidate]
    let scanState: ExtensionSettingsScanState
    let commands: ExtensionSettingsFindingsCommands
    let onRefresh: () -> Void

    @State private var actionSession = ExtensionSettingsFindingsActionSession()

    var body: some View {
        SettingsSection(title: "Scan and Findings") {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    if scanState.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(scanButtonTitle)
                }
                .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(scanState.isScanning)
        } content: {
            ExtensionSettingsScanStatusView(state: scanState)

            if candidates.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let statusMessage = actionSession.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(candidates) { candidate in
                        SafariWebExtensionCandidateRow(
                            candidate: candidate,
                            isBusy: actionSession.busyCandidateIDs.contains(candidate.id),
                            onAdd: {
                                actionSession.add(
                                    candidate,
                                    commands: commands
                                )
                            }
                        )
                    }
                }
            }
        }
        .onDisappear {
            actionSession.cancelAll()
        }
    }

    private var emptyMessage: LocalizedStringResource {
        switch scanState {
        case .inert:
            "Scan this Mac to find Safari Web Extensions."
        case .scanning:
            "Scanning for Safari extensions…"
        case .completed:
            "No Safari Web Extensions found on this Mac."
        case .failed:
            "No scan results."
        case .cancelled:
            "Scan cancelled."
        }
    }

    private var scanButtonTitle: LocalizedStringResource {
        if case .inert = scanState {
            return "Scan"
        }
        return "Rescan"
    }
}

private struct ExtensionSettingsScanStatusView: View {
    let state: ExtensionSettingsScanState

    var body: some View {
        Group {
            switch state {
            case .inert, .scanning, .cancelled:
                EmptyView()
            case .completed(_, let summary):
                if summary.scannerIssues.isEmpty == false {
                    Text(
                        summary.scannerIssues.count == 1
                            ? "Found 1 issue while scanning Safari extensions."
                            : "Found \(summary.scannerIssues.count) issues while scanning Safari extensions."
                    )
                }
            case .failed(_, let message):
                Text(message)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SafariWebExtensionCandidateRow: View {
    let candidate: DiscoveredSafariExtensionCandidate
    let isBusy: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text("From \(candidate.containingAppName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let version = candidate.version {
                    Text("Version \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Button(buttonTitle, action: onAdd)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || candidate.isReadable == false)
        }
        .padding(.vertical, 8)
    }

    private var buttonTitle: LocalizedStringResource {
        if candidate.isReadable == false { return "Unreadable" }
        return "Add"
    }
}

struct ExtensionSettingsContentBlockersSection: View {
    let candidates: [DiscoveredSafariExtensionCandidate]
    let records: [InstalledSafariContentBlockerRecord]
    let commands: ExtensionSettingsContentBlockerCommands
    let onRecordChanged: (InstalledSafariContentBlockerRecord) -> Void

    @State private var actionSession = ExtensionSettingsContentBlockerActionSession()

    var body: some View {
        SettingsSection(title: "Content Blockers") {
            VStack(alignment: .leading, spacing: 12) {
                if let statusMessage = actionSession.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(contentBlockerGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.candidates) { candidate in
                            SafariContentBlockerCandidateRow(
                                candidate: candidate,
                                record: recordsByID[candidate.id],
                                isBusy: actionSession.busyCandidateIDs
                                    .contains(candidate.id),
                                onToggle: { isEnabled in
                                    actionSession.setEnabled(
                                        isEnabled,
                                        candidate: candidate,
                                        commands: commands,
                                        onRecordChanged: onRecordChanged
                                    )
                                }
                            )
                        }
                    }
                }
            }
        }
        .onDisappear {
            actionSession.cancelAll()
        }
    }

    private var recordsByID: [String: InstalledSafariContentBlockerRecord] {
        Dictionary(
            uniqueKeysWithValues: records.map {
                ($0.extensionBundleIdentifier, $0)
            }
        )
    }

    private var contentBlockerGroups: [SafariContentBlockerCandidateGroup] {
        Dictionary(grouping: candidates, by: \.containingAppName)
            .map { entry in
                SafariContentBlockerCandidateGroup(
                    name: entry.key,
                    candidates: entry.value.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare(
                            $1.displayName
                        ) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }
}

struct ExtensionSettingsUnsupportedSection: View {
    let candidates: [DiscoveredSafariExtensionCandidate]

    var body: some View {
        SettingsSection(title: "Unsupported") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(candidates) { candidate in
                    SafariUnsupportedExtensionCandidateRow(candidate: candidate)
                }
            }
        }
    }
}

private struct SafariContentBlockerCandidateGroup: Identifiable {
    var id: String { name }

    let name: String
    let candidates: [DiscoveredSafariExtensionCandidate]
}

private struct SafariContentBlockerCandidateRow: View {
    let candidate: DiscoveredSafariExtensionCandidate
    let record: InstalledSafariContentBlockerRecord?
    let isBusy: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.headline)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let version = candidate.version {
                    Text("Version \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .scaleEffect(0.75)
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { record?.isEnabled == true },
                    set: { isEnabled in
                        onToggle(isEnabled)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isBusy)
            .help(
                record?.isEnabled == true
                    ? "Disable content blocker"
                    : "Enable content blocker"
            )
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        guard let record else {
            return "Static rules will be validated before enabling."
        }
        switch record.compileStatus {
        case .available:
            let count = record.ruleListCount == 1
                ? "1 rule list"
                : "\(record.ruleListCount) rule lists"
            return record.isEnabled
                ? "\(count) compiled and enabled."
                : "\(count) compiled, currently disabled."
        case .rulesUnavailable:
            return record.lastError
                ?? SafariContentBlockerCompileStatus.rulesUnavailable.title
        case .compileFailed:
            return record.lastError
                ?? SafariContentBlockerCompileStatus.compileFailed.title
        case .unknown:
            return SafariContentBlockerCompileStatus.unknown.title
        }
    }
}

private struct SafariUnsupportedExtensionCandidateRow: View {
    let candidate: DiscoveredSafariExtensionCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.headline)

                Text("From \(candidate.containingAppName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

@MainActor
@Observable
private final class ExtensionSettingsFindingsActionSession {
    private(set) var busyCandidateIDs: Set<String> = []
    private(set) var statusMessage: String?

    @ObservationIgnored private var actionTasks: [String: Task<Void, Never>] = [:]

    deinit {
        actionTasks.values.forEach { $0.cancel() }
    }

    func add(
        _ candidate: DiscoveredSafariExtensionCandidate,
        commands: ExtensionSettingsFindingsCommands
    ) {
        actionTasks[candidate.id]?.cancel()
        busyCandidateIDs.insert(candidate.id)
        actionTasks[candidate.id] = Task { @MainActor [weak self] in
            do {
                let installed = try await commands.add(candidate)
                guard Task.isCancelled == false else { return }
                self?.statusMessage = "Added \(installed.name). Enable it in Extensions above."
            } catch is CancellationError {
            } catch {
                guard Task.isCancelled == false else { return }
                self?.statusMessage = error.localizedDescription
            }
            guard Task.isCancelled == false else { return }
            self?.busyCandidateIDs.remove(candidate.id)
            self?.actionTasks[candidate.id] = nil
        }
    }

    func cancelAll() {
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        busyCandidateIDs.removeAll()
    }
}

@MainActor
@Observable
private final class ExtensionSettingsContentBlockerActionSession {
    private(set) var busyCandidateIDs: Set<String> = []
    private(set) var statusMessage: String?

    @ObservationIgnored private var actionTasks: [String: Task<Void, Never>] = [:]

    deinit {
        actionTasks.values.forEach { $0.cancel() }
    }

    func setEnabled(
        _ isEnabled: Bool,
        candidate: DiscoveredSafariExtensionCandidate,
        commands: ExtensionSettingsContentBlockerCommands,
        onRecordChanged: @escaping (InstalledSafariContentBlockerRecord) -> Void
    ) {
        actionTasks[candidate.id]?.cancel()
        busyCandidateIDs.insert(candidate.id)
        actionTasks[candidate.id] = Task { @MainActor [weak self] in
            do {
                let record = try await commands.setEnabled(
                    isEnabled,
                    for: candidate
                )
                guard Task.isCancelled == false else { return }
                if let record {
                    onRecordChanged(record)
                }
                self?.statusMessage = Self.statusMessage(
                    candidate: candidate,
                    record: record,
                    isEnabled: isEnabled
                )
            } catch is CancellationError {
            } catch {
                guard Task.isCancelled == false else { return }
                self?.statusMessage = error.localizedDescription
            }
            guard Task.isCancelled == false else { return }
            self?.busyCandidateIDs.remove(candidate.id)
            self?.actionTasks[candidate.id] = nil
        }
    }

    func cancelAll() {
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        busyCandidateIDs.removeAll()
    }

    private static func statusMessage(
        candidate: DiscoveredSafariExtensionCandidate,
        record: InstalledSafariContentBlockerRecord?,
        isEnabled: Bool
    ) -> String {
        if isEnabled, let record {
            return "Enabled \(record.displayName). Reload pages to apply content blocker changes."
        }
        return "Disabled \(candidate.displayName). Reload pages to remove its rules."
    }
}
