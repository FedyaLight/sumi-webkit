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
        case recovered(
            importReport: SumiImportRecoveryReport?,
            profileRetirement: ProfileRetirementStartupRecoveryReport
        )
        case failed(Failure)
    }

    private(set) var state: State

    init(state: State = .pending) {
        self.state = state
    }

    func recoverIfNeeded(
        preflight: ProfileRetirementStartupPreflightStatus,
        recoverProfileRetirement: @MainActor () async throws
            -> ProfileRetirementStartupRecoveryReport,
        recoverImport: @MainActor () async throws -> SumiImportRecoveryReport?,
        hasSafeProfile: @MainActor () -> Bool = { true },
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
            let profileRetirementReport = try await recoverProfileRetirement()
            guard hasSafeProfile() else {
                throw SumiStartupRecoveryError.noSafeProfile
            }
            let importReport = try await recoverImport()
            startRuntime()
            state = .ready
            return .recovered(
                importReport: importReport,
                profileRetirement: profileRetirementReport
            )
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

private enum SumiStartupRecoveryError: LocalizedError {
    case noSafeProfile

    var errorDescription: String? {
        "Sumi could not find a safe profile after isolating pending profile deletion."
    }
}
