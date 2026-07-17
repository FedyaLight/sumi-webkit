import Foundation
import Observation

@MainActor
@Observable
final class SumiStartupRecoveryTransaction {
    enum State {
        case pending
        case recovering
        case ready
        case failed(message: String, backupURL: URL?)
    }

    struct Failure {
        let message: String
        let backupURL: URL?
    }

    enum Outcome {
        case notClaimed
        case recovered(SumiImportRecoveryReport?)
        case failed(Failure)
    }

    private(set) var state = State.pending

    func recoverIfNeeded(
        preflight: ProfileRetirementStartupPreflightStatus,
        recoverProfileRetirement: @MainActor () async throws -> Void,
        recoverImport: @MainActor () async throws -> SumiImportRecoveryReport?,
        startRuntime: @MainActor () -> Void
    ) async -> Outcome {
        guard case .pending = state else { return .notClaimed }
        state = .recovering

        guard preflight == .ready else {
            let failure = Failure(
                message: preflight.failureMessage
                    ?? "Profile deletion recovery is unavailable.",
                backupURL: nil
            )
            state = .failed(
                message: failure.message,
                backupURL: failure.backupURL
            )
            return .failed(failure)
        }

        do {
            try await recoverProfileRetirement()
            let report = try await recoverImport()
            startRuntime()
            state = .ready
            return .recovered(report)
        } catch {
            let failure = Failure(
                message: error.localizedDescription,
                backupURL: (error as? SumiImportTransactionError)?
                    .preRestoreBackupURL
            )
            state = .failed(
                message: failure.message,
                backupURL: failure.backupURL
            )
            return .failed(failure)
        }
    }
}
