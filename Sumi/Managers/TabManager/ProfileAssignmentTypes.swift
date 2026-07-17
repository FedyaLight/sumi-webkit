import Foundation
import SumiWebRuntime
import WebKit

enum ProfileTransitionRejectionReason: Equatable {
    case stale
    case failed
}

enum TabProfileAssignmentExecutionOutcome: Equatable {
    case committed
    case deferred
    case stale
    case failed

    var wasAccepted: Bool {
        self == .committed || self == .deferred
    }

    var immediateSettlement: ProfileTransitionSettlement? {
        switch self {
        case .committed:
            return .committed
        case .stale:
            return .rejected(.stale)
        case .failed:
            return .rejected(.failed)
        case .deferred:
            return nil
        }
    }
}

enum PreparedProfileAssignmentBatchTransitionOutcome: Equatable {
    case committed
    case pipelineOwned
    case rejectedUnstaged(ProfileTransitionRejectionReason)
    case rejectedSettled
    case conflicted

    var wasAccepted: Bool {
        self == .committed || self == .pipelineOwned
    }
}

/// Exact, mutation-free input for one profile replacement. The assignment
/// intent is created only after the repository admits its aggregate model.
@MainActor
struct PreparedTabProfileAssignment {
    let tab: Tab
    let sourceProfileID: UUID?
    let profileWitness: TabRuntimeProfileAssignmentWitness
    let sourceRevision: UInt64
    let desiredProfileID: UUID?
    let runtimeFallback: TabRuntimeFallbackProfileWitness?
    let navigationIntent: TabMainFrameNavigationIntent
    let sourceWebView: WKWebView?
    let sourceSessionGeneration: UInt64
    let sourceSessionWebViews: [WKWebView]
    let targetURL: URL

    var sourceResolvedProfileID: UUID { profileWitness.sourceProfile.id }
    var targetProfile: Profile { profileWitness.targetProfile }

    var requiresPhysicalReplacement: Bool {
        sourceResolvedProfileID != targetProfile.id
    }

    func isCurrent() -> Bool {
        tab.profileId == sourceProfileID
            && tab.profileAssignment.changeRevision == sourceRevision
            && tab.profileAssignment.hasUnsettledAssignment == false
            && profileWitness.isCurrent()
            && runtimeFallbackIsCurrent()
    }

    func runtimeFallbackIsCurrent() -> Bool {
        runtimeFallback?.isCurrent() ?? true
    }

    func physicalNavigationIsCurrent() -> Bool {
        requiresPhysicalReplacement == false
            || (tab.mainFrameLoads.isCurrent(navigationIntent)
                && (sourceWebView.map { $0.url == targetURL }
                    ?? (tab.url == targetURL)))
    }

    func physicalEvidenceIsCurrent(
        in snapshot: WebViewSessionSnapshot
    ) -> Bool {
        guard requiresPhysicalReplacement,
              isCurrent(),
              physicalNavigationIsCurrent(),
              snapshot.generation == sourceSessionGeneration,
              snapshot.allKnownWebViews.count == sourceSessionWebViews.count
        else { return false }
        let current = Set(snapshot.allKnownWebViews.map(ObjectIdentifier.init))
        let expected = Set(sourceSessionWebViews.map(ObjectIdentifier.init))
        return current == expected
    }
}

struct TabSpaceProfileTransitionPreparation: Equatable {
    let tabID: UUID
    let sourceSpaceID: UUID?
    let targetSpaceID: UUID?
    let sourceProfileID: UUID?
    let sourceAssignmentRevision: UInt64
    let pinnedProfileID: UUID
}

enum TabSpaceProfileTransitionPreparationOutcome: Equatable {
    case unnecessary
    case prepared(TabSpaceProfileTransitionPreparation)
    case rejected
}

enum TabSpaceProfileResolution: Equatable {
    case unchanged
    case transition(current: UUID, target: UUID)
    case unavailable
}
