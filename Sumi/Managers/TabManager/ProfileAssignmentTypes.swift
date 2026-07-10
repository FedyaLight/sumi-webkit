import Foundation

enum TabProfileAssignmentExecutionOutcome: Equatable {
    case committed
    case deferred
    case stale
    case failed

    var wasAccepted: Bool {
        self == .committed || self == .deferred
    }
}

struct TabSpaceProfileTransitionPreparation: Equatable {
    let tabID: UUID
    let sourceSpaceID: UUID?
    let targetSpaceID: UUID?
    let pinnedProfileID: UUID
}
