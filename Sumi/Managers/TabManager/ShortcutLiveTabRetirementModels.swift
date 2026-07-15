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

@MainActor
enum ShortcutRetirementWindowCommitPolicy {
    /// A browser workflow chooses the final visual/selection state and performs
    /// the one durable window-session write after retirement.
    case callerOwned
    /// Structural deletion/generic removal owns validation and persistence.
    case retirementService
}

@MainActor
struct PreparedShortcutLiveTabRetirement {
    let tabs: [Tab]
    let runtime: RuntimePortRegistry?
    let runtimeTeardown: PreparedTabRuntimeTeardown?
    let committedRuntimeRetirement: CommittedTabRuntimeRetirementCleanupOwnership?
    let terminallyDrainedTabIDs: Set<UUID>
    let runtimeAttachment: TabRuntimeAttachmentWitness?
    let terminalEffect: PreparedShortcutLiveTabRetirementTerminalEffect?
    let windowCommitPolicy: ShortcutRetirementWindowCommitPolicy
    var result: ShortcutLiveTabRetirementResult

    init(
        tabs: [Tab],
        runtime: RuntimePortRegistry?,
        runtimeTeardown: PreparedTabRuntimeTeardown? = nil,
        committedRuntimeRetirement: CommittedTabRuntimeRetirementCleanupOwnership? = nil,
        terminallyDrainedTabIDs: Set<UUID> = [],
        runtimeAttachment: TabRuntimeAttachmentWitness? = nil,
        terminalEffect: PreparedShortcutLiveTabRetirementTerminalEffect? = nil,
        windowCommitPolicy: ShortcutRetirementWindowCommitPolicy = .callerOwned,
        result: ShortcutLiveTabRetirementResult
    ) {
        precondition(tabs.isEmpty || runtime != nil)
        precondition(
            runtimeTeardown == nil || committedRuntimeRetirement == nil,
            "Shortcut retirement cannot own two terminal runtime effects"
        )
        self.tabs = tabs
        self.runtime = runtime
        self.runtimeTeardown = runtimeTeardown
        self.committedRuntimeRetirement = committedRuntimeRetirement
        self.terminallyDrainedTabIDs = terminallyDrainedTabIDs
        self.runtimeAttachment = runtimeAttachment
        self.terminalEffect = terminalEffect
        self.windowCommitPolicy = windowCommitPolicy
        self.result = result
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
