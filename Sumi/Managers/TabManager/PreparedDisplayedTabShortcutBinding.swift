import Foundation
import SumiDomain

@MainActor
private struct DisplayedTabShortcutCandidateReceipt {
    let id: UUID
    let role: ShortcutPinRole
    let profileID: UUID?
    let executionProfileID: UUID?
    let spaceID: UUID?
    let folderID: UUID?

    init(_ candidate: ShortcutPin) {
        id = candidate.id
        role = candidate.role
        profileID = candidate.profileId
        executionProfileID = candidate.executionProfileId
        spaceID = candidate.spaceId
        folderID = candidate.folderId
    }

    func accepts(_ pin: ShortcutPin) -> Bool {
        pin.id == id
            && pin.role == role
            && pin.profileId == profileID
            && pin.executionProfileId == executionProfileID
            && pin.spaceId == spaceID
            && pin.folderId == folderID
    }
}

@MainActor
private struct DisplayedTabShortcutSourceReceipt {
    let tab: Tab
    let spaceID: UUID?
    let liveTabsByWindowID: [UUID: Tab]
    let freshTabs: [(Tab, BrowserWindowState)]

    var windowIDs: Set<UUID> { Set(liveTabsByWindowID.keys) }
}

@MainActor
private final class DisplayedTabShortcutResidencePreparer {
    @MainActor
    struct PlannedResidence {
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

    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner
    private let planned: [PlannedResidence]
    private let source: DisplayedTabShortcutSourceReceipt

    init(
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        planned: [(Tab, DisplayedShortcutPresentationResidencePlan.Entry,
            ShortcutSplitLauncherBindingTarget)],
        source: DisplayedTabShortcutSourceReceipt
    ) {
        self.registry = registry
        self.membership = membership
        self.planned = planned.map {
            PlannedResidence(tab: $0.0, presentation: $0.1, target: $0.2)
        }
        self.source = source
    }

    func prepare(
        for pin: ShortcutPin
    ) -> (
        LiveShortcutPresentationResidenceTransaction,
        DisplayedShortcutResidenceContribution,
        [ShortcutSplitLauncherBindingPlan],
        [UUID: ShortcutBindingIdentity]
    )? {
        guard planned.allSatisfy({ item in
            registry.entry(containing: item.tab) == nil
                && registry.tab(
                    for: pin.id,
                    in: item.presentation.window.id
                ) == nil
        }), planned.allSatisfy({ item in
            item.tab === source.tab || item.acceptsFreshModel(for: pin)
        }), planned.filter({ $0.tab === source.tab }).count == 1 else {
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
        guard Set(terminalIdentitiesByWindowID.keys) == source.windowIDs else {
            return nil
        }
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
                preparedLookup: item.tab === source.tab
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
            guard item.tab === source.tab else { return nil }
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
        return (
            residences,
            presentationContribution,
            bindingPlans,
            terminalIdentitiesByWindowID
        )
    }
}

@MainActor
final class DisplayedTabShortcutBindingPreflight {
    private let candidate: DisplayedTabShortcutCandidateReceipt
    private let profile: ShortcutTabProfileAssignmentAdmission
    private let residences: DisplayedTabShortcutResidencePreparer
    private let source: DisplayedTabShortcutSourceReceipt

    var sourceSpaceID: UUID? { source.spaceID }
    var freshTabs: [(Tab, BrowserWindowState)] { source.freshTabs }
    var sourceTab: Tab { source.tab }
    var liveTabsByWindowID: [UUID: Tab] { source.liveTabsByWindowID }

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
        self.candidate = DisplayedTabShortcutCandidateReceipt(candidate)
        self.profile = profile
        let source = DisplayedTabShortcutSourceReceipt(
            tab: sourceTab,
            spaceID: sourceSpaceID,
            liveTabsByWindowID: liveTabsByWindowID,
            freshTabs: freshTabs
        )
        self.source = source
        residences = DisplayedTabShortcutResidencePreparer(
            registry: registry,
            membership: membership,
            planned: planned,
            source: source
        )
    }

    func prepareResidences(
        for pin: ShortcutPin
    ) -> PreparedDisplayedTabShortcutBinding? {
        guard candidate.accepts(pin),
              let prepared = residences.prepare(for: pin) else { return nil }
        return PreparedDisplayedTabShortcutBinding(
            contribution: ShortcutTabBindingBatchContribution(
                inputs: [.init(
                    pin: pin,
                    plans: prepared.2,
                    residences: prepared.0
                )],
                profileAdmissions: [profile],
                residences: [
                    ShortcutTabBindingResidenceReceiptTransaction(prepared.0),
                ]
            ),
            preflight: self,
            residences: prepared.0,
            presentationContribution: prepared.1,
            terminalIdentitiesByWindowID: prepared.3
        )
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
