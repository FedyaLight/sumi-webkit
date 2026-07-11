import Foundation
import SumiWebRuntime

/// One exact Space/profile model transaction. It retains pending and staged
/// state until the shared WebView replacement pipeline reports settlement.
@MainActor
final class SpaceProfileTransaction {
    struct Runtime {
        let profileID: (UUID) -> UUID?
        let assignProfile: (UUID, UUID?) -> Bool
        let tab: (UUID) -> Tab?
        let isTabInSpace: (UUID, UUID) -> Bool
        let sendObjectWillChange: () -> Void
    }

    enum State: Equatable {
        case pending
        case staged
        case terminal
    }

    let intent: DeferredWebViewSpaceProfileAssignmentIntent
    private let runtime: Runtime
    private(set) var state: State = .pending

    init(
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        runtime: Runtime
    ) {
        self.intent = intent
        self.runtime = runtime
    }

    var desiredProfileID: UUID { intent.desiredProfileID }

    func isCurrentPending(revision: UInt64) -> Bool {
        guard state == .pending,
              revision == intent.revision,
              runtime.profileID(intent.spaceID) == intent.expectedProfileID else {
            return false
        }
        return intent.tabIntents.allSatisfy { tabIntent in
            guard runtime.isTabInSpace(tabIntent.tabID, intent.spaceID) else {
                return false
            }
            return runtime.tab(tabIntent.tabID)?
                .isCurrentProfileAssignmentIntent(tabIntent.intent) == true
        }
    }

    @discardableResult
    func stage(revision: UInt64) -> Bool {
        guard isCurrentPending(revision: revision) else { return false }
        runtime.sendObjectWillChange()
        guard runtime.assignProfile(intent.spaceID, intent.desiredProfileID) else {
            return false
        }
        for tabIntent in intent.tabIntents {
            guard let tab = runtime.tab(tabIntent.tabID) else {
                preconditionFailure("Space profile transaction lost an affected Tab")
            }
            precondition(
                tab.stageProfileAssignmentIntent(tabIntent.intent),
                "Space profile transaction changed during repository admission"
            )
        }
        state = .staged
        return true
    }

    func finish() {
        precondition(state == .staged)
        precondition(runtime.profileID(intent.spaceID) == intent.desiredProfileID)
        for tabIntent in intent.tabIntents {
            guard let tab = runtime.tab(tabIntent.tabID) else {
                preconditionFailure("Space profile transaction lost an affected Tab")
            }
            precondition(
                tab.finishStagedProfileAssignmentIntent(tabIntent.intent),
                "Space profile transaction lost a staged Tab intent"
            )
        }
        state = .terminal
    }

    func rollback() {
        precondition(state == .staged)
        runtime.sendObjectWillChange()
        precondition(
            runtime.assignProfile(intent.spaceID, intent.expectedProfileID),
            "Space profile rollback lost its Space"
        )
        for tabIntent in intent.tabIntents {
            guard let tab = runtime.tab(tabIntent.tabID) else {
                preconditionFailure("Space profile rollback lost an affected Tab")
            }
            precondition(
                tab.rollbackStagedProfileAssignmentIntent(tabIntent.intent),
                "Space profile rollback lost a staged Tab intent"
            )
        }
        state = .terminal
    }

    func abortPending() {
        guard state == .pending else { return }
        for tabIntent in intent.tabIntents {
            runtime.tab(tabIntent.tabID)?.abortProfileAssignmentIntent(
                tabIntent.intent
            )
        }
        state = .terminal
    }
}
