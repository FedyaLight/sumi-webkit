import Foundation

actor AdblockGenerationRecovery {
    private let archive: AdblockGenerationArchive
    private let publisher: any AdblockRuleListPublishing
    private let contentRuleListStore: any SumiContentRuleListCompiling
    #if DEBUG
        private let startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    init(
        archive: AdblockGenerationArchive,
        publisher: any AdblockRuleListPublishing,
        contentRuleListStore: any SumiContentRuleListCompiling,
        startupDiagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        self.archive = archive
        self.publisher = publisher
        self.contentRuleListStore = contentRuleListStore
        #if DEBUG
            self.startupDiagnostics = startupDiagnostics ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        #else
            _ = startupDiagnostics
        #endif
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
                #if DEBUG
                    startupDiagnostics.recordGenerationStaleCheck(
                        consideredStale: false,
                        reason: "Active generation WebKit smoke lookup succeeded"
                    )
                #endif
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
                #if DEBUG
                    startupDiagnostics.recordGenerationStaleCheck(
                        consideredStale: true,
                        reason: "Active generation smoke lookup failed; no previous generation is available"
                    )
                #endif
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active generation smoke lookup failed; no previous generation is available"]
                )
            }

            let previousMissingIdentifiers = await missingIdentifiers(in: previousManifest)
            guard previousMissingIdentifiers.isEmpty else {
                #if DEBUG
                    startupDiagnostics.recordGenerationStaleCheck(
                        consideredStale: true,
                        reason: "Active and previous Adblock generations failed smoke lookup"
                    )
                #endif
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

            #if DEBUG
                let reason = "Active generation smoke lookup failed; restored \(previousManifest.activeGenerationId) after missing identifiers: \(activeMissingIdentifiers.joined(separator: ","))"
                startupDiagnostics.recordGenerationStaleCheck(consideredStale: true, reason: reason)
                startupDiagnostics.recordFallback(reason: reason)
                startupDiagnostics.recordPayloadBackedRestoreUsed(reason: reason)
                startupDiagnostics.recordRepairCompileUsed(reason: reason)
            #endif
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
            #if DEBUG
                startupDiagnostics.recordLookupAttempt(identifiers: [identifier])
            #endif
            if await contentRuleListStore.canLookUpContentRuleList(forIdentifier: identifier) {
                #if DEBUG
                    startupDiagnostics.recordLookupHit(identifier)
                #endif
            } else {
                missing.append(identifier)
                #if DEBUG
                    startupDiagnostics.recordLookupMiss(identifier)
                #endif
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
