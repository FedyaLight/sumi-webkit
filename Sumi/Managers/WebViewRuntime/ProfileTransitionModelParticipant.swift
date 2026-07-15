import Foundation
import SumiWebRuntime

@MainActor
private enum ProfileTransitionModelError: Error {
    case stale
}

/// Exact model transaction for one Tab profile-assignment intent.
@MainActor
final class TabProfileAssignmentModelTransaction:
    WebViewReplacementModelTransaction {
    private enum State: Equatable {
        case prepared, staged, claimed, rolledBack, drained
    }

    private let tab: Tab
    private let targetProfileID: UUID
    private let intent: DeferredWebViewProfileAssignmentIntent
    private var state = State.prepared

    init(
        tab: Tab,
        targetProfileID: UUID,
        intent: DeferredWebViewProfileAssignmentIntent
    ) {
        self.tab = tab
        self.targetProfileID = targetProfileID
        self.intent = intent
    }

    func validateForStaging() -> Bool {
        state == .prepared
            && intent.resolvedProfileID == targetProfileID
            && tab.profileAssignment.isCurrent(intent)
            && navigationIsCurrent()
    }

    func stage() throws {
        guard tab.profileAssignment.stage(intent) else {
            throw ProfileTransitionModelError.stale
        }
        state = .staged
    }

    func retainsModelAfterFailedStage() -> Bool { false }

    func stagedModelIsExact() -> Bool {
        state == .staged
            && tab.profileAssignment.isCurrentStaged(intent)
            && navigationIsCurrent()
    }

    func canClaimTerminalModel() -> Bool {
        tab.profileAssignment.isCurrentStaged(intent)
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard tab.profileAssignment.finish(intent) else {
            return .terminallyDrained
        }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        state == .claimed
            && tab.profileAssignment.isCurrentFinished(intent)
            && navigationIsCurrent()
    }

    func publishCommit() {}

    func rollback() throws {
        guard tab.profileAssignment.rollback(intent) else {
            throw ProfileTransitionModelError.stale
        }
        state = .rolledBack
    }

    func publishRollback() {}

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .prepared, .claimed, .rolledBack, .drained:
            return true
        case .staged:
            return tab.profileAssignment.canSettleTerminalDrain(intent)
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        if case .staged = state {
            precondition(tab.profileAssignment.settleTerminalDrain(intent))
        }
        state = .drained
        return true
    }

    private func navigationIsCurrent() -> Bool {
        let current = tab.mainFrameLoads.currentIntent
        return current.revision == intent.navigationRevision
            && current.targetURL == intent.targetURL
    }
}

