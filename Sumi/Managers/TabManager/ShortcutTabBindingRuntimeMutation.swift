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
        admission: LiveShortcutPresentationRefreshAdmission,
        refreshes: LiveShortcutPresentationRefreshService
    ) -> Bool {
        let lease = runtimeConnection.captureLease()
        guard runtimeConnection.accepts(lease),
              refreshes.acceptsCurrent(admission, for: pin),
              let prepared = prepare(
            pin,
            changes: admission.changes,
            using: lease
              ),
              let residences = refreshes.prepareResidenceTransaction(
                  admission,
                  for: pin
              ) else { return false }
        return execute(
            pin: pin,
            prepared: prepared,
            residences: residences,
            using: lease
        )
    }

    func rebind(
        _ tab: Tab,
        from sourcePin: ShortcutPin,
        to targetPin: ShortcutPin
    ) -> Bool {
        guard let entry = registry.entry(containing: tab),
              entry.pinId == sourcePin.id else { return false }
        let lease = runtimeConnection.captureLease()
        let window = lease.windowState(for: entry.windowId)
        guard runtimeConnection.accepts(lease),
              let binding = targets.prepareExisting(
                  targetPin,
                  to: tab,
                  currentSpaceID: window?.currentSpaceId,
                  using: lease
              ),
              let page = targets.presentationPage(
                  for: targetPin,
                  windowID: entry.windowId,
                  spaceID: targetPin.spaceId
                      ?? entry.presentationPage.page.spaceID
              ) else { return false }
        let source = ShortcutBindingIdentity(tab: tab)
        let selected = window.map {
            ShortcutSelectionIdentity.isSelected(
                tabId: tab.id,
                pinId: sourcePin.id,
                in: $0
            )
        } ?? false
        guard let residencePlan = registry.staging.prepareRelocation(
            tab,
            from: sourcePin.id,
            to: targetPin.id,
            in: entry.windowId,
            presentationPage: page
        ) else { return false }
        let admission = LiveShortcutPresentationRefreshAdmission(
            pin: targetPin,
            changes: [.init(
                tab: tab,
                windowID: entry.windowId,
                sourcePage: entry.presentationPage,
                targetPage: page
            )]
        )
        let residences = LiveShortcutPresentationResidenceTransaction(
            pin: targetPin,
            admission: admission,
            staging: registry.staging,
            plans: [residencePlan]
        )
        let plan = ShortcutSplitLauncherBindingPlan(
            tab: tab,
            windowID: entry.windowId,
            windowState: window,
            tabReceipt: binding.receipt,
            windowReceipt: window.map(ShortcutSplitLauncherWindowReceipt.init),
            sourceIdentity: source,
            wasSelected: selected,
            target: binding.target
        )
        return execute(
            pin: targetPin,
            prepared: [.init(plan: plan, profile: binding.profile)],
            residences: residences,
            using: lease
        )
    }

    private func prepare(
        _ pin: ShortcutPin,
        changes: [LiveShortcutPresentationRefreshAdmission.Change],
        using lease: TabRuntimePortLease
    ) -> [PreparedShortcutTabRuntimeBinding]? {
        var result: [PreparedShortcutTabRuntimeBinding] = []
        for change in changes {
            let window = lease.windowState(for: change.windowID)
            guard let binding = targets.prepareExisting(
                pin,
                to: change.tab,
                currentSpaceID: window?.currentSpaceId,
                using: lease
            ) else { return nil }
            let source = ShortcutBindingIdentity(tab: change.tab)
            result.append(.init(
                plan: ShortcutSplitLauncherBindingPlan(
                    tab: change.tab,
                    windowID: change.windowID,
                    windowState: window,
                    tabReceipt: binding.receipt,
                    windowReceipt: window.map(
                        ShortcutSplitLauncherWindowReceipt.init
                    ),
                    sourceIdentity: source,
                    wasSelected: window.map {
                        ShortcutSelectionIdentity.isSelected(
                            tabId: change.tab.id,
                            pinId: source?.pinId,
                            in: $0
                        )
                    } ?? false,
                    target: binding.target
                ),
                profile: binding.profile
            ))
        }
        return result
    }

    private func execute(
        pin: ShortcutPin,
        prepared: [PreparedShortcutTabRuntimeBinding],
        residences: LiveShortcutPresentationResidenceTransaction,
        using lease: TabRuntimePortLease
    ) -> Bool {
        let inputs = [ShortcutTabBindingModelTransaction.Input(
                pin: pin,
                plans: prepared.map(\.plan),
                residences: residences
            )]
        let builder = ShortcutTabBindingBatchBuilder(
            runtimeConnection: runtimeConnection,
            runtimeAttachment: TabRuntimeAttachmentWitness(
                connection: runtimeConnection,
                lease: lease
            ),
            windowMutations: windowMutations,
            profiles: targets.profiles,
            persistence: ShortcutSplitLauncherWindowPersistence(
                structuralLookup: structuralLookup
            ),
            structuralLookup: structuralLookup
        )
        let contribution = ShortcutTabBindingBatchContribution(
            inputs: inputs,
            profileAdmissions: prepared.map(\.profile),
            residences: inputs.map {
                ShortcutTabBindingResidenceReceiptTransaction($0.residences)
            }
        )
        guard let (model, profiles) = builder.makeTransaction(
            from: contribution
        ) else {
            guard residences.cancelPrepared() else { return false }
            return false
        }
        return profiles.execute(bindingModel: model).wasAccepted
    }
}
