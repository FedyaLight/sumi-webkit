import Foundation

@MainActor
struct ShortcutLiveRetirementBatchWindowEntry {
    let window: BrowserWindowState
    let source: BrowserWindowShortcutMutationState
    let target: BrowserWindowShortcutMutationState
    let requiresPersistence: Bool

    func isCurrent(using attachment: TabRuntimeAttachmentWitness) -> Bool {
        attachment.lease.windowState(for: window.id) === window
            && window.unpublishedShortcutMutationState == source
    }
}

@MainActor
struct ShortcutLiveRetirementBatchPlan {
    let entries: [LiveShortcutTabEntry]
    let residencePlans: [LiveShortcutResidenceMutationStaging.Plan]
    let windows: [ShortcutLiveRetirementBatchWindowEntry]
    let attachment: TabRuntimeAttachmentWitness
    let registry: LiveShortcutTabRegistry
    let splitTopology: SplitGroupReplacementReceipt?
    let result: ShortcutLiveTabRetirementResult

    var tabs: [Tab] { entries.map(\.tab) }
    var runtime: RuntimePortRegistry? { attachment.lease.registry }
    var hasModelEffect: Bool {
        entries.isEmpty == false || windows.isEmpty == false
            || splitTopology != nil
    }

    func sourceIsExact() -> Bool {
        guard attachment.isCurrent(),
              entries.count == residencePlans.count,
              excludesRegularSplitResidences() else { return false }
        let current = registry.mutationSnapshot
        return entries.allSatisfy { expected in
            current.entry(containing: expected.tab)?.isIdentical(to: expected)
                == true
        } && windows.allSatisfy { $0.isCurrent(using: attachment) }
    }

    private func excludesRegularSplitResidences() -> Bool {
        guard let runtime else { return tabs.isEmpty }
        let tabIDs = Set(tabs.map(\.id))
        var overlap = false
        runtime.forEachWindowState { window in
            if tabIDs.isDisjoint(
                with: runtime.visibleSplitTabIds(for: window.id)
            ) == false {
                overlap = true
            }
        }
        return overlap == false
    }
}

@MainActor
enum ShortcutLiveRetirementBatchPreparation {
    case prepared(PreparedShortcutLiveRetirementBatch)
    case noEffect
    case rejected
}

@MainActor
struct PreparedShortcutLiveRetirementBatch {
    let result: ShortcutLiveTabRetirementResult
    private let terminalEffect: ShortcutLiveRetirementBatchTerminalEffect?

    init(
        result: ShortcutLiveTabRetirementResult,
        terminalEffect: ShortcutLiveRetirementBatchTerminalEffect
    ) {
        self.result = result
        self.terminalEffect = terminalEffect
    }

    init(result: ShortcutLiveTabRetirementResult = .init()) {
        self.result = result
        terminalEffect = nil
    }

    func publishTerminalEffects() {
        terminalEffect?.publish()
    }
}
