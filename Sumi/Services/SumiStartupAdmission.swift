import Foundation

enum SumiStartupAdmission {
    case ready(completedRetirements: [ProfileRetirementRecord])
    case recoveryRequired
    case failed(message: String)

    @MainActor
    static func evaluate(
        preflight: ProfileRetirementStartupPreflightStatus,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        importJournal: SumiImportTransactionDatabaseJournal
    ) -> SumiStartupAdmission {
        guard preflight == .ready else {
            return .failed(
                message: preflight.failureMessage
                    ?? "Profile deletion recovery is unavailable."
            )
        }

        do {
            let retirementRecords = profileReferenceAdmission.records()
            let hasQuarantinedRetirement =
                profileReferenceAdmission.quarantinedRetirements.isEmpty
                    == false
            let hasProfileRetirementRecovery = retirementRecords.contains {
                $0.isCompletedTombstone == false
            } || hasQuarantinedRetirement
            let hasImportRecovery = try importJournal.hasPendingRecovery()
            if hasProfileRetirementRecovery || hasImportRecovery {
                return .recoveryRequired
            }
            return .ready(
                completedRetirements: retirementRecords.filter(
                    \.isCompletedTombstone
                )
            )
        } catch {
            return .failed(
                message: "Sumi could not inspect startup recovery state. "
                    + error.localizedDescription
            )
        }
    }
}
