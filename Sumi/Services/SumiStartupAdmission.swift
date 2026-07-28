import Foundation

enum SumiStartupAdmission {
    case ready
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
            let hasProfileRetirement =
                profileReferenceAdmission.records().isEmpty == false
                || profileReferenceAdmission.quarantinedRetirements.isEmpty
                    == false
            let hasImportRecovery = try importJournal.hasPendingRecovery()
            return hasProfileRetirement || hasImportRecovery
                ? .recoveryRequired
                : .ready
        } catch {
            return .failed(
                message: "Sumi could not inspect startup recovery state. "
                    + error.localizedDescription
            )
        }
    }
}
