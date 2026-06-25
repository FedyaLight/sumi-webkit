//
//  SafariExtensionImportCandidatesSection.swift
//  Sumi
//

import SwiftUI

struct SafariExtensionImportCandidatesSection: View {
    @EnvironmentObject private var browserManager: BrowserManager

    let installedExtensions: [InstalledExtension]
    let onStatus: (String) -> Void

    @State private var candidates: [DiscoveredSafariExtensionCandidate] = []
    @State private var contentBlockerRecords: [InstalledSafariContentBlockerRecord] = []
    @State private var enablingIDs: Set<String> = []
    @State private var contentBlockerBusyIDs: Set<String> = []
    @State private var isScanning = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Safari extensions installed in other macOS apps can be enabled in Sumi without copying their extension bundles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Rescan") {
                    rescanCandidates()
                }
                .buttonStyle(.bordered)
                .disabled(isScanning)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isScanning {
                ProgressView("Scanning applications…")
                    .controlSize(.small)
            } else if webExtensionCandidates.isEmpty
                && contentBlockerCandidates.isEmpty
                && legacySafariExtensionCandidates.isEmpty
            {
                Text("No Safari extension candidates were found.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if !webExtensionCandidates.isEmpty {
                        candidateGroup("Web Extensions") {
                            ForEach(webExtensionCandidates) { candidate in
                                SafariExtensionImportCandidateRow(
                                    candidate: candidate,
                                    isEnabling: enablingIDs.contains(candidate.id),
                                    onEnable: {
                                        enableCandidate(candidate)
                                    }
                                )
                            }
                        }
                    }

                    if !contentBlockerCandidates.isEmpty {
                        candidateGroup("Content Blockers") {
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

                    if !legacySafariExtensionCandidates.isEmpty {
                        candidateGroup("Unsupported Safari Extensions") {
                            ForEach(legacySafariExtensionCandidates) { candidate in
                                SafariUnsupportedExtensionCandidateRow(candidate: candidate)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            rescanCandidates()
        }
    }

    private var webExtensionCandidates: [DiscoveredSafariExtensionCandidate] {
        let installedPaths = Set(installedExtensions.map(\.sourceBundlePath))
        return candidates.filter { candidate in
            candidate.bundleKind == .webExtension
                && installedPaths.contains(candidate.appexURL.path) == false
        }
    }

    private var contentBlockerCandidates: [DiscoveredSafariExtensionCandidate] {
        candidates.filter { $0.bundleKind == .contentBlocker }
    }

    private var legacySafariExtensionCandidates: [DiscoveredSafariExtensionCandidate] {
        candidates.filter { $0.bundleKind == .legacySafariAppExtension }
    }

    private var contentBlockerRecordsByID: [String: InstalledSafariContentBlockerRecord] {
        Dictionary(uniqueKeysWithValues: contentBlockerRecords.map { ($0.extensionBundleIdentifier, $0) })
    }

    private var contentBlockerGroups: [(name: String, candidates: [DiscoveredSafariExtensionCandidate])] {
        Dictionary(grouping: contentBlockerCandidates, by: \.containingAppName)
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

    @ViewBuilder
    private func candidateGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func rescanCandidates() {
        isScanning = true
        Task { @MainActor in
            defer { isScanning = false }
            guard browserManager.extensionsModule.isEnabled else {
                candidates = []
                contentBlockerRecords = []
                return
            }

            var issues: [SafariExtensionScannerIssue] = []
            let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
            SafariExtensionImportStore.shared.refreshDiscoveredCandidates(
                discovered.filter { $0.bundleKind == .webExtension }
            )
            candidates = discovered
            contentBlockerRecords = browserManager.extensionsModule.installedSafariContentBlockers()
        }
    }

    private func enableCandidate(_ candidate: DiscoveredSafariExtensionCandidate) {
        enablingIDs.insert(candidate.id)
        Task { @MainActor in
            defer { enablingIDs.remove(candidate.id) }
            do {
                let installed = try await browserManager.extensionsModule.enableSafariAppExtension(
                    from: candidate
                )
                onStatus("Enabled \(installed.name).")
                rescanCandidates()
            } catch {
                onStatus(error.localizedDescription)
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
                    let record = try await browserManager.extensionsModule
                        .enableSafariContentBlocker(from: candidate)
                    statusMessage = "Enabled \(record.displayName). Reload pages to apply content blocker changes."
                    onStatus(statusMessage ?? "")
                } else {
                    _ = try await browserManager.extensionsModule
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
            contentBlockerRecords = browserManager.extensionsModule.installedSafariContentBlockers()
        }
    }
}

private struct SafariExtensionImportCandidateRow: View {
    let candidate: DiscoveredSafariExtensionCandidate
    let isEnabling: Bool
    let onEnable: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.headline)

                Text("From \(candidate.containingAppName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let version = candidate.version {
                    Text("Version \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isEnabling {
                ProgressView()
                    .scaleEffect(0.75)
            }

            Button("Enable") {
                onEnable()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEnabling || candidate.isReadable == false)
        }
        .padding(.vertical, 4)
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

                Text("Legacy Safari App Extensions are hosted by Safari.app APIs and cannot run inside Sumi through public WebKit APIs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("Unsupported")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
