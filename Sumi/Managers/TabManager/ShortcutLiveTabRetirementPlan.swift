import Foundation

@MainActor
struct ShortcutLiveTabRetirementPlan {
    let pinID: UUID
    let windowID: UUID
    let entry: LiveShortcutTabEntry?
    let registry: LiveShortcutTabRegistry
    let runtimeConnection: TabRuntimePortConnection
    let runtimeLease: TabRuntimePortLease
    let windowState: BrowserWindowState?
    let sourceWindowState: BrowserWindowShortcutMutationState?
    let residencePlan: LiveShortcutResidenceMutationStaging.Plan?
    let result: ShortcutLiveTabRetirementResult

    init?(
        pinID: UUID,
        windowID: UUID,
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection
    ) {
        let entry = registry.entries(in: windowID).first { $0.pinId == pinID }
        let runtimeLease = runtimeConnection.captureLease()
        if entry != nil, runtimeLease.registry == nil { return nil }
        self.pinID = pinID
        self.windowID = windowID
        self.entry = entry
        self.registry = registry
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
        residencePlan = entry.flatMap(registry.staging.prepareRemoval)
        windowState = entry.flatMap { runtimeLease.windowState(for: $0.windowId) }
        sourceWindowState = windowState?.unpublishedShortcutMutationState

        if let entry, let windowState, var target = sourceWindowState {
            let didClear = target.currentTabId == entry.tab.id
                || target.currentTabId == entry.pinId
                || target.currentShortcutPinId == entry.pinId
            if target.currentTabId == entry.tab.id
                || target.currentTabId == entry.pinId {
                target.currentTabId = nil
            }
            if target.currentShortcutPinId == entry.pinId {
                target.currentShortcutPinId = nil
                target.currentShortcutPinRole = nil
            }
            result = ShortcutLiveTabRetirementResult(
                retiredTabIds: [entry.tab.id],
                didClearCurrentSelection: didClear,
                windowStatesNeedingPersistence: target == sourceWindowState
                    ? [] : [windowState]
            )
        } else {
            result = ShortcutLiveTabRetirementResult(
                retiredTabIds: entry.map { [$0.tab.id] } ?? []
            )
        }
    }

    var tabs: [Tab] { entry.map { [$0.tab] } ?? [] }

    func windowIsCurrent(_ expected: BrowserWindowShortcutMutationState?) -> Bool {
        guard let entry else { return true }
        return runtimeLease.windowState(for: entry.windowId) === windowState
            && windowState?.unpublishedShortcutMutationState == expected
    }
}
