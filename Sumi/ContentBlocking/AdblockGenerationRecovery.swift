import Foundation

actor AdblockGenerationRecovery {
    private let archive: AdblockGenerationArchive
    private let publisher: any AdblockRuleListPublishing
    private let contentRuleListStore: any SumiContentRuleListCompiling
    init(
        archive: AdblockGenerationArchive,
        publisher: any AdblockRuleListPublishing,
        contentRuleListStore: any SumiContentRuleListCompiling
    ) {
        self.archive = archive
        self.publisher = publisher
        self.contentRuleListStore = contentRuleListStore
    }

    func restorePreviousGenerationIfNeeded() async -> AdblockGenerationRollbackReport {
        do {
            try Task.checkCancellation()
            guard let activeManifest = try await archive.activeManifest() else {
                return report(diagnostics: ["No active Adblock manifest"])
            }
            try Task.checkCancellation()
            let activeMissingIdentifiers = await missingIdentifiers(in: activeManifest)
            guard !activeMissingIdentifiers.isEmpty else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: []
                )
            }
            guard let previousGenerationId = activeManifest.previousGenerationId,
                  let previousManifest = try await archive.archivedManifest(generationId: previousGenerationId)
            else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active generation smoke lookup failed; no previous generation is available"]
                )
            }

            let previousMissingIdentifiers = await missingIdentifiers(in: previousManifest)
            guard previousMissingIdentifiers.isEmpty else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active and previous Adblock generations failed smoke lookup"]
                )
            }

            let previousDefinitions = try await archive.compiledShardDefinitions(for: previousManifest)
            let publication = try await publisher.preparePublication(
                manifest: previousManifest,
                definitions: previousDefinitions
            )
            try Task.checkCancellation()

            // The disk pointer changes only after WebKit has prepared a complete replacement.
            // commitPublication is synchronous and non-throwing, so no fallible step remains
            // after this durable switch.
            try await archive.replaceActiveManifest(previousManifest)
            await publisher.commitPublication(publication)

            return AdblockGenerationRollbackReport(
                rolledBack: true,
                activeGenerationId: activeManifest.activeGenerationId,
                restoredGenerationId: previousManifest.activeGenerationId,
                diagnostics: ["Rolled back after missing identifiers: \(activeMissingIdentifiers.joined(separator: ","))"]
            )
        } catch {
            return report(diagnostics: ["Rollback smoke check failed: \(error.localizedDescription)"])
        }
    }

    private func missingIdentifiers(in manifest: AdblockCompiledGenerationManifest) async -> [String] {
        var missing = [String]()
        for identifier in manifest.webKitRuleListIdentifiers {
            guard !Task.isCancelled else { return manifest.webKitRuleListIdentifiers }
            if await contentRuleListStore.canLookUpContentRuleList(
                forIdentifier: identifier
            ) == false {
                missing.append(identifier)
            }
        }
        return missing
    }

    private func report(diagnostics: [String]) -> AdblockGenerationRollbackReport {
        AdblockGenerationRollbackReport(
            rolledBack: false,
            activeGenerationId: nil,
            restoredGenerationId: nil,
            diagnostics: diagnostics
        )
    }
}
