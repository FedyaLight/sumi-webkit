import Foundation

@MainActor
final class PreparedRegularTabPlacement {
    enum State {
        case prepared
        case staged
        case committed
        case cancelled
        case abandoned
    }

    struct SourceSnapshot {
        let spaceID: UUID?
        let profileID: UUID?
        let assignmentRevision: UInt64
        let index: Int
        let isPinned: Bool
        let isSpacePinned: Bool
        let folderID: UUID?
    }

    struct TargetSnapshot {
        let spaceID: UUID
        let index: Int?
        let tabs: [Tab]
    }

    private unowned let transaction: RegularTabPlacementTransaction
    let tab: Tab
    let source: SourceSnapshot
    let target: TargetSnapshot
    let admission: PreparedRegularTabPlacementAdmission
    var stagedTargetTabs: [Tab]?
    var state = State.prepared

    init(
        transaction: RegularTabPlacementTransaction,
        tab: Tab,
        source: SourceSnapshot,
        target: TargetSnapshot,
        admission: PreparedRegularTabPlacementAdmission
    ) {
        self.transaction = transaction
        self.tab = tab
        self.source = source
        self.target = target
        self.admission = admission
    }

    func belongs(to transaction: RegularTabPlacementTransaction) -> Bool {
        self.transaction === transaction
    }

    func commit() -> Bool {
        guard transaction.stage(self) else { return false }
        guard transaction.finish(self, publishing: {}) else {
            _ = transaction.rollback(self)
            return false
        }
        return true
    }

    func stage() -> Bool {
        transaction.stage(self)
    }

    func finish(
        publishing publication: @MainActor () -> Void = {}
    ) -> Bool {
        transaction.finish(self, publishing: publication)
    }

    @discardableResult
    func rollback() -> Bool {
        transaction.rollback(self)
    }

    @discardableResult
    func cancel() -> Bool {
        transaction.cancel(self)
    }

    static func stageAggregate(
        _ placements: [PreparedRegularTabPlacement]
    ) -> Bool {
        guard let transaction = placements.first?.transaction else {
            return false
        }
        return transaction.stageAggregate(placements)
    }

    static func finishAggregate(
        _ placements: [PreparedRegularTabPlacement],
        publishing publication: @MainActor () -> Void
    ) -> Bool {
        guard let transaction = placements.first?.transaction else {
            return false
        }
        return transaction.finishAggregate(
            placements,
            publishing: publication
        )
    }

    static func cancelAggregate(
        _ placements: [PreparedRegularTabPlacement]
    ) -> Bool {
        guard let transaction = placements.first?.transaction else {
            return placements.isEmpty
        }
        return transaction.cancelAggregate(placements)
    }

    static func rollbackAggregate(
        _ placements: [PreparedRegularTabPlacement]
    ) -> Bool {
        guard let transaction = placements.first?.transaction else {
            return false
        }
        return transaction.rollbackAggregate(placements)
    }
}
