import Foundation

@MainActor
struct ShortcutLiveRetirementBindingExclusion {
    private let tab: Tab
    private let pinID: UUID
    private let windowID: UUID

    fileprivate init(tab: Tab, pinID: UUID, windowID: UUID) {
        self.tab = tab
        self.pinID = pinID
        self.windowID = windowID
    }

    func belongs(to pin: ShortcutPin) -> Bool { pin.id == pinID }

    func matches(
        pin: ShortcutPin,
        change: LiveShortcutPresentationRefreshAdmission.Change
    ) -> Bool {
        belongs(to: pin)
            && change.tab === tab
            && change.windowID == windowID
    }
}

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
    let retirementWindowState: BrowserWindowShortcutMutationState?
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
            retirementWindowState = target
            result = ShortcutLiveTabRetirementResult(
                retiredTabIds: [entry.tab.id],
                didClearCurrentSelection: didClear,
                windowStatesNeedingPersistence: target == sourceWindowState
                    ? [] : [windowState]
            )
        } else {
            retirementWindowState = sourceWindowState
            result = ShortcutLiveTabRetirementResult(
                retiredTabIds: entry.map { [$0.tab.id] } ?? []
            )
        }
    }

    var tabs: [Tab] { entry.map { [$0.tab] } ?? [] }

    var bindingExclusion: ShortcutLiveRetirementBindingExclusion? {
        entry.map {
            ShortcutLiveRetirementBindingExclusion(
                tab: $0.tab,
                pinID: pinID,
                windowID: windowID
            )
        }
    }

    func sourceResidenceIsCurrent() -> Bool {
        guard runtimeConnection.accepts(runtimeLease) else { return false }
        guard let entry else {
            return registry.tab(for: pinID, in: windowID) == nil
        }
        return residencePlan != nil
            && registry.entry(containing: entry.tab)?.isIdentical(to: entry)
                == true
    }

    func windowIsCurrent(_ expected: BrowserWindowShortcutMutationState?) -> Bool {
        guard let entry else { return true }
        return runtimeLease.windowState(for: entry.windowId) === windowState
            && windowState?.unpublishedShortcutMutationState == expected
    }

    func windowContribution(
        reconcilingWith presentation: ShortcutTabBindingWindowContribution
    ) -> (ShortcutTabBindingWindowContribution, BrowserWindowShortcutMutationState?)? {
        guard let windowState, let sourceWindowState,
              let retirementWindowState else { return (.empty, nil) }
        let overlap = presentation.entries.filter { $0.window.id == windowState.id }
        guard overlap.count <= 1 else { return nil }
        let target: BrowserWindowShortcutMutationState
        if let presentation = overlap.first {
            guard presentation.window === windowState,
                  presentation.source == sourceWindowState,
                  presentation.target.currentTabId != entry?.tab.id,
                  presentation.target.currentTabId != pinID,
                  presentation.target.currentShortcutPinId != pinID
            else { return nil }
            target = presentation.target
        } else {
            target = retirementWindowState
        }
        return (ShortcutTabBindingWindowContribution(entries: [.init(
            window: windowState,
            source: sourceWindowState,
            target: target,
            requiresPersistence: false
        )]), target)
    }
}
