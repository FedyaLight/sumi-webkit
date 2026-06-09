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
    @State private var importingIDs: Set<String> = []
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Safari extensions installed in other macOS apps can be imported into Sumi. Import enables the extension immediately when the runtime loads successfully.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Rescan") {
                    rescanCandidates()
                }
                .buttonStyle(.bordered)
                .disabled(isScanning)
            }

            if isScanning {
                ProgressView("Scanning applications…")
                    .controlSize(.small)
            } else if importableCandidates.isEmpty {
                Text("No importable Safari Web Extensions were found.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(importableCandidates) { candidate in
                        SafariExtensionImportCandidateRow(
                            candidate: candidate,
                            isImporting: importingIDs.contains(candidate.id),
                            onImport: {
                                importCandidate(candidate)
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            rescanCandidates()
        }
    }

    private var importableCandidates: [DiscoveredSafariExtensionCandidate] {
        let installedPaths = Set(installedExtensions.map(\.sourceBundlePath))
        return candidates.filter { candidate in
            installedPaths.contains(candidate.appexURL.path) == false
        }
    }

    private func rescanCandidates() {
        isScanning = true
        Task { @MainActor in
            defer { isScanning = false }
            guard browserManager.extensionsModule.isEnabled else {
                candidates = []
                return
            }

            var issues: [SafariExtensionScannerIssue] = []
            let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
            SafariExtensionImportStore.shared.refreshDiscoveredCandidates(discovered)
            candidates = discovered
        }
    }

    private func importCandidate(_ candidate: DiscoveredSafariExtensionCandidate) {
        importingIDs.insert(candidate.id)
        Task { @MainActor in
            defer { importingIDs.remove(candidate.id) }
            do {
                let installed = try await browserManager.extensionsModule.importSafariAppExtension(
                    from: candidate
                )
                onStatus("Imported and enabled \(installed.name).")
                rescanCandidates()
            } catch {
                onStatus(error.localizedDescription)
            }
        }
    }
}

private struct SafariExtensionImportCandidateRow: View {
    let candidate: DiscoveredSafariExtensionCandidate
    let isImporting: Bool
    let onImport: () -> Void

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

            if isImporting {
                ProgressView()
                    .scaleEffect(0.75)
            }

            Button("Import") {
                onImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting || candidate.isReadable == false)
        }
        .padding(.vertical, 4)
    }
}
