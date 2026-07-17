import Foundation
import SumiDomain

@MainActor
extension WindowSplitPresentationSynchronizer {
    func prepareSettlementAgainstSource(
        previousGroups: [SumiDomain.SplitGroup],
        sourceGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        affectedGroupIDs: Set<UUID>,
        preferredSelections: [UUID: WindowSplitSelection],
        insertionPreview: ShortcutPresentationCatalogInsertionPreview,
        residenceContribution: DisplayedShortcutResidenceContribution,
        requiredWindows: [UUID: BrowserWindowState],
        terminalParticipants: WindowSplitPresentationTerminalParticipants
    ) -> PreparedWindowSplitPresentationSettlement? {
        prepareSettlement(
            previousGroups: previousGroups,
            replacementGroups: replacementGroups,
            currentGroups: sourceGroups,
            affectedGroupIDs: affectedGroupIDs,
            standaloneMembers: [:],
            unavailableMembers: [:],
            preferredSelections: preferredSelections,
            activationSource: .displayedBinding(
                insertionPreview,
                residenceContribution
            ),
            requiredWindows: requiredWindows,
            terminalParticipants: terminalParticipants,
            sessionWriteUrgency: .scheduled
        )
    }
}

/// Reconciles window-local selection and materialization after a shared split
/// group changes. Durable structure is already committed when this service is
/// called; it never chooses or mutates shared split topology.
@MainActor
final class WindowSplitPresentationSynchronizer {
    private let preparation: WindowSplitPresentationPreparationService
    private let splitGroups: SplitGroupStore
    private let members: SplitRuntimeMemberResolver
    private let materialization: WindowSplitMaterializationService
    private let terminalEffects:
        WindowSplitPresentationEffectExecutor

    init(
        preparation: WindowSplitPresentationPreparationService,
        splitGroups: SplitGroupStore,
        members: SplitRuntimeMemberResolver,
        materialization: WindowSplitMaterializationService,
        terminalEffects: WindowSplitPresentationEffectExecutor
    ) {
        self.preparation = preparation
        self.splitGroups = splitGroups
        self.members = members
        self.materialization = materialization
        self.terminalEffects = terminalEffects
    }

    /// Prepares the complete window-local half of a split topology aggregate.
    /// The caller must already have installed `replacementGroups` in the raw
    /// split store. Shortcut materialization, final window selection and all
    /// outward effects remain owned by the returned receipt.
    func prepareSettlement(
        previousGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        affectedGroupIDs: Set<UUID>,
        standaloneMembers: [UUID: SplitMemberID] = [:],
        unavailableMembers: [UUID: Set<SplitMemberID>] = [:],
        preferredSelections: [UUID: WindowSplitSelection] = [:],
        requiredWindows: [UUID: BrowserWindowState] = [:],
        terminalParticipants: WindowSplitPresentationTerminalParticipants,
        sessionWriteUrgency: WindowSplitSessionWriteUrgency = .scheduled
    ) -> PreparedWindowSplitPresentationSettlement? {
        prepareSettlement(
            previousGroups: previousGroups,
            replacementGroups: replacementGroups,
            currentGroups: replacementGroups,
            affectedGroupIDs: affectedGroupIDs,
            standaloneMembers: standaloneMembers,
            unavailableMembers: unavailableMembers,
            preferredSelections: preferredSelections,
            activationSource: .canonical,
            requiredWindows: requiredWindows,
            terminalParticipants: terminalParticipants,
            sessionWriteUrgency: sessionWriteUrgency
        )
    }

    func prepareSettlementAgainstSource(
        previousGroups: [SumiDomain.SplitGroup],
        sourceGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        affectedGroupIDs: Set<UUID>,
        standaloneMembers: [UUID: SplitMemberID] = [:],
        unavailableMembers: [UUID: Set<SplitMemberID>] = [:],
        preferredSelections: [UUID: WindowSplitSelection] = [:],
        requiredWindows: [UUID: BrowserWindowState] = [:],
        terminalParticipants: WindowSplitPresentationTerminalParticipants,
        sessionWriteUrgency: WindowSplitSessionWriteUrgency = .scheduled
    ) -> PreparedWindowSplitPresentationSettlement? {
        prepareSettlement(
            previousGroups: previousGroups,
            replacementGroups: replacementGroups,
            currentGroups: sourceGroups,
            affectedGroupIDs: affectedGroupIDs,
            standaloneMembers: standaloneMembers,
            unavailableMembers: unavailableMembers,
            preferredSelections: preferredSelections,
            activationSource: .canonical,
            requiredWindows: requiredWindows,
            terminalParticipants: terminalParticipants,
            sessionWriteUrgency: sessionWriteUrgency
        )
    }

    private func prepareSettlement(
        previousGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        currentGroups: [SumiDomain.SplitGroup],
        affectedGroupIDs: Set<UUID>,
        standaloneMembers: [UUID: SplitMemberID],
        unavailableMembers: [UUID: Set<SplitMemberID>],
        preferredSelections: [UUID: WindowSplitSelection],
        activationSource: WindowSplitPresentationActivationSource,
        requiredWindows: [UUID: BrowserWindowState],
        terminalParticipants: WindowSplitPresentationTerminalParticipants,
        sessionWriteUrgency: WindowSplitSessionWriteUrgency
    ) -> PreparedWindowSplitPresentationSettlement? {
        preparation.prepare(
            input: .init(
                previousGroups: previousGroups,
                replacementGroups: replacementGroups,
                affectedGroupIDs: affectedGroupIDs,
                standaloneMembers: standaloneMembers,
                unavailableMembers: unavailableMembers,
                preferredSelections: preferredSelections,
                requiredWindows: requiredWindows,
                sessionWriteUrgency: sessionWriteUrgency
            ),
            currentGroups: currentGroups,
            activationSource: activationSource,
            terminalEffects: terminalEffects,
            terminalParticipants: terminalParticipants
        )
    }

