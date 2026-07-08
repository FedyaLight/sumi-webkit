//
//  SafariExtensionImportCandidatesSection.swift
//  Sumi
//

import SwiftUI

struct SafariContentBlockerCandidatesSection: View {
    let extensionsModule: SumiExtensionsModule
    let candidates: [DiscoveredSafariExtensionCandidate]
    @Binding var contentBlockerRecords: [InstalledSafariContentBlockerRecord]
    let onStatus: (String) -> Void

    @State private var contentBlockerBusyIDs: Set<String> = []
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(contentBlockerGroups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(group.candidates) { candidate in
                        SafariContentBlockerCandidateRow(
                            candidate: candidate,
                            record: contentBlockerRecordsByID[candidate.id],
                            isBusy: contentBlockerBusyIDs.contains(candidate.id),
                            onToggle: { enabled in
                                toggleContentBlocker(candidate, enabled: enabled)
                            }
                        )
                    }
                }
            }
        }
    }

    private func toggleContentBlocker(
        _ candidate: DiscoveredSafariExtensionCandidate,
        enabled: Bool
    ) {
        contentBlockerBusyIDs.insert(candidate.id)
        Task { @MainActor in
            defer { contentBlockerBusyIDs.remove(candidate.id) }
            do {
                if enabled {
                    let record = try await extensionsModule
                        .enableSafariContentBlocker(from: candidate)
                    statusMessage = "Enabled \(record.displayName). Reload pages to apply content blocker changes."
                    onStatus(statusMessage ?? "")
                } else {
                    let _ = try await extensionsModule
                        .setSafariContentBlockerEnabled(
                            false,
                            bundleIdentifier: candidate.extensionBundleIdentifier
                        )
                    statusMessage = "Disabled \(candidate.displayName). Reload pages to remove its rules."
                    onStatus(statusMessage ?? "")
                }
            } catch {
                statusMessage = error.localizedDescription
                onStatus(error.localizedDescription)
            }
            contentBlockerRecords = extensionsModule.installedSafariContentBlockers()
        }
    }

    private var contentBlockerRecordsByID: [String: InstalledSafariContentBlockerRecord] {
        Dictionary(uniqueKeysWithValues: contentBlockerRecords.map { ($0.extensionBundleIdentifier, $0) })
    }

    private var contentBlockerGroups: [(name: String, candidates: [DiscoveredSafariExtensionCandidate])] {
        Dictionary(grouping: candidates, by: \.containingAppName)
            .map { entry in
                (
                    name: entry.key,
                    candidates: entry.value.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

struct SafariUnsupportedExtensionCandidatesSection: View {
    let candidates: [DiscoveredSafariExtensionCandidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(candidates) { candidate in
                SafariUnsupportedExtensionCandidateRow(candidate: candidate)
            }
        }
    }
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

            Toggle("", isOn: Binding(
                get: { record?.isEnabled == true },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isBusy)
            .help(record?.isEnabled == true ? "Disable content blocker" : "Enable content blocker")
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
            return record.lastError ?? SafariContentBlockerCompileStatus.rulesUnavailable.title
        case .compileFailed:
            return record.lastError ?? SafariContentBlockerCompileStatus.compileFailed.title
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
