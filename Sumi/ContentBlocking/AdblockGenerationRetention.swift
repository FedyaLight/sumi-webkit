import Foundation

actor AdblockGenerationRetention {
    private let archive: AdblockGenerationArchive
    private let contentRuleListStore: any SumiContentRuleListCompiling
    private let fileManager: FileManager
    #if DEBUG
        private let startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    init(
        archive: AdblockGenerationArchive,
        contentRuleListStore: any SumiContentRuleListCompiling,
        fileManager: FileManager = .default,
        startupDiagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        self.archive = archive
        self.contentRuleListStore = contentRuleListStore
        self.fileManager = fileManager
        #if DEBUG
            self.startupDiagnostics = startupDiagnostics ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        #else
            _ = startupDiagnostics
        #endif
    }

    func removeUnrecoverableGenerations() async -> AdblockGenerationCleanupReport {
        var report = AdblockGenerationCleanupReport()
        do {
            try Task.checkCancellation()
            guard let activeManifest = try await archive.activeManifest() else { return report }
            var preservedGenerationIds = Set([activeManifest.activeGenerationId])
            var preservedIdentifiers = Set(activeManifest.webKitRuleListIdentifiers)
            if let previousGenerationId = activeManifest.previousGenerationId {
                preservedGenerationIds.insert(previousGenerationId)
                if let previousManifest = try await archive.archivedManifest(generationId: previousGenerationId) {
                    preservedIdentifiers.formUnion(previousManifest.webKitRuleListIdentifiers)
                } else {
                    report.diagnostics.append(
                        "Previous Adblock generation \(previousGenerationId) is referenced but has no archived manifest"
                    )
                }
            }

            let identifiers = await contentRuleListStore.availableContentRuleListIdentifiers()
            for identifier in identifiers
                where Self.isGeneratedIdentifier(identifier) && !preservedIdentifiers.contains(identifier) {
                try Task.checkCancellation()
                do {
                    try await contentRuleListStore.removeContentRuleList(forIdentifier: identifier)
                    report.removedWebKitIdentifiers.append(identifier)
                    #if DEBUG
                        startupDiagnostics.recordCompiledRuleListRemoval(
                            identifiers: [identifier],
                            reason: "Adblock retention removed an unrecoverable WebKit rule list"
                        )
                    #endif
                } catch {
                    report.diagnostics.append(
                        "Failed to remove WebKit rule list \(identifier): \(error.localizedDescription)"
                    )
                }
            }

            for generationId in try await archive.archivedGenerationIds()
                where !preservedGenerationIds.contains(generationId) {
                try Task.checkCancellation()
                let url = try await archive.generationDirectoryURL(generationId: generationId)
                removeItemIfInsideArchive(url, report: &report)
            }

            let stagingRoot = await archive.stagingDirectoryURL()
            if fileManager.fileExists(atPath: stagingRoot.path) {
                for url in try fileManager.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil) {
                    try Task.checkCancellation()
                    removeItemIfInsideArchive(url, report: &report)
                }
            }
        } catch {
            report.diagnostics.append("Adblock retention failed before deletion: \(error.localizedDescription)")
        }
        report.removedWebKitIdentifiers.sort()
        report.removedFilePaths.sort()
        return report
    }

    private func removeItemIfInsideArchive(
        _ url: URL,
        report: inout AdblockGenerationCleanupReport
    ) {
        let root = archive.storageRoot.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        guard candidate.hasPrefix(root + "/"), fileManager.fileExists(atPath: candidate) else { return }
        do {
            try fileManager.removeItem(at: url)
            report.removedFilePaths.append(url.path)
        } catch {
            report.diagnostics.append("Failed to remove \(url.path): \(error.localizedDescription)")
        }
    }

    private static func isGeneratedIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
            || identifier.hasPrefix("sumi.tracking.network.")
    }
}
