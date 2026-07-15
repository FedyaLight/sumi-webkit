import Foundation
import SumiDomain

@MainActor
final class DisplayedTabShortcutBindingPreflight {
    @MainActor
    private struct PlannedResidence {
        let tab: Tab
        let presentation: DisplayedShortcutPresentationResidencePlan.Entry
        let target: ShortcutSplitLauncherBindingTarget

        func acceptsFreshModel(for pin: ShortcutPin) -> Bool {
            tab.isPinned == false
                && tab.isSpacePinned == false
                && tab.shortcutPinId == pin.id
                && tab.shortcutPinRole == pin.role
                && tab.spaceId == target.spaceID
                && tab.profileId == target.desiredProfileID
                && tab.folderId == target.folderID
        }
    }

    private let candidateID: UUID
    private let candidateRole: ShortcutPinRole
    private let candidateProfileID: UUID?
    private let candidateExecutionProfileID: UUID?
    private let candidateSpaceID: UUID?
    private let candidateFolderID: UUID?
    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner
    private let profile: ShortcutTabProfileAssignmentAdmission
    private let planned: [PlannedResidence]

    let sourceTab: Tab
    let sourceSpaceID: UUID?
    let liveTabsByWindowID: [UUID: Tab]
    let freshTabs: [(Tab, BrowserWindowState)]

    init(
        candidate: ShortcutPin,
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        profile: ShortcutTabProfileAssignmentAdmission,
        planned: [(Tab, DisplayedShortcutPresentationResidencePlan.Entry,
            ShortcutSplitLauncherBindingTarget)],
        sourceTab: Tab,
        sourceSpaceID: UUID?,
        liveTabsByWindowID: [UUID: Tab],
        freshTabs: [(Tab, BrowserWindowState)]
    ) {
        candidateID = candidate.id
        candidateRole = candidate.role
        candidateProfileID = candidate.profileId
        candidateExecutionProfileID = candidate.executionProfileId
        candidateSpaceID = candidate.spaceId
        candidateFolderID = candidate.folderId
        self.registry = registry
        self.membership = membership
        self.profile = profile
        self.planned = planned.map {
            PlannedResidence(tab: $0.0, presentation: $0.1, target: $0.2)
        }
        self.sourceTab = sourceTab
        self.sourceSpaceID = sourceSpaceID
        self.liveTabsByWindowID = liveTabsByWindowID
        self.freshTabs = freshTabs
    }

    func prepareResidences(
        for pin: ShortcutPin
    ) -> PreparedDisplayedTabShortcutBinding? {
        guard accepts(pin), planned.allSatisfy({ item in
            registry.entry(containing: item.tab) == nil
                && registry.tab(
                    for: pin.id,
                    in: item.presentation.window.id
                ) == nil
        }), planned.allSatisfy({ item in
            item.tab === sourceTab || item.acceptsFreshModel(for: pin)
        }), planned.filter({ $0.tab === sourceTab }).count == 1 else {
            return nil
        }
        var residencePlans: [LiveShortcutResidenceMutationStaging.Plan] = []
        var terminalIdentitiesByWindowID: [UUID: ShortcutBindingIdentity] = [:]
        for item in planned {
            guard let plan = registry.staging.prepareRegistration(
                item.tab,
                for: pin.id,
                in: item.presentation.window.id,
                presentationPage: item.presentation.page
            ) else { return nil }
            residencePlans.append(plan)
            let terminalIdentity = ShortcutBindingIdentity(
                pinId: pin.id,
                role: pin.role,
                spaceId: item.target.spaceID
            )
            guard terminalIdentitiesByWindowID.updateValue(
                terminalIdentity,
                forKey: item.presentation.window.id
            ) == nil else { return nil }
        }
        guard Set(terminalIdentitiesByWindowID.keys)
                == Set(liveTabsByWindowID.keys) else { return nil }
        let residences = LiveShortcutPresentationResidenceTransaction(
            pin: pin,
            admission: LiveShortcutPresentationRefreshAdmission(
                pin: pin,
                changes: []
            ),
            staging: registry.staging,
            plans: residencePlans
        )
        let contributionEntries = planned.map { item in
            DisplayedShortcutResidenceContribution.Entry(
                window: item.presentation.window,
                pinID: pin.id,
                tab: item.tab,
                page: item.presentation.page,
                source: ShortcutSplitLauncherTabReceipt(item.tab),
                target: ShortcutBindingIdentity(
                    pinId: pin.id,
                    role: pin.role,
                    spaceId: item.target.spaceID
                ),
                targetFolderID: item.target.folderID,
                preparedLookup: item.tab === sourceTab
                    ? .exactSource : .absentFresh
            )
        }
        guard let presentationContribution =
            DisplayedShortcutResidenceContribution(
                pin: pin,
                registry: registry,
                membership: membership,
                residences: residences,
                entries: contributionEntries
            ) else { return nil }
        let bindingPlans: [ShortcutSplitLauncherBindingPlan] = planned.compactMap { item in
            guard item.tab === sourceTab else { return nil }
            return ShortcutSplitLauncherBindingPlan(
                tab: item.tab,
                windowID: item.presentation.window.id,
                windowState: nil,
                tabReceipt: ShortcutSplitLauncherTabReceipt(item.tab),
                windowReceipt: nil,
                sourceIdentity: ShortcutBindingIdentity(tab: item.tab),
                wasSelected: false,
                target: item.target
            )
        }
        return PreparedDisplayedTabShortcutBinding(
            contribution: ShortcutTabBindingBatchContribution(
                inputs: [.init(
                    pin: pin,
                    plans: bindingPlans,
                    residences: residences
                )],
                profileAdmissions: [profile],
                residences: [
                    ShortcutTabBindingResidenceReceiptTransaction(residences),
                ]
            ),
            preflight: self,
            residences: residences,
            presentationContribution: presentationContribution,
            terminalIdentitiesByWindowID: terminalIdentitiesByWindowID
        )
    }

    private func accepts(_ pin: ShortcutPin) -> Bool {
        pin.id == candidateID
            && pin.role == candidateRole
            && pin.profileId == candidateProfileID
            && pin.executionProfileId == candidateExecutionProfileID
            && pin.spaceId == candidateSpaceID
            && pin.folderId == candidateFolderID
    }
}

@MainActor
final class PreparedDisplayedTabShortcutBinding {
    let contribution: ShortcutTabBindingBatchContribution
    private let preflight: DisplayedTabShortcutBindingPreflight
    private let residences: LiveShortcutPresentationResidenceTransaction
    let presentationContribution: DisplayedShortcutResidenceContribution
    let terminalIdentitiesByWindowID: [UUID: ShortcutBindingIdentity]

    init(
        contribution: ShortcutTabBindingBatchContribution,
        preflight: DisplayedTabShortcutBindingPreflight,
        residences: LiveShortcutPresentationResidenceTransaction,
        presentationContribution: DisplayedShortcutResidenceContribution,
        terminalIdentitiesByWindowID: [UUID: ShortcutBindingIdentity]
    ) {
        self.contribution = contribution
        self.preflight = preflight
        self.residences = residences
        self.presentationContribution = presentationContribution
        self.terminalIdentitiesByWindowID = terminalIdentitiesByWindowID
    }

    var sourceTab: Tab { preflight.sourceTab }
    var sourceSpaceID: UUID? { preflight.sourceSpaceID }
    var liveTabsByWindowID: [UUID: Tab] { preflight.liveTabsByWindowID }
    var freshTabs: [(Tab, BrowserWindowState)] { preflight.freshTabs }

    func cancelPreparedResidences() -> Bool { residences.cancelPrepared() }
}
