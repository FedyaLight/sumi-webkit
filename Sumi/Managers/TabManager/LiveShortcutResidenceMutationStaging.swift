import Foundation

/// Prepares exact residence plans and applies them only during model staging.
/// Publication remains a separate terminal operation.
@MainActor
final class LiveShortcutResidenceMutationStaging {
    struct Plan {
        fileprivate enum Operation {
            case registration(LiveShortcutTabEntry)
            case removal(LiveShortcutTabEntry)
            case relocation(
                previous: LiveShortcutTabEntry,
                current: LiveShortcutTabEntry
            )
        }

        fileprivate let operation: Operation
    }

    enum Change {
        case registration(LiveShortcutTabEntry)
        case removal(LiveShortcutTabEntry)
        case relocation(
            previous: LiveShortcutTabEntry,
            current: LiveShortcutTabEntry
        )

        var affectedEntries: [LiveShortcutTabEntry] {
            switch self {
            case .registration(let entry), .removal(let entry):
                return [entry]
            case .relocation(let previous, let current):
                return [previous, current]
            }
        }
    }

    private let storage: LiveShortcutTabResidenceStore
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        storage: LiveShortcutTabResidenceStore,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.storage = storage
        self.structuralLookup = structuralLookup
    }

    func canRelocate(
        _ tab: Tab,
        from sourcePinID: UUID,
        to targetPinID: UUID,
        in windowID: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Bool {
        prepareRelocation(
            tab,
            from: sourcePinID,
            to: targetPinID,
            in: windowID,
            presentationPage: presentationPage
        ) != nil
    }

    func prepareRegistration(
        _ tab: Tab,
        for pinID: UUID,
        in windowID: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Plan? {
        let plan = Plan(operation: .registration(
            LiveShortcutTabEntry(
                windowId: windowID,
                pinId: pinID,
                tab: tab,
                presentationPage: presentationPage
            )
        ))
        return projectedSnapshot(for: [plan]) == nil ? nil : plan
    }

    func prepareRelocation(
        _ tab: Tab,
        from sourcePinID: UUID,
        to targetPinID: UUID,
        in windowID: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Plan? {
        guard let previous = storage.snapshot.entry(containing: tab) else {
            return nil
        }
        let plan = Plan(operation: .relocation(
            previous: previous,
            current: LiveShortcutTabEntry(
                windowId: windowID,
                pinId: targetPinID,
                tab: tab,
                presentationPage: presentationPage
            )
        ))
        guard previous.pinId == sourcePinID,
              previous.windowId == windowID else { return nil }
        return projectedSnapshot(for: [plan]) == nil ? nil : plan
    }

    func prepareRemoval(_ expected: LiveShortcutTabEntry) -> Plan? {
        let plan = Plan(operation: .removal(expected))
        return projectedSnapshot(for: [plan]) == nil ? nil : plan
    }

    func canStage(_ plans: [Plan]) -> Bool {
        projectedSnapshot(for: plans) != nil
    }

    func stage(_ plans: [Plan]) -> [Change]? {
        guard let target = projectedSnapshot(for: plans) else { return nil }
        let changes = plans.map { plan -> Change in
            switch plan.operation {
            case .registration(let expected):
                let entry = storage.register(
                    expected.tab,
                    for: expected.pinId,
                    in: expected.windowId,
                    presentationPage: expected.presentationPage
                )
                precondition(entry?.isIdentical(to: expected) == true)
                return .registration(expected)
            case .removal(let expected):
                precondition(storage.remove(ifMatching: expected))
                return .removal(expected)
            case .relocation(let previous, let current):
                let result = storage.relocate(
                    current.tab,
                    from: previous.pinId,
                    to: current.pinId,
                    in: current.windowId,
                    presentationPage: current.presentationPage
                )
                precondition(
                    result?.previous.isIdentical(to: previous) == true
                        && result?.current.isIdentical(to: current) == true
                )
                return .relocation(previous: previous, current: current)
            }
        }
        precondition(storage.snapshot.isIdentical(to: target))
        return changes
    }

    func canPublish(_ changes: [Change]) -> Bool {
        reversedSnapshot(for: changes) != nil
    }

    private func reversedSnapshot(
        for changes: [Change]
    ) -> LiveShortcutTabSnapshot? {
        var entries = storage.snapshot.entriesByWindow
        for change in changes.reversed() {
            switch change {
            case .registration(let current):
                guard entry(containing: current.tab, in: entries)?
                    .isIdentical(to: current) == true else { return nil }
                removeProjected(current, from: &entries)
            case .removal(let previous):
                guard entry(containing: previous.tab, in: entries) == nil,
                      entries[previous.windowId]?[previous.pinId] == nil
                else { return nil }
                entries[previous.windowId, default: [:]][previous.pinId]
                    = previous
            case .relocation(let previous, let current):
                guard entry(containing: current.tab, in: entries)?
                    .isIdentical(to: current) == true else { return nil }
                removeProjected(current, from: &entries)
                guard entry(containing: previous.tab, in: entries) == nil,
                      entries[previous.windowId]?[previous.pinId] == nil
                else { return nil }
                entries[previous.windowId, default: [:]][previous.pinId]
                    = previous
            }
        }
        return LiveShortcutTabSnapshot(entriesByWindow: entries)
    }

    @discardableResult
    func rollback(_ changes: [Change]) -> Bool {
        guard canPublish(changes) else { return false }
        for change in changes.reversed() {
            switch change {
            case .registration(let entry):
                guard storage.remove(ifMatching: entry) else { return false }
            case .removal(let entry):
                guard storage.register(
                    entry.tab,
                    for: entry.pinId,
                    in: entry.windowId,
                    presentationPage: entry.presentationPage
                )?.isIdentical(to: entry) == true else { return false }
            case .relocation(let previous, let current):
                guard storage.relocate(
                    current.tab,
                    from: current.pinId,
                    to: previous.pinId,
                    in: current.windowId,
                    presentationPage: previous.presentationPage
                )?.previous.isIdentical(to: current) == true else {
                    return false
                }
            }
        }
        return true
    }

    func publish(_ changes: [Change]) {
        structuralLookup.notifyTransientShortcutStateChanged(
            entries: changes.flatMap(\.affectedEntries)
        )
    }

    private func projectedSnapshot(
        for plans: [Plan]
    ) -> LiveShortcutTabSnapshot? {
        var entries = storage.snapshot.entriesByWindow
        for plan in plans {
            switch plan.operation {
            case .registration(let target):
                guard target.presentationPage.page.windowID == target.windowId,
                      entry(containing: target.tab, in: entries) == nil,
                      entries[target.windowId]?[target.pinId] == nil else {
                    return nil
                }
                entries[target.windowId, default: [:]][target.pinId] = target
            case .removal(let source):
                guard entry(containing: source.tab, in: entries)?
                    .isIdentical(to: source) == true else { return nil }
                removeProjected(source, from: &entries)
            case .relocation(let source, let target):
                guard source.tab === target.tab,
                      source.windowId == target.windowId,
                      source.pinId != target.pinId
                        || source.presentationPage != target.presentationPage,
                      target.presentationPage.page.windowID == target.windowId,
                      entry(containing: source.tab, in: entries)?
                        .isIdentical(to: source) == true else { return nil }
                let occupant = entries[target.windowId]?[target.pinId]
                guard occupant == nil || occupant?.tab === source.tab else {
                    return nil
                }
                removeProjected(source, from: &entries)
                entries[target.windowId, default: [:]][target.pinId] = target
            }
        }
        return LiveShortcutTabSnapshot(entriesByWindow: entries)
    }

    private func entry(
        containing tab: Tab,
        in entries: [UUID: [UUID: LiveShortcutTabEntry]]
    ) -> LiveShortcutTabEntry? {
        entries.values.lazy.compactMap { slots in
            slots.values.first { $0.tab === tab }
        }.first
    }

    private func removeProjected(
        _ entry: LiveShortcutTabEntry,
        from entries: inout [UUID: [UUID: LiveShortcutTabEntry]]
    ) {
        entries[entry.windowId]?.removeValue(forKey: entry.pinId)
        if entries[entry.windowId]?.isEmpty == true {
            entries.removeValue(forKey: entry.windowId)
        }
    }
}
