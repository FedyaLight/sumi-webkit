import Foundation

@MainActor
final class ShortcutLiveRetirementBatchPlanFactory {
    private let registry: LiveShortcutTabRegistry
    private let connection: TabRuntimePortConnection
    private let splitPlanner: ShortcutLiveRetirementSplitPlanner
    private let deletedWindows: ShortcutLiveRetirementDeletedWindowPlanner

    init(
        registry: LiveShortcutTabRegistry,
        connection: TabRuntimePortConnection,
        splitPlanner: ShortcutLiveRetirementSplitPlanner
    ) {
        self.registry = registry
        self.connection = connection
        self.splitPlanner = splitPlanner
        deletedWindows = ShortcutLiveRetirementDeletedWindowPlanner(
            registry: registry
        )
    }

    func windowRetirement(
        pinIDs: Set<UUID>,
        windowID: UUID,
        targetWindowState: BrowserWindowShortcutMutationState?
    ) -> ShortcutLiveRetirementBatchPlan? {
        let entries = registry.entries(in: windowID)
            .filter { pinIDs.contains($0.pinId) }
        let attachment = exactAttachment(requiredBy: entries)
        guard let attachment else { return nil }
        guard entries.isEmpty == false else { return emptyPlan(attachment) }
        guard let window = attachment.lease.windowState(for: windowID) else {
            return nil
        }
        let source = window.unpublishedShortcutMutationState
        let update = ShortcutLiveRetirementWindowProjection.removingInstances(
            entries, from: source, targetOverride: targetWindowState
        )
        guard ShortcutLiveRetirementWindowPostcondition.excludesCurrentReferences(
            pinIDs: pinIDs,
            tabIDs: Set(entries.map(\.tab.id)),
            from: update.target
        ), splitPlanner.selectionExcludes(pinIDs, state: update.target)
        else { return nil }
        return makePlan(
            entries: entries,
            windows: update.target == source ? [] : [.init(
                window: window,
                source: source,
                target: update.target,
                requiresPersistence: update.requiresPersistence
            )],
            attachment: attachment,
            splitTopology: nil,
            didClearCurrentSelection: update.didClearCurrentSelection
        )
    }

    func deletedPins(
        _ pinIDs: Set<UUID>,
        targetWindowStates: [UUID: BrowserWindowShortcutMutationState] = [:]
    ) -> ShortcutLiveRetirementBatchPlan? {
        let entries = pinIDs.sorted(by: Self.uuidOrder)
            .flatMap(registry.entries(for:))
        guard let attachment = exactAttachment(requiredBy: entries) else {
            return nil
        }
        guard let splitPlan = splitPlanner.prepare(deleting: pinIDs) else {
            return nil
        }
        guard let windowPlan = deletedWindows.prepare(
            pinIDs: pinIDs,
            entries: entries,
            attachment: attachment,
            split: splitPlan,
            targetStates: targetWindowStates
        ) else { return nil }
        let windows = windowPlan.windows
        guard entries.isEmpty == false || windows.isEmpty == false
                || splitPlan.receipt != nil else {
            return emptyPlan(attachment)
        }
        return makePlan(
            entries: entries,
            windows: windows,
            attachment: attachment,
            splitTopology: splitPlan.receipt,
            didClearCurrentSelection: windowPlan.didClearCurrentSelection
        )
    }

    private func makePlan(
        entries: [LiveShortcutTabEntry],
        windows: [ShortcutLiveRetirementBatchWindowEntry],
        attachment: TabRuntimeAttachmentWitness,
        splitTopology: SplitGroupReplacementReceipt?,
        didClearCurrentSelection: Bool
    ) -> ShortcutLiveRetirementBatchPlan? {
        let entries = entries.sorted {
            Self.uuidOrder($0.tab.id, $1.tab.id)
        }
        guard Set(entries.map { ObjectIdentifier($0.tab) }).count == entries.count,
              Set(entries.map(\.tab.id)).count == entries.count else { return nil }
        let residencePlans = entries.compactMap(registry.staging.prepareRemoval)
        guard residencePlans.count == entries.count else { return nil }
        return ShortcutLiveRetirementBatchPlan(
            entries: entries,
            residencePlans: residencePlans,
            windows: windows.sorted { Self.uuidOrder($0.window.id, $1.window.id) },
            attachment: attachment, registry: registry,
            splitTopology: splitTopology,
            result: ShortcutLiveTabRetirementResult(
                retiredTabIds: entries.map(\.tab.id),
                didClearCurrentSelection: didClearCurrentSelection,
                windowStatesNeedingPersistence: windows
                    .filter(\.requiresPersistence).map(\.window)
            )
        )
    }

    private func emptyPlan(
        _ attachment: TabRuntimeAttachmentWitness
    ) -> ShortcutLiveRetirementBatchPlan {
        ShortcutLiveRetirementBatchPlan(
            entries: [], residencePlans: [], windows: [],
            attachment: attachment, registry: registry, splitTopology: nil,
            result: ShortcutLiveTabRetirementResult()
        )
    }

    private func exactAttachment(
        requiredBy entries: [LiveShortcutTabEntry]
    ) -> TabRuntimeAttachmentWitness? {
        let attachment = TabRuntimeAttachmentWitness(
            connection: connection, lease: connection.captureLease()
        )
        return entries.isEmpty || attachment.lease.registry != nil
            ? attachment : nil
    }

    private static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
