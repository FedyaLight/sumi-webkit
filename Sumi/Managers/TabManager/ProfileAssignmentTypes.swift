import Foundation

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

struct TabSpaceProfileTransitionPreparation: Equatable {
    let tabID: UUID
    let sourceSpaceID: UUID?
    let targetSpaceID: UUID?
    let pinnedProfileID: UUID
}
