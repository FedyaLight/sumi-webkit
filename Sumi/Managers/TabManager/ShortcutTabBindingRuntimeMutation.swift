import Foundation

/// Owns the exact residence, window-selection, and runtime-lease transaction
/// for shortcut rebinding. Target-model settlement is delegated to its typed
/// participant and published only after all reversible state is staged.
@MainActor
final class ShortcutTabBindingRuntimeMutation {
    private let registry: LiveShortcutTabRegistry
    private let targets: ShortcutTabBindingTargetMutationService
    private let runtimeConnection: TabRuntimePortConnection
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        registry: LiveShortcutTabRegistry,
        targets: ShortcutTabBindingTargetMutationService,
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.registry = registry
        self.targets = targets
        self.runtimeConnection = runtimeConnection
        self.windowMutations = windowMutations
        self.structuralLookup = structuralLookup
    }

    func canRebind(_ tab: Tab, from sourcePin: ShortcutPin) -> Bool {
        registry.entry(containing: tab)?.pinId == sourcePin.id
    }

    func refresh(
        _ pin: ShortcutPin,
        residences: LiveShortcutPresentationResidenceTransaction
    ) -> Bool {
        let lease = runtimeConnection.captureLease()
        guard runtimeConnection.accepts(lease),
              residences.isCurrent() else {
            precondition(residences.rollback())
            return false
        }

        var changedWindows: [UUID: BrowserWindowState] = [:]
        var executions: [ShortcutTabBindingExecutionReceipt] = []
        structuralLookup.withTransaction {
            precondition(windowMutations.withAggregate {
                for entry in registry.entries(for: pin.id) {
                    let window = lease.windowState(for: entry.windowId)
                    let source = ShortcutBindingIdentity(tab: entry.tab)
                    let selected = window.map {
                        ShortcutSelectionIdentity.isSelected(
                            tabId: entry.tab.id,
                            pinId: source?.pinId,
                            in: $0
                        )
                    } ?? false
                    executions.append(targets.prepareExisting(
                        pin,
                        to: entry.tab,
                        currentSpaceID: window?.currentSpaceId
                    ))
                    stageSelection(
                        tab: entry.tab,
                        source: source,
                        target: pin,
                        selected: selected,
                        window: window,
                        changedWindows: &changedWindows
                    )
                }
                return true
            })
            precondition(
                residences.publish(),
                "Shortcut binding lost staged presentation residences"
            )
        }
        executions.forEach { $0.execute() }
        persist(changedWindows, using: lease.registry)
        return true
    }

    func rebind(
        _ tab: Tab,
        from sourcePin: ShortcutPin,
        to targetPin: ShortcutPin
    ) -> Bool {
        guard let entry = registry.entry(containing: tab),
              entry.pinId == sourcePin.id else { return false }
        let lease = runtimeConnection.captureLease()
        var changedWindows: [UUID: BrowserWindowState] = [:]
        let didRebind = structuralLookup.withTransaction {
            let window = lease.windowState(for: entry.windowId)
            let source = ShortcutBindingIdentity(tab: tab)
            let selected = window.map {
                ShortcutSelectionIdentity.isSelected(
                    tabId: tab.id,
                    pinId: sourcePin.id,
                    in: $0
                )
            } ?? false
            guard let page = targets.presentationPage(
                for: targetPin,
                windowID: entry.windowId,
                spaceID: targetPin.spaceId ?? entry.presentationPage.page.spaceID
            ), runtimeConnection.accepts(lease),
                  let residence = registry.staging.relocate(
                      tab,
                      from: sourcePin.id,
                      to: targetPin.id,
                      in: entry.windowId,
                      presentationPage: page
                  ) else { return false }
            let execution = targets.prepareExisting(
                targetPin,
                to: tab,
                currentSpaceID: window?.currentSpaceId
            )
            precondition(windowMutations.withAggregate {
                stageSelection(
                    tab: tab,
                    source: source,
                    target: targetPin,
                    selected: selected,
                    window: window,
                    changedWindows: &changedWindows
                )
                return true
            })
            registry.staging.publish([residence])
            execution.execute()
            return true
        }
        persist(changedWindows, using: lease.registry)
        return didRebind
    }

    private func stageSelection(
        tab: Tab,
        source: ShortcutBindingIdentity?,
        target: ShortcutPin,
        selected: Bool,
        window: BrowserWindowState?,
        changedWindows: inout [UUID: BrowserWindowState]
    ) {
        guard let window else { return }
        var requiresPersistence = false
        windowMutations.stage(window) { state in
            requiresPersistence = ShortcutSelectionTransition.apply(
                tab: tab,
                source: source,
                targetPin: target,
                isSelected: selected,
                to: &state
            )
        }
        if requiresPersistence { changedWindows[window.id] = window }
    }

    private func persist(
        _ windows: [UUID: BrowserWindowState],
        using runtime: RuntimePortRegistry?
    ) {
        guard let runtime, windows.isEmpty == false else { return }
        let ordered = windows.values.sorted { $0.id.uuidString < $1.id.uuidString }
        structuralLookup.runAfterCurrentBatch {
            ordered.forEach(runtime.persistWindowSession(for:))
        }
    }
}
