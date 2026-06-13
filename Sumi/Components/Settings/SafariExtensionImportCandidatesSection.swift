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
    @State private var enablingIDs: Set<String> = []
    @State private var isScanning = false

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
                            isEnabling: enablingIDs.contains(candidate.id),
                            onEnable: {
                                enableCandidate(candidate)
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
