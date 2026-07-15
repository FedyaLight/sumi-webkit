import Foundation
import SumiDomain

/// Chooses the affected windows, active members and shortcut activation
/// requests for an already-installed raw split topology. It performs no model
/// staging and retains no TabManager after returning its immutable draft.
@MainActor
struct WindowSplitPresentationDraftPlanner {
    private struct ActivationRequestSlot: Hashable {
        let windowID: UUID
        let pinID: UUID
    }

    private struct ActivationRequestBuilder {
        private(set) var requests: [
            ShortcutPresentationActivationService.Request
        ] = []
        private var slots: Set<ActivationRequestSlot> = []

        mutating func append(
            _ memberID: SplitMemberID,
            window: BrowserWindowState,
            presentationSpaceID: UUID?
        ) -> Bool {
            guard case .shortcutPin(let pinID) = memberID else { return true }
            guard slots.insert(ActivationRequestSlot(
                windowID: window.id,
                pinID: pinID
            )).inserted else { return false }
            requests.append(.init(
                pinID: pinID,
                windowID: window.id,
                presentationSpaceID: presentationSpaceID
            ))
            return true
        }
    }

    func prepare(
        _ input: WindowSplitPresentationSettlementInput,
        currentGroups: [SumiDomain.SplitGroup],
        tabManager: TabManager,
        windows: [BrowserWindowState]
    ) -> WindowSplitPresentationDraftPlan? {
        let windowIDs = Set(windows.map(\.id))
        let requestedWindowIDs = Set(input.standaloneMembers.keys)
            .union(input.unavailableMembers.keys)
            .union(input.preferredSelections.keys)
        guard input.affectedGroupIDs.isEmpty == false,
              tabManager.splitGroupStore.groups == currentGroups,
              windowIDs.count == windows.count,
              Set(input.previousGroups.map(\.id)).count
                == input.previousGroups.count,
              Set(input.replacementGroups.map(\.id)).count
                == input.replacementGroups.count,
              Set(input.standaloneMembers.keys).isDisjoint(
                  with: input.unavailableMembers.keys
              ),
              requestedWindowIDs == Set(input.requiredWindows.keys),
              requestedWindowIDs.isSubset(of: windowIDs)
        else { return nil }

        let windowsByID = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0) }
        )
        guard input.requiredWindows.allSatisfy({ windowID, expected in
            windowsByID[windowID] === expected
        }) else { return nil }

        let previousByID = Dictionary(
            uniqueKeysWithValues: input.previousGroups.map { ($0.id, $0) }
        )
        let replacementByID = Dictionary(
            uniqueKeysWithValues: input.replacementGroups.map { ($0.id, $0) }
        )
        guard let draftPlan = makeDrafts(
            input: input,
            windows: windows,
            previousByID: previousByID,
            replacementByID: replacementByID,
            tabManager: tabManager
        ), requestedWindowIDs.isSubset(
            of: Set(draftPlan.drafts.map { $0.window.id })
        ) else { return nil }
        return draftPlan
    }

    private func makeDrafts(
        input: WindowSplitPresentationSettlementInput,
        windows: [BrowserWindowState],
        previousByID: [UUID: SumiDomain.SplitGroup],
        replacementByID: [UUID: SumiDomain.SplitGroup],
        tabManager: TabManager
    ) -> WindowSplitPresentationDraftPlan? {
        var drafts: [WindowSplitPresentationDraft] = []
        var activationRequests = ActivationRequestBuilder()

        for window in windows {
            let preferredSelection = input.preferredSelections[window.id]
            let selectedGroupID = preferredSelection?.groupID
                ?? window.splitSelection?.groupID
            guard input.standaloneMembers[window.id] != nil
                    || selectedGroupID.map(
                        input.affectedGroupIDs.contains
                    ) == true else {
                continue
            }

            if let standalone = input.standaloneMembers[window.id] {
                guard activationRequests.append(
                    standalone,
                    window: window,
                    presentationSpaceID: window.currentSpaceId
                ) else { return nil }
                drafts.append(WindowSplitPresentationDraft(
                    window: window,
                    activeMemberID: standalone,
                    splitSelection: nil,
                    materializedMembers: [standalone]
                ))
                continue
            }

            if let selectedGroupID,
               let group = replacementByID[selectedGroupID] {
                let requested = preferredSelection?.activeMemberID
                    ?? window.splitSelection?.activeMemberID
                guard let activeMemberID = requested.flatMap({
                    group.contains($0) ? $0 : nil
                }) ?? group.memberIDs.first else { return nil }
                for memberID in group.memberIDs {
                    guard activationRequests.append(
                        memberID,
                        window: window,
                        presentationSpaceID: group.container.spaceId
                            ?? window.currentSpaceId
                    ) else { return nil }
                }
                drafts.append(WindowSplitPresentationDraft(
                    window: window,
                    activeMemberID: activeMemberID,
                    splitSelection: WindowSplitSelection(
                        groupID: group.id,
                        activeMemberID: activeMemberID
                    ),
                    materializedMembers: group.memberIDs
                ))
                continue
            }

            let previous = selectedGroupID.flatMap { previousByID[$0] }
            let unavailable = input.unavailableMembers[window.id] ?? []
            let candidates = ([window.splitSelection?.activeMemberID]
                + (previous?.memberIDs.map(Optional.some) ?? []))
                .compactMap { $0 }
            let activeMemberID = candidates.first {
                memberIsAvailable(
                    $0,
                    excluding: unavailable,
                    tabManager: tabManager
                )
            }
            if let activeMemberID {
                guard activationRequests.append(
                    activeMemberID,
                    window: window,
                    presentationSpaceID: previous?.container.spaceId
                        ?? window.currentSpaceId
                ) else { return nil }
            }
            drafts.append(WindowSplitPresentationDraft(
                window: window,
                activeMemberID: activeMemberID,
                splitSelection: nil,
                materializedMembers: activeMemberID.map { [$0] } ?? []
            ))
        }
        return WindowSplitPresentationDraftPlan(
            drafts: drafts,
            activationRequests: activationRequests.requests,
            expectedGroups: input.replacementGroups,
            sessionWriteUrgency: input.sessionWriteUrgency
        )
    }

    private func memberIsAvailable(
        _ memberID: SplitMemberID,
        excluding unavailable: Set<SplitMemberID>,
        tabManager: TabManager
    ) -> Bool {
        guard unavailable.contains(memberID) == false else { return false }
        switch memberID {
        case .regularTab(let tabID):
            return tabManager.regularTabCollectionOwner.tab(for: tabID) != nil
        case .shortcutPin(let pinID):
            return tabManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pinID) != nil
        }
    }
}
