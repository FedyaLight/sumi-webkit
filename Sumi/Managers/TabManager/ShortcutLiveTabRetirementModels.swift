import Foundation

/// Exact outcome of shortcut runtime retirement. A background instance can be
/// retired successfully without clearing the window's current selection.
@MainActor
struct ShortcutLiveTabRetirementResult {
    private(set) var retiredTabIds: [UUID]
    private(set) var didClearCurrentSelection: Bool
    private(set) var windowStatesNeedingPersistence: [BrowserWindowState]

    var didRetire: Bool { retiredTabIds.isEmpty == false }

    init(
        retiredTabIds: [UUID] = [],
        didClearCurrentSelection: Bool = false,
        windowStatesNeedingPersistence: [BrowserWindowState] = []
    ) {
        var seenTabIds = Set<UUID>()
        self.retiredTabIds = retiredTabIds.filter {
            seenTabIds.insert($0).inserted
        }
        var seenWindowIds = Set<UUID>()
        self.windowStatesNeedingPersistence = windowStatesNeedingPersistence
            .filter { seenWindowIds.insert($0.id).inserted }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        self.didClearCurrentSelection = didClearCurrentSelection
    }

    mutating func merge(_ other: Self) {
        self = Self(
            retiredTabIds: retiredTabIds + other.retiredTabIds,
            didClearCurrentSelection: didClearCurrentSelection
                || other.didClearCurrentSelection,
            windowStatesNeedingPersistence: windowStatesNeedingPersistence
                + other.windowStatesNeedingPersistence
        )
    }
}

/// A typed participant that installs window-local shortcut state inside the
/// same observation aggregate as launcher placement. Admission and reversible
/// repository work happen before this point; settlement is infallible once all
/// participants report that their exact evidence remains current.
@MainActor
protocol BrowserWindowShortcutAggregateParticipant: AnyObject {
    func isCurrentForWindowSettlement() -> Bool
    func settleAdmittedWindowModel(
        using owner: BrowserWindowShortcutMutationOwner
    )
    func publishAdmittedModel()
}
