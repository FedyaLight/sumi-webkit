@MainActor
final class ShortcutSplitLauncherBindingBatchStaging {
    private let refreshes: LiveShortcutPresentationRefreshService
    private let resolution: ShortcutPinRuntimeResolutionOwner
    let builder: ShortcutTabBindingBatchBuilder

    init(
        refreshes: LiveShortcutPresentationRefreshService,
        resolution: ShortcutPinRuntimeResolutionOwner,
        builder: ShortcutTabBindingBatchBuilder
    ) {
        self.refreshes = refreshes
        self.resolution = resolution
        self.builder = builder
    }

    func admission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        refreshes.admission(for: pin)
    }

    func prepare(
        pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission
    ) -> ShortcutSplitLauncherPreparedBinding? {
        guard builder.isCurrent(),
              refreshes.acceptsCurrent(admission, for: pin) else { return nil }
        let plans = makePlans(pin: pin, admission: admission)
        guard plans.count == admission.changes.count else { return nil }
        let profileAdmissions = plans.compactMap {
            builder.prepareProfileAdmission(
                tab: $0.tab,
                target: $0.target
            )
        }
        guard profileAdmissions.count == plans.count else { return nil }
        return ShortcutSplitLauncherPreparedBinding(
            pinTarget: ShortcutSplitLauncherBindingPinTarget(pin),
            admission: admission,
            plans: plans,
            profileAdmissions: profileAdmissions
        )
    }

    func prepareTransaction(
        pin: ShortcutPin,
        prepared: ShortcutSplitLauncherPreparedBinding
    ) -> ShortcutSplitLauncherPreparedBindingModel? {
        guard builder.isCurrent(),
              prepared.pinTarget.accepts(pin),
              refreshes.acceptsCurrent(prepared.admission, for: pin),
              let residences = refreshes.prepareResidenceTransaction(
                  prepared.admission,
                  for: pin
              ) else { return nil }
        return ShortcutSplitLauncherPreparedBindingModel(
            pinTarget: prepared.pinTarget,
            input: ShortcutTabBindingModelTransaction.Input(
                pin: pin,
                plans: prepared.plans,
                residences: residences
            ),
            profileAdmissions: prepared.profileAdmissions
        )
    }

    private func makePlans(
        pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission
    ) -> [ShortcutSplitLauncherBindingPlan] {
        admission.changes.compactMap { change in
            let windowState = builder.windowState(for: change.windowID)
            let source = ShortcutBindingIdentity(tab: change.tab)
            guard let target = target(
                pin,
                currentSpaceID: windowState?.currentSpaceId
            ) else { return nil }
            return ShortcutSplitLauncherBindingPlan(
                tab: change.tab,
                windowID: change.windowID,
                windowState: windowState,
                tabReceipt: ShortcutSplitLauncherTabReceipt(change.tab),
                windowReceipt: windowState.map(
                    ShortcutSplitLauncherWindowReceipt.init
                ),
                sourceIdentity: source,
                wasSelected: windowState.map {
                    ShortcutSelectionIdentity.isSelected(
                        tabId: change.tab.id,
                        pinId: source?.pinId,
                        in: $0
                    )
                } ?? false,
                target: target
            )
        }
    }

    private func target(
        _ pin: ShortcutPin,
        currentSpaceID: UUID?
    ) -> ShortcutSplitLauncherBindingTarget? {
        guard let profileTarget = builder.resolvedProfileTarget(
            resolution.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: currentSpaceID
            )
        ) else { return nil }
        return ShortcutSplitLauncherBindingTarget(
            spaceID: resolution.resolvedLiveSpaceId(
                for: pin,
                currentSpaceId: currentSpaceID
            ),
            desiredProfileID: resolution.desiredLiveTabProfileId(for: pin),
            resolvedProfileID: profileTarget.profileID,
            runtimeFallback: profileTarget.runtimeFallback,
            folderID: pin.role == .favorite ? nil : pin.folderId
        )
    }
}