/// Begins and stages one previously witnessed assignment only after the
/// WebView repository accepts the complete replacement batch.
@MainActor
final class PreparedTabProfileAssignmentModelTransaction:
    WebViewReplacementModelTransaction {
    private enum State: Equatable {
        case prepared, staged, claimed, rolledBack, drained
    }

    private let assignment: PreparedTabProfileAssignment
    private var intent: DeferredWebViewProfileAssignmentIntent?
    private var state = State.prepared

    init(_ assignment: PreparedTabProfileAssignment) {
        self.assignment = assignment
    }

    func validateForStaging() -> Bool {
        state == .prepared
            && intent == nil
            && assignment.isCurrent()
            && assignment.physicalNavigationIsCurrent()
    }

    func stage() throws {
        guard validateForStaging() else {
            throw ProfileTransitionModelError.stale
        }
        let intent = assignment.tab.profileAssignment.begin(
            desiredProfileID: assignment.desiredProfileID,
            resolvedProfileID: assignment.targetProfile.id,
            targetURL: assignment.targetURL,
            navigationRevision: assignment.navigationIntent.revision,
            requiresStructuralPersistence: false
        )
        guard assignment.tab.profileAssignment.stage(intent) else {
            assignment.tab.profileAssignment.abort(intent)
            throw ProfileTransitionModelError.stale
        }
        self.intent = intent
        state = .staged
    }

    func retainsModelAfterFailedStage() -> Bool { false }

    func stagedModelIsExact() -> Bool {
        guard state == .staged, let intent else { return false }
        return assignment.tab.profileAssignment.isCurrentStaged(intent)
            && assignment.profileWitness.isCurrent()
            && assignment.runtimeFallbackIsCurrent()
            && assignment.physicalNavigationIsCurrent()
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard let intent,
              assignment.tab.profileAssignment.finish(intent) else {
            return .terminallyDrained
        }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard state == .claimed, let intent else { return false }
        return assignment.tab.profileAssignment.isCurrentFinished(intent)
            && assignment.profileWitness.isCurrent()
            && assignment.runtimeFallbackIsCurrent()
            && assignment.physicalNavigationIsCurrent()
    }

    func publishCommit() {}

    func rollback() throws {
        guard let intent,
              assignment.tab.profileAssignment.rollback(intent) else {
            throw ProfileTransitionModelError.stale
        }
        state = .rolledBack
    }

    func publishRollback() {}

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .prepared, .claimed, .rolledBack, .drained:
            return true
        case .staged:
            guard let intent else { return false }
            return assignment.tab.profileAssignment
                .canSettleTerminalDrain(intent)
        }
    }

    func settleTerminalDrain() -> Bool {
        switch state {
        case .prepared, .claimed, .rolledBack, .drained:
            return true
        case .staged:
            guard let intent,
                  assignment.tab.profileAssignment
                    .settleTerminalDrain(intent) else { return false }
            state = .drained
            return true
        }
    }
}

/// Couples heterogeneous profile intents and the caller's unpublished binding
/// model into the repository's single commit/rollback authority.
@MainActor
final class PreparedProfileAssignmentBatchModelTransaction:
    WebViewReplacementModelTransaction {
    private enum State {
        case prepared, staged, claiming, claimed, conflicted, terminal
    }

    private let profiles: [PreparedTabProfileAssignmentModelTransaction]
    private let binding: any ShortcutTabBindingAggregateTransaction
    private let tabs: [Tab]
    private var state = State.prepared

    init(
        assignments: [PreparedTabProfileAssignment],
        binding: any ShortcutTabBindingAggregateTransaction
    ) {
        profiles = assignments.map(
            PreparedTabProfileAssignmentModelTransaction.init
        )
        self.binding = binding
        tabs = assignments.map(\.tab)
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        let bindingTabs = binding.exactBindingTabs.map(ObjectIdentifier.init)
        let profileTabs = tabs.map(ObjectIdentifier.init)
        return Set(bindingTabs).count == bindingTabs.count
            && Set(profileTabs).count == profileTabs.count
            && Set(bindingTabs) == Set(profileTabs)
            && binding.validateForStaging()
            && profiles.allSatisfy { $0.validateForStaging() }
    }

    func stage() throws {
        guard validateForStaging() else {
            throw ProfileTransitionModelError.stale
        }
        var stagedProfiles: [PreparedTabProfileAssignmentModelTransaction] = []
        var didAttemptBindingStage = false
        do {
            for profile in profiles {
                try profile.stage()
                stagedProfiles.append(profile)
            }
            didAttemptBindingStage = true
            try binding.stage()
        } catch {
            if didAttemptBindingStage && binding.retainsModelAfterFailedStage() {
                state = .conflicted
                throw error
            }
            var compensationError: Error?
            if didAttemptBindingStage == false,
               binding.cancelPrepared() == false {
                compensationError = ProfileTransitionModelError.stale
            }
            for profile in stagedProfiles.reversed() {
                do { try profile.rollback() } catch {
                    compensationError = compensationError ?? error
                }
            }
            if let compensationError {
                state = .conflicted
                throw compensationError
            }
            throw error
        }
        state = .staged
        guard stagedModelIsExact() else {
            try rollback()
            throw ProfileTransitionModelError.stale
        }
        tabs.forEach { _ = $0.webViewRebuildEpoch.advance() }
    }

    func retainsModelAfterFailedStage() -> Bool {
        if case .conflicted = state { return true }
        return false
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return binding.stagedModelIsExact()
            && profiles.allSatisfy { $0.stagedModelIsExact() }
    }

    func canClaimTerminalModel() -> Bool {
        binding.canClaimTerminalModel()
            && profiles.allSatisfy { $0.canClaimTerminalModel() }
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel() else { return .terminallyDrained }
        state = .claiming
        guard binding.claimTerminalModel() == .sealed else {
            if case .claiming = state {
                _ = settleTerminalDrain()
            }
            return .terminallyDrained
        }
        guard case .claiming = state else { return .terminallyDrained }
        for profile in profiles {
            precondition(
                profile.claimTerminalModel() == .sealed,
                "Validated profile assignment lost terminal authority"
            )
        }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return binding.claimedModelIsExact()
            && profiles.allSatisfy { $0.claimedModelIsExact() }
    }

    func publishCommit() {
        guard case .claimed = state else {
            preconditionFailure("Prepared profile batch was not claimed")
        }
        profiles.forEach { $0.publishCommit() }
        binding.publishCommit()
        state = .terminal
    }

    func rollback() throws {
        guard case .staged = state else {
            throw ProfileTransitionModelError.stale
        }
        var compensationError: Error?
        do { try binding.rollback() } catch {
            compensationError = compensationError ?? error
        }
        for profile in profiles.reversed() {
            do { try profile.rollback() } catch {
                compensationError = compensationError ?? error
            }
        }
        state = compensationError == nil ? .terminal : .conflicted
        if let compensationError { throw compensationError }
    }

    func publishRollback() {
        binding.publishRollback()
        profiles.forEach { $0.publishRollback() }
    }

    func settleTerminalDrain() -> Bool {
        if case .terminal = state { return true }
        guard canSettleTerminalDrain() else { return false }
        for profile in profiles {
            precondition(
                profile.settleTerminalDrain(),
                "Validated profile assignment lost terminal-drain authority"
            )
        }
        precondition(binding.settleTerminalDrain())
        state = .terminal
        return true
    }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .terminal:
            return true
        case .conflicted:
            return false
        case .prepared, .staged, .claiming, .claimed:
            return binding.canSettleTerminalDrain()
                && profiles.allSatisfy { $0.canSettleTerminalDrain() }
        }
    }
}

