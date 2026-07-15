import Foundation

@MainActor
struct ShortcutTabBindingWindowBatch {
    let aggregate: BrowserWindowShortcutMutationOwner.PreparedAggregate
    let changedWindows: [BrowserWindowState]
    let targetStates: [UUID: BrowserWindowShortcutMutationState]
}

@MainActor
struct ShortcutTabBindingWindowBatchPreparer {
    private struct PlannedWindow {
        let window: BrowserWindowState
        let source: BrowserWindowShortcutMutationState
        var target: BrowserWindowShortcutMutationState
        var requiresPersistence: Bool
    }

    static func prepare(
        inputs: [ShortcutTabBindingModelTransaction.Input],
        contributions: [ShortcutTabBindingWindowContribution],
        using owner: BrowserWindowShortcutMutationOwner
    ) -> ShortcutTabBindingWindowBatch? {
        var planned: [UUID: PlannedWindow] = [:]
        for entry in contributions.flatMap(\.entries) {
            guard merge(entry, into: &planned) else { return nil }
        }
        for input in inputs {
            for plan in input.plans {
                guard let window = plan.windowState else { continue }
                let source = window.unpublishedShortcutMutationState
                var target = source
                let requiresPersistence = ShortcutSelectionTransition.apply(
                    tab: plan.tab,
                    source: plan.sourceIdentity,
                    targetPin: input.pin,
                    isSelected: plan.wasSelected,
                    to: &target
                )
                guard merge(.init(
                    window: window,
                    source: source,
                    target: target,
                    requiresPersistence: requiresPersistence
                ), into: &planned) else { return nil }
            }
        }
        let ordered = planned.values.sorted {
            $0.window.id.uuidString < $1.window.id.uuidString
        }
        guard let aggregate = owner.prepareAggregate({
            for item in ordered {
                guard item.window.unpublishedShortcutMutationState
                    == item.source else { return false }
                owner.stage(item.window) { $0 = item.target }
            }
            return true
        }) else { return nil }
        return ShortcutTabBindingWindowBatch(
            aggregate: aggregate,
            changedWindows: ordered.compactMap {
                $0.requiresPersistence ? $0.window : nil
            },
            targetStates: Dictionary(uniqueKeysWithValues: ordered.map {
                ($0.window.id, $0.target)
            })
        )
    }

    private static func merge(
        _ entry: ShortcutTabBindingWindowContribution.Entry,
        into planned: inout [UUID: PlannedWindow]
    ) -> Bool {
        guard entry.window.unpublishedShortcutMutationState == entry.source
        else { return false }
        var item = planned[entry.window.id] ?? PlannedWindow(
            window: entry.window,
            source: entry.source,
            target: entry.source,
            requiresPersistence: false
        )
        guard item.window === entry.window, item.source == entry.source,
              merge(\.currentTabId, from: entry, into: &item),
              merge(\.currentSpaceId, from: entry, into: &item),
              merge(\.currentShortcutPinId, from: entry, into: &item),
              merge(\.currentShortcutPinRole, from: entry, into: &item),
              merge(\.isShowingEmptyState, from: entry, into: &item),
              merge(\.splitSelection, from: entry, into: &item),
              merge(\.activeTabForSpace, from: entry, into: &item),
              merge(\.selectedShortcutPinForSpace, from: entry, into: &item),
              merge(\.selectionHistory, from: entry, into: &item),
              merge(\.webKitChildWindowIdentity, from: entry, into: &item)
        else { return false }
        item.requiresPersistence = item.requiresPersistence
            || entry.requiresPersistence
        planned[entry.window.id] = item
        return true
    }

    private static func merge<Value: Equatable>(
        _ keyPath: WritableKeyPath<BrowserWindowShortcutMutationState, Value>,
        from entry: ShortcutTabBindingWindowContribution.Entry,
        into item: inout PlannedWindow
    ) -> Bool {
        let source = entry.source[keyPath: keyPath]
        let candidate = entry.target[keyPath: keyPath]
        guard candidate != source else { return true }
        let existing = item.target[keyPath: keyPath]
        guard existing == source || existing == candidate else { return false }
        item.target[keyPath: keyPath] = candidate
        return true
    }
}
