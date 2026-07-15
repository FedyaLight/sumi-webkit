import Foundation

/// Atomic physical residence and presentation-page authority for live shortcuts.
@MainActor
final class LiveShortcutTabResidenceStore {
    private var entriesByWindow: [UUID: [UUID: LiveShortcutTabEntry]] = [:]

    var tabsByWindow: [UUID: [UUID: Tab]] {
        entriesByWindow.mapValues { $0.mapValues(\.tab) }
    }
    var tabs: [Tab] { entriesByWindow.values.flatMap(\.values).map(\.tab) }
    var snapshot: LiveShortcutTabSnapshot {
        LiveShortcutTabSnapshot(entriesByWindow: entriesByWindow)
    }

    /// Restores an exact capture without publication. Aggregate transactions
    /// call this only before any model or window settlement becomes visible.
    func restore(_ source: LiveShortcutTabSnapshot) {
        entriesByWindow = source.entriesByWindow
        precondition(snapshot.isIdentical(to: source))
    }

    func removeAll() {
        entriesByWindow.removeAll()
    }

    func register(
        _ tab: Tab,
        for pinId: UUID,
        in windowId: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> LiveShortcutTabEntry? {
        precondition(
            presentationPage.page.windowID == windowId,
            "Live shortcut presentation receipt belongs to another window"
        )
        if let existing = entriesByWindow[windowId]?[pinId] {
            precondition(
                existing.tab === tab
                    && existing.presentationPage == presentationPage,
                "Live shortcut registry slot replacement"
            )
            return nil
        }
        precondition(
            snapshot.entry(containing: tab) == nil,
            "Live shortcut tab registered in more than one slot"
        )
        let entry = LiveShortcutTabEntry(
            windowId: windowId,
            pinId: pinId,
            tab: tab,
            presentationPage: presentationPage
        )
        entriesByWindow[windowId, default: [:]][pinId] = entry
        return entry
    }

    func canRekey(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID
    ) -> Bool {
        guard let entry = snapshot.entry(containing: tab) else { return false }
        return entry.windowId == windowId
            && entry.pinId == sourcePinId
            && sourcePinId != targetPinId
            && targetSlotAccepts(tab, pinId: targetPinId, windowId: windowId)
    }

    func rekey(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID
    ) -> (previous: LiveShortcutTabEntry, current: LiveShortcutTabEntry)? {
        guard canRekey(
            tab,
            from: sourcePinId,
            to: targetPinId,
            in: windowId
        ), let previous = snapshot.entry(containing: tab) else { return nil }
        let current = LiveShortcutTabEntry(
            windowId: windowId,
            pinId: targetPinId,
            tab: tab,
            presentationPage: previous.presentationPage
        )
        replace(previous, with: current)
        return (previous, current)
    }

    func relocate(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> (previous: LiveShortcutTabEntry, current: LiveShortcutTabEntry)? {
        guard canRelocate(
            tab,
            from: sourcePinId,
            to: targetPinId,
            in: windowId,
            presentationPage: presentationPage
        ), let previous = snapshot.entry(containing: tab) else { return nil }
        let current = LiveShortcutTabEntry(
            windowId: windowId,
            pinId: targetPinId,
            tab: tab,
            presentationPage: presentationPage
        )
        replace(previous, with: current)
        return (previous, current)
    }

    func canRelocate(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Bool {
        guard let entry = snapshot.entry(containing: tab) else { return false }
        return entry.windowId == windowId
            && entry.pinId == sourcePinId
            && presentationPage.page.windowID == windowId
            && (sourcePinId != targetPinId
                || entry.presentationPage != presentationPage)
            && targetSlotAccepts(tab, pinId: targetPinId, windowId: windowId)
    }

    func contains(
        matching predicate: (LiveShortcutTabEntry) -> Bool
    ) -> Bool {
        snapshot.orderedEntries.contains(where: predicate)
    }

    func remove(pinId: UUID, in windowId: UUID) -> LiveShortcutTabEntry? {
        guard let entry = entriesByWindow[windowId]?[pinId] else { return nil }
        removeResidence(entry)
        return entry
    }

    func remove(tabId: UUID) -> LiveShortcutTabEntry? {
        guard let entry = snapshot.entry(tabID: tabId) else { return nil }
        removeResidence(entry)
        return entry
    }

    @discardableResult
    func remove(ifMatching expected: LiveShortcutTabEntry) -> Bool {
        guard let current = snapshot.entry(containing: expected.tab),
              current.isIdentical(to: expected) else { return false }
        removeResidence(current)
        return true
    }

    func removeAll(
        matching predicate: (LiveShortcutTabEntry) -> Bool
    ) -> [LiveShortcutTabEntry] {
        let entries = snapshot.orderedEntries.filter(predicate)
        entries.forEach(removeResidence)
        return entries
    }

    private func replace(
        _ previous: LiveShortcutTabEntry,
        with current: LiveShortcutTabEntry
    ) {
        removeResidence(previous)
        entriesByWindow[current.windowId, default: [:]][current.pinId] = current
    }

    private func removeResidence(_ entry: LiveShortcutTabEntry) {
        precondition(
            entriesByWindow[entry.windowId]?[entry.pinId]?
                .isIdentical(to: entry) == true,
            "Live shortcut removal lost exact residence"
        )
        entriesByWindow[entry.windowId]?.removeValue(forKey: entry.pinId)
        if entriesByWindow[entry.windowId]?.isEmpty == true {
            entriesByWindow.removeValue(forKey: entry.windowId)
        }
    }

    private func targetSlotAccepts(
        _ tab: Tab,
        pinId: UUID,
        windowId: UUID
    ) -> Bool {
        guard let occupant = entriesByWindow[windowId]?[pinId] else {
            return true
        }
        return occupant.tab === tab
    }
}