/// Couples profile model staging to the rebuild-epoch authority for the exact
/// Tab set whose WebView generation is being replaced.
@MainActor
final class ProfileTransitionModelParticipant:
    WebViewReplacementModelTransaction {
    private let model: any WebViewReplacementModelTransaction
    private let tabs: [Tab]

    init(
        model: any WebViewReplacementModelTransaction,
        tabs: [Tab]
    ) {
        self.model = model
        self.tabs = tabs
    }

    func validateForStaging() -> Bool { model.validateForStaging() }

    func stage() throws {
        try model.stage()
        guard model.stagedModelIsExact() else {
            do {
                try model.rollback()
                model.publishRollback()
            } catch {
                throw error
            }
            throw ProfileTransitionModelError.stale
        }
        tabs.forEach { _ = $0.webViewRebuildEpoch.advance() }
    }

    func retainsModelAfterFailedStage() -> Bool {
        model.retainsModelAfterFailedStage()
    }

    func stagedModelIsExact() -> Bool { model.stagedModelIsExact() }

    func canClaimTerminalModel() -> Bool {
        model.canClaimTerminalModel()
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        model.claimTerminalModel()
    }

    func claimedModelIsExact() -> Bool { model.claimedModelIsExact() }

    func publishCommit() { model.publishCommit() }
    func rollback() throws { try model.rollback() }
    func publishRollback() { model.publishRollback() }
    func canSettleTerminalDrain() -> Bool {
        model.canSettleTerminalDrain()
    }
    func settleTerminalDrain() -> Bool { model.settleTerminalDrain() }
}
