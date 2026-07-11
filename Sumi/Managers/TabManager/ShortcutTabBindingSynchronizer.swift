import Foundation

/// Keeps materialized tabs aligned with their launcher role and execution context.
@MainActor
final class ShortcutTabBindingSynchronizer {
    private let registry: LiveShortcutTabRegistry
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let profiles: TabProfileTransitionService
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimePorts: () -> RuntimePortRegistry?

    init(
        registry: LiveShortcutTabRegistry,
        resolution: ShortcutPinRuntimeResolutionOwner,
        profiles: TabProfileTransitionService,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimePorts: @escaping () -> RuntimePortRegistry?
    ) {
        self.registry = registry
        self.resolution = resolution
        self.profiles = profiles
        self.structuralLookup = structuralLookup
        self.runtimePorts = runtimePorts
    }

    convenience init(tabManager: TabManager) {
        self.init(
            registry: tabManager.liveShortcutTabs,
            resolution: tabManager.shortcutPinRuntimeResolutionOwner,
            profiles: tabManager.profileAssignments.tabs,
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimePorts: { [weak tabManager] in tabManager?.runtimePorts }
        )
    }
    func refreshInstances(for pin: ShortcutPin) {
        let runtime = runtimePorts()
        var changedWindowStates: [UUID: BrowserWindowState] = [:]
        structuralLookup.withTransaction {
            var changed = false
            for entry in registry.entries(for: pin.id) {
                let windowState = runtime?.windowState(for: entry.windowId)
                let sourceIdentity = ShortcutBindingIdentity(tab: entry.tab)
                let isSelected = windowState.map {
                    ShortcutSelectionIdentity.isSelected(
                        tabId: entry.tab.id,
                        pinId: sourceIdentity?.pinId,
                        in: $0
                    )
                } ?? false
                changed = applyExisting(
                    pin,
                    to: entry.tab,
                    currentSpaceId: windowState?.currentSpaceId
                ) || changed
                if let windowState,
                   ShortcutSelectionTransition.apply(
                       tab: entry.tab,
                       source: sourceIdentity,
                       targetPin: pin,
                       isSelected: isSelected,
                       in: windowState
                   ) {
                    changedWindowStates[windowState.id] = windowState
                }
            }
            if changed { structuralLookup.requestPublish() }
        }
        persist(changedWindowStates, using: runtime)
    }

    @discardableResult
    func canRebind(_ tab: Tab, from sourcePin: ShortcutPin) -> Bool {
        registry.entry(containing: tab)?.pinId == sourcePin.id
    }

    @discardableResult
    func rebind(
        _ tab: Tab,
        from sourcePin: ShortcutPin,
        to targetPin: ShortcutPin
    ) -> Bool {
        guard let entry = registry.entry(containing: tab),
              entry.pinId == sourcePin.id else { return false }

        let runtime = runtimePorts()
        var changedWindowStates: [UUID: BrowserWindowState] = [:]
        let didRebind = structuralLookup.withTransaction {
            let windowState = runtime?.windowState(for: entry.windowId)
            let wasSelected = windowState.map {
                ShortcutSelectionIdentity.isSelected(
                    tabId: tab.id,
                    pinId: sourcePin.id,
                    in: $0
                )
            } ?? false
            let sourceIdentity = ShortcutBindingIdentity(tab: tab)
            _ = registry.rekey(
                tab,
                from: sourcePin.id,
                to: targetPin.id,
                in: entry.windowId
            )
            _ = applyExisting(
                targetPin,
                to: tab,
                currentSpaceId: windowState?.currentSpaceId
            )
            if let windowState,
               ShortcutSelectionTransition.apply(
                   tab: tab,
                   source: sourceIdentity,
                   targetPin: targetPin,
                   isSelected: wasSelected,
                   in: windowState
               ) {
                changedWindowStates[windowState.id] = windowState
            }
            return true
        }
        persist(changedWindowStates, using: runtime)
        return didRebind
    }

    @discardableResult
    func initializeFresh(
        _ tab: Tab,
        for pin: ShortcutPin,
        currentSpaceId: UUID?
    ) -> Bool {
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        tab.spaceId = resolution.resolvedLiveSpaceId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
        tab.profileId = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
        tab.folderId = pin.role == .essential ? nil : pin.folderId
        return true
    }

    @discardableResult
    func applyExisting(
        _ pin: ShortcutPin,
        to tab: Tab,
        currentSpaceId: UUID?
    ) -> Bool {
        let targetSpaceId = resolution.resolvedLiveSpaceId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
        let targetProfileId = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
        let targetFolderId = pin.role == .essential ? nil : pin.folderId
        let changed = tab.shortcutPinId != pin.id
            || tab.shortcutPinRole != pin.role
            || tab.spaceId != targetSpaceId
            || tab.profileId != targetProfileId
            || tab.folderId != targetFolderId
            || tab.isPinned
            || tab.isSpacePinned

        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        _ = profiles.prepareForSpaceTransition(
            tab: tab,
            targetSpaceID: targetSpaceId,
            desiredProfileID: targetProfileId
        )
        tab.spaceId = targetSpaceId
        tab.folderId = targetFolderId
        profiles.assignProfile(targetProfileId, to: tab)
        return changed
    }

    private func persist(
        _ windowStates: [UUID: BrowserWindowState],
        using runtime: RuntimePortRegistry?
    ) {
        guard let runtime, windowStates.isEmpty == false else { return }
        let orderedStates = windowStates.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        structuralLookup.runAfterCurrentBatch {
            orderedStates.forEach(runtime.persistWindowSession(for:))
        }
    }
}
