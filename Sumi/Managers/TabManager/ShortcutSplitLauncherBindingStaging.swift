import Foundation

/// Stages launcher presentation relocation without publishing residence,
/// window, profile, persistence, or execution effects. The enclosing split
/// transaction owns terminal settlement through the returned receipt.
@MainActor
final class ShortcutSplitLauncherBindingStaging {
    private let refreshes: LiveShortcutPresentationRefreshService
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let profileSettlement: ShortcutSplitLauncherProfileSettlement
    private let persistence: ShortcutSplitLauncherWindowPersistence

    init(
        refreshes: LiveShortcutPresentationRefreshService,
        resolution: ShortcutPinRuntimeResolutionOwner,
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner,
        profileSettlement: ShortcutSplitLauncherProfileSettlement,
        persistence: ShortcutSplitLauncherWindowPersistence
    ) {
        self.refreshes = refreshes
        self.resolution = resolution
        self.runtimeConnection = runtimeConnection
        self.windowMutations = windowMutations
        self.profileSettlement = profileSettlement
        self.persistence = persistence
    }

    convenience init(tabManager: TabManager) {
        self.init(
            refreshes: tabManager.liveShortcutPresentationRefreshes,
            resolution: tabManager.shortcutPinRuntimeResolutionOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            profileSettlement: ShortcutSplitLauncherProfileSettlement(
                profiles: tabManager.profileAssignments.tabs
            ),
            persistence: ShortcutSplitLauncherWindowPersistence(
                structuralLookup: tabManager.structuralLookupCoordinator
            )
        )
    }

    func admission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        refreshes.admission(for: pin)
    }

    func stage(
        pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission
    ) -> ShortcutTabBindingRefreshTransaction? {
        guard refreshes.acceptsCurrent(admission, for: pin),
              admission.changes.allSatisfy({
                  $0.tab.profileAssignment.hasUnsettledAssignment == false
              }) else { return nil }
        let runtimeLease = runtimeConnection.captureLease()
        let plans = makePlans(
            pin: pin,
            admission: admission,
            runtimeLease: runtimeLease
        )
        guard plans.count == admission.changes.count,
              let residences = refreshes.stageResidenceTransaction(
                  admission,
                  for: pin
              )
        else { return nil }
        return ShortcutTabBindingRefreshTransaction(
            pin: pin,
            runtimeConnection: runtimeConnection,
            runtimeLease: runtimeLease,
            plans: plans,
            residences: residences,
            windowMutations: windowMutations,
            profileSettlement: profileSettlement,
            persistence: persistence
        )
    }

    private func makePlans(
        pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission,
        runtimeLease: TabRuntimePortLease
    ) -> [ShortcutSplitLauncherBindingPlan] {
        admission.changes.map { change in
            let windowState = runtimeLease.windowState(for: change.windowID)
            let source = ShortcutBindingIdentity(tab: change.tab)
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
                target: target(pin, currentSpaceID: windowState?.currentSpaceId)
            )
        }
    }

    private func target(
        _ pin: ShortcutPin,
        currentSpaceID: UUID?
    ) -> ShortcutSplitLauncherBindingTarget {
        ShortcutSplitLauncherBindingTarget(
            spaceID: resolution.resolvedLiveSpaceId(
                for: pin,
                currentSpaceId: currentSpaceID
            ),
            profileID: resolution.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: currentSpaceID
            ),
            folderID: pin.role == .essential ? nil : pin.folderId
        )
    }
}
