import SumiWebRuntime

@MainActor
enum ProfileTransitionModelOnlyOutcome {
    case committed
    case rejectedStale
    case rolledBackCommitValidation
    case terminalShutdown
    case conflicted

    var settlement: ProfileTransitionSettlement {
        switch self {
        case .committed:
            return .committed
        case .rejectedStale:
            return .rejected(.stale)
        case .rolledBackCommitValidation:
            return .rolledBack(.commitValidationFailed)
        case .terminalShutdown:
            return .terminalShutdown
        case .conflicted:
            return .conflicted
        }
    }

    var tabExecution: TabProfileAssignmentExecutionOutcome {
        switch self {
        case .committed:
            return .committed
        case .rejectedStale:
            return .stale
        case .rolledBackCommitValidation, .terminalShutdown, .conflicted:
            return .failed
        }
    }

    var batchExecution: PreparedProfileAssignmentBatchTransitionOutcome {
        switch self {
        case .committed:
            return .committed
        case .rejectedStale, .rolledBackCommitValidation, .terminalShutdown:
            return .rejectedSettled
        case .conflicted:
            return .conflicted
        }
    }
}

@MainActor
enum ProfileTransitionModelOnlySettlement {
    static func execute(
        _ model: WebViewReplacementModelParticipant
    ) -> ProfileTransitionModelOnlyOutcome {
        do {
            try model.stage()
        } catch {
            return model.retainsModelAfterFailedStage()
                ? .conflicted
                : .rejectedStale
        }
        guard model.stagedModelIsExact() else { return .conflicted }
        guard model.canClaimTerminalModel() else {
            do {
                try model.rollback()
                model.publishRollback()
                return .rolledBackCommitValidation
            } catch {
                return .conflicted
            }
        }
        switch model.claimTerminalModel() {
        case .sealed:
            guard model.claimedModelIsExact() else {
                _ = settleTerminalDrainIfPossible(model)
                return .conflicted
            }
            model.publishCommit()
            return .committed
        case .terminallyDrained:
            return settleTerminalDrainIfPossible(model)
                ? .terminalShutdown
                : .conflicted
        }
    }

    private static func settleTerminalDrainIfPossible(
        _ model: WebViewReplacementModelParticipant
    ) -> Bool {
        model.canSettleTerminalDrain() && model.settleTerminalDrain()
    }
}