    /// Synchronizes exactly the windows presenting an affected group. Previous
    /// values are required so a dissolved group can retain the user's active
    /// pane as a standalone tab.
    func synchronize(
        previousGroups: [SumiDomain.SplitGroup],
        affectedGroupIDs: Set<UUID>,
        preferredSelections: [UUID: WindowSplitSelection] = [:],
        preferredActiveMembers: [UUID: SplitMemberID] = [:],
        standaloneMembers: [UUID: SplitMemberID] = [:],
        unavailableMembers: [UUID: Set<SplitMemberID>] = [:],
        sessionWriteUrgency: WindowSplitSessionWriteUrgency = .scheduled
    ) {
        guard !affectedGroupIDs.isEmpty else { return }
        let previousByID = Dictionary(
            previousGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for windowState in preparation.currentWindows() {
            let previousSelectedGroupID = windowState.splitSelection?.groupID
            guard preferredSelections[windowState.id] != nil
                    || preferredActiveMembers[windowState.id] != nil
                    || standaloneMembers[windowState.id] != nil
                    || previousSelectedGroupID.map(affectedGroupIDs.contains) == true else {
                continue
            }

            let before = WindowSplitPresentationPersistedState(windowState)
            if let standaloneMember = standaloneMembers[windowState.id] {
                windowState.splitSelection = nil
                if let tab = members.liveTab(
                    for: standaloneMember,
                    in: windowState
                ) {
                    terminalEffects.selectWithoutPersistence(
                        tab,
                        in: windowState
                    )
                }
            } else {
                synchronize(
                    windowState,
                    previousGroup: previousSelectedGroupID.flatMap {
                        previousByID[$0]
                    },
                    preferredSelection: preferredSelections[windowState.id],
                    preferredActiveMember: preferredActiveMembers[windowState.id],
                    unavailableMembers: unavailableMembers[windowState.id] ?? []
                )
            }
            terminalEffects.publishSynchronizedWindow(
                windowState,
                previousState: before,
                urgency: sessionWriteUrgency
            )
        }
    }

    /// Invalidates rendering for an already-valid presentation without
    /// reselecting tabs, materializing members or writing window sessions.
    func refreshPresentations(for groupIDs: Set<UUID>) {
        guard !groupIDs.isEmpty else { return }
        for windowState in preparation.currentWindows()
            where windowState.splitSelection.map({
                groupIDs.contains($0.groupID)
            }) == true {
            terminalEffects.refreshPresentation(windowState)
        }
    }

    private func synchronize(
        _ windowState: BrowserWindowState,
        previousGroup: SumiDomain.SplitGroup?,
        preferredSelection: WindowSplitSelection?,
        preferredActiveMember: SplitMemberID?,
        unavailableMembers: Set<SplitMemberID>
    ) {
        let selectedGroupID = preferredSelection?.groupID
            ?? windowState.splitSelection?.groupID
        guard let selectedGroupID,
              let currentGroup = splitGroups.group(
                  id: selectedGroupID
              ) else {
            leaveDissolvedGroup(
                previousGroup,
                unavailableMembers: unavailableMembers,
                in: windowState
            )
            return
        }

        let requestedMemberID = preferredSelection?.activeMemberID
            ?? preferredActiveMember
            ?? windowState.splitSelection?.activeMemberID
        let activeMemberID = requestedMemberID.flatMap {
            currentGroup.contains($0) ? $0 : nil
        } ?? currentGroup.memberIDs.first
        guard let activeMemberID else {
            windowState.splitSelection = nil
            return
        }
        let selection = WindowSplitSelection(
            groupID: currentGroup.id,
            activeMemberID: activeMemberID
        )
        guard materialization.withMaterialization(
            currentGroup,
            selection: selection,
            in: windowState,
            finalizing: { [terminalEffects] materialized in
                terminalEffects.selectWithoutPersistence(
                    materialized.activeTab,
                    in: windowState
                )
                windowState.splitSelection = materialized.presentation.selection
            }
        ) else {
            windowState.splitSelection = nil
            return
        }
    }

    private func leaveDissolvedGroup(
        _ previousGroup: SumiDomain.SplitGroup?,
        unavailableMembers: Set<SplitMemberID>,
        in windowState: BrowserWindowState
    ) {
        let selectedMemberID = windowState.splitSelection?.activeMemberID
        windowState.splitSelection = nil
        guard let previousGroup else { return }

        let candidates = [selectedMemberID]
            + previousGroup.memberIDs.map(Optional.some)
        for memberID in candidates.compactMap({ $0 })
            where !unavailableMembers.contains(memberID) {
            guard let tab = members.liveTab(
                for: memberID,
                in: windowState
            ) else {
                continue
            }
            terminalEffects.selectWithoutPersistence(
                tab,
                in: windowState
            )
            return
        }
    }

    func splitDropPresentationProjection(
        _ effect: SplitDropCommitEffect,
        caller: BrowserWindowState
    ) -> SplitDropPresentationSelectionProjection? {
        SplitDropPresentationSelectionProjector.prepare(
            effect,
            caller: caller,
            windows: preparation.currentWindows()
        )
    }
}
