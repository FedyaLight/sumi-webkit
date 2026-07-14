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
    let windowCommitPolicy: ShortcutRetirementWindowCommitPolicy
    var result: ShortcutLiveTabRetirementResult

    init(
        tabs: [Tab],
        runtime: RuntimePortRegistry?,
        runtimeTeardown: PreparedTabRuntimeTeardown? = nil,
        windowCommitPolicy: ShortcutRetirementWindowCommitPolicy = .callerOwned,
        result: ShortcutLiveTabRetirementResult
    ) {
        precondition(tabs.isEmpty || runtime != nil)
        self.tabs = tabs
        self.runtime = runtime
        self.runtimeTeardown = runtimeTeardown
        self.windowCommitPolicy = windowCommitPolicy
        self.result = result
    }
}
