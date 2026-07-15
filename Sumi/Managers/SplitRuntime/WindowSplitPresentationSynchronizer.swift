import Foundation
import SumiDomain

enum WindowSplitSessionWriteUrgency {
    case scheduled
    case immediate
}

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
    private let tabManager: @MainActor () -> TabManager?
    private let windows: @MainActor () -> [BrowserWindowState]
    private let selectTabWithoutPersistence: @MainActor (
        Tab,
        BrowserWindowState
    ) -> Void
    private let terminalEffects:
        WindowSplitPresentationEffectExecutor

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        windows: @escaping @MainActor () -> [BrowserWindowState],
        selectTabWithoutPersistence: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> Void,
        publishPreparedSelectionEffects: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            UUID?,
            UUID?
        ) -> Void,
        publishWindowChange: @escaping @MainActor (UUID) -> Void,
        refreshCompositor: @escaping @MainActor (BrowserWindowState) -> Void,
        scheduleWindowSession: @escaping @MainActor (BrowserWindowState) -> Void,
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.windows = windows
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        terminalEffects = WindowSplitPresentationEffectExecutor(
            publishPreparedSelectionEffects: publishPreparedSelectionEffects,
            publishWindowChange: publishWindowChange,
            refreshCompositor: refreshCompositor,
            scheduleWindowSession: scheduleWindowSession,
            persistWindowSession: persistWindowSession
        )
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
        guard let tabManager = tabManager(),
              tabManager.splitGroupStore.groups == currentGroups else {
            return nil
        }
        guard let draft = WindowSplitPresentationDraftPlanner().prepare(
            .init(
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
            tabManager: tabManager,
            windows: windows()
        ) else { return nil }
        guard let residences = WindowSplitPresentationResidencePreparer().prepare(
            source: activationSource,
            requests: draft.activationRequests,
            activation: tabManager.shortcutPresentationActivation
        ),
            let plan = WindowSplitPresentationSettlementPlanner().prepare(
                draft,
                shortcutWitnesses: residences.shortcutWitnesses,
                regularTabs: tabManager.regularTabCollectionOwner
            ) else { return nil }
        let participantIDs = terminalParticipants.map(ObjectIdentifier.init)
        guard Set(participantIDs).count == participantIDs.count,
              terminalParticipants.allSatisfy({ participant in
                  plan.windows.contains {
                      $0.window === participant.targetWindow
                  }
              }) else { return nil }
        return PreparedWindowSplitPresentationSettlement(
            plan: plan,
            residences: residences,
            validator: WindowSplitPresentationSettlementValidator(
                splitGroups: tabManager.splitGroupStore,
                regularTabs: tabManager.regularTabCollectionOwner,
                liveShortcuts: tabManager.liveShortcutTabs,
                currentWindows: windows
            ),
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
        guard !affectedGroupIDs.isEmpty,
              let tabManager = tabManager() else {
            return
        }
        let previousByID = Dictionary(
            previousGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for windowState in windows() {
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
                if let tab = liveTab(
                    for: standaloneMember,
                    in: windowState,
                    tabManager: tabManager
                ) {
                    selectTabWithoutPersistence(tab, windowState)
                }
            } else {
                synchronize(
                    windowState,
                    previousGroup: previousSelectedGroupID.flatMap {
                        previousByID[$0]
                    },
                    preferredSelection: preferredSelections[windowState.id],
                    preferredActiveMember: preferredActiveMembers[windowState.id],
                    unavailableMembers: unavailableMembers[windowState.id] ?? [],
                    tabManager: tabManager
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
        for windowState in windows()
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
        unavailableMembers: Set<SplitMemberID>,
        tabManager: TabManager
    ) {
        let selectedGroupID = preferredSelection?.groupID
            ?? windowState.splitSelection?.groupID
        guard let selectedGroupID,
              let currentGroup = tabManager.splitGroupStore.group(
                  id: selectedGroupID
              ) else {
            leaveDissolvedGroup(
                previousGroup,
                unavailableMembers: unavailableMembers,
                in: windowState,
                tabManager: tabManager
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
        guard WindowSplitMaterializationService().withMaterialization(
            currentGroup,
            selection: selection,
            in: windowState,
            tabManager: tabManager,
            finalizing: { [selectTabWithoutPersistence] materialized in
                selectTabWithoutPersistence(
                    materialized.activeTab,
                    windowState
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
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) {
        let selectedMemberID = windowState.splitSelection?.activeMemberID
        windowState.splitSelection = nil
        guard let previousGroup else { return }

        let candidates = [selectedMemberID]
            + previousGroup.memberIDs.map(Optional.some)
        for memberID in candidates.compactMap({ $0 })
            where !unavailableMembers.contains(memberID) {
            guard let tab = liveTab(
                for: memberID,
                in: windowState,
                tabManager: tabManager
            ) else {
                continue
            }
            selectTabWithoutPersistence(tab, windowState)
            return
        }
    }

    private func liveTab(
        for memberID: SplitMemberID,
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            return tabManager.regularTabCollectionOwner.tab(for: tabID)

        case .shortcutPin(let pinID):
            return tabManager.shortcutPresentationActivation.activate(
                pinID: pinID,
                in: windowState.id,
                presentationSpaceID: windowState.currentSpaceId
            )
        }
    }

    func splitDropPresentationProjection(
        _ effect: SplitDropCommitEffect,
        caller: BrowserWindowState
    ) -> SplitDropPresentationSelectionProjection? {
        SplitDropPresentationSelectionProjector.prepare(
            effect,
            caller: caller,
            windows: windows()
        )
    }
}
