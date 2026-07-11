import Foundation
import SumiDomain

/// Reconciles window-local selection and materialization after a shared split
/// group changes. Durable structure is already committed when this service is
/// called; it never chooses or mutates shared split topology.
@MainActor
final class WindowSplitPresentationSynchronizer {
    private struct PersistedSelectionState: Equatable {
        let tabState: ShortcutConversionWindowSessionState
        let splitSelection: WindowSplitSelection?

        @MainActor
        init(_ windowState: BrowserWindowState) {
            tabState = ShortcutConversionWindowSessionState(windowState)
            splitSelection = windowState.splitSelection
        }
    }

    private let tabManager: @MainActor () -> TabManager?
    private let windows: @MainActor () -> [BrowserWindowState]
    private let selectTabWithoutPersistence: @MainActor (
        Tab,
        BrowserWindowState
    ) -> Void
    private let publishWindowChange: @MainActor (UUID) -> Void
    private let refreshCompositor: @MainActor (BrowserWindowState) -> Void
    private let persistWindowSession: @MainActor (BrowserWindowState) -> Void

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        windows: @escaping @MainActor () -> [BrowserWindowState],
        selectTabWithoutPersistence: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> Void,
        publishWindowChange: @escaping @MainActor (UUID) -> Void = { _ in },
        refreshCompositor: @escaping @MainActor (BrowserWindowState) -> Void,
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.windows = windows
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        self.publishWindowChange = publishWindowChange
        self.refreshCompositor = refreshCompositor
        self.persistWindowSession = persistWindowSession
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
        unavailableMembers: [UUID: Set<SplitMemberID>] = [:]
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

            let before = PersistedSelectionState(windowState)
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
            publishWindowChange(windowState.id)
            refreshCompositor(windowState)
            if before != PersistedSelectionState(windowState) {
                persistWindowSession(windowState)
            }
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
            publishWindowChange(windowState.id)
            refreshCompositor(windowState)
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
        guard let materialized = WindowSplitMaterializationService().materialize(
            currentGroup,
            selection: selection,
            in: windowState,
            tabManager: tabManager
        ) else {
            windowState.splitSelection = nil
            return
        }

        selectTabWithoutPersistence(materialized.activeTab, windowState)
        windowState.splitSelection = materialized.presentation.selection
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
            if let liveTab = tabManager.liveShortcutTabs.tab(
                for: pinID,
                in: windowState.id
            ) {
                return liveTab
            }
            guard let pin = tabManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pinID) else {
                return nil
            }
            return tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
            )
        }
    }
}
