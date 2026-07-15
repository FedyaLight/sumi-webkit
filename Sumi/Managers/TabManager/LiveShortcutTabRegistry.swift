import Foundation

/// Canonical per-window membership for materialized shortcut tabs.
@MainActor
final class LiveShortcutTabRegistry {
    private let storage: TabTransientTabRegistryOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    let staging: LiveShortcutResidenceMutationStaging

    init(
        storage: TabTransientTabRegistryOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.storage = storage
        self.structuralLookup = structuralLookup
        staging = LiveShortcutResidenceMutationStaging(
            storage: storage.liveShortcutResidences,
            structuralLookup: structuralLookup
        )
    }

    convenience init(tabManager: TabManager) {
        self.init(
            storage: tabManager.transientTabRegistryOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
    }

    var snapshot: [UUID: [UUID: Tab]] {
        storage.transientShortcutTabsByWindow
    }

    private var readModel: LiveShortcutTabSnapshot {
        storage.liveShortcutResidences.snapshot
    }

    var mutationSnapshot: LiveShortcutTabSnapshot { readModel }

    func restoreMutationSnapshot(_ source: LiveShortcutTabSnapshot) {
        storage.liveShortcutResidences.restore(source)
    }

    func tab(for pinId: UUID, in windowId: UUID) -> Tab? {
        storage.transientShortcutTabsByWindow[windowId]?[pinId]
    }

    func entries(for pinId: UUID) -> [LiveShortcutTabEntry] {
        readModel.entries(for: pinId)
    }

    func entries(in windowId: UUID) -> [LiveShortcutTabEntry] {
        readModel.entries(in: windowId)
    }

    func entries(presentedInSpace spaceID: UUID) -> [LiveShortcutTabEntry] {
        readModel.orderedEntries.filter {
            $0.presentationPage.page.spaceID == spaceID
        }
    }

    func entry(containing tab: Tab) -> LiveShortcutTabEntry? {
        readModel.entry(containing: tab)
    }

    func entry(tabId: UUID) -> LiveShortcutTabEntry? {
        readModel.entry(tabID: tabId)
    }

    @discardableResult
    func register(
        _ tab: Tab,
        for pinId: UUID,
        in windowId: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Bool {
        guard let change = staging.register(
            tab,
            for: pinId,
            in: windowId,
            presentationPage: presentationPage
        ) else { return false }
        staging.publish([change])
        return true
    }

    @discardableResult
    func rekey(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID
    ) -> Bool {
        guard storage.liveShortcutResidences.canRekey(
            tab,
            from: sourcePinId,
            to: targetPinId,
            in: windowId
        ) else { return false }
        return structuralLookup.withTransaction {
            guard let change = storage.liveShortcutResidences.rekey(
                tab,
                from: sourcePinId,
                to: targetPinId,
                in: windowId
            ) else { return false }
            structuralLookup.notifyTransientShortcutStateChanged(
                entries: [change.previous, change.current]
            )
            return true
        }
    }

    @discardableResult
    func relocate(
        _ tab: Tab,
        from sourcePinId: UUID,
        to targetPinId: UUID,
        in windowId: UUID,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Bool {
        guard staging.canRelocate(
            tab,
            from: sourcePinId,
            to: targetPinId,
            in: windowId,
            presentationPage: presentationPage
        ) else { return false }
        return structuralLookup.withTransaction {
            guard let change = staging.relocate(
                tab,
                from: sourcePinId,
                to: targetPinId,
                in: windowId,
                presentationPage: presentationPage
            ) else { return false }
            staging.publish([change])
            return true
        }
    }

    @discardableResult
    func remove(pinId: UUID, in windowId: UUID) -> LiveShortcutTabEntry? {
        guard let entry = storage.liveShortcutResidences.remove(
            pinId: pinId,
            in: windowId
        ) else { return nil }
        structuralLookup.notifyTransientShortcutStateChanged(entries: [entry])
        return entry
    }

    @discardableResult
    func remove(tabId: UUID) -> LiveShortcutTabEntry? {
        guard let entry = storage.liveShortcutResidences.remove(tabId: tabId) else { return nil }
        structuralLookup.notifyTransientShortcutStateChanged(entries: [entry])
        return entry
    }
}
