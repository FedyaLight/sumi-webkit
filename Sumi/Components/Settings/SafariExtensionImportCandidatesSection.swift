//
//  SafariExtensionImportCandidatesSection.swift
//  Sumi
//

import Observation
import SwiftUI

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
            .disabled(isBusy)
            .help(
                record?.isEnabled == true
                    ? "Disable content blocker"
                    : "Enable content blocker"
            )
        }
        .padding(.vertical, 4)
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
        .padding(.vertical, 4)
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
