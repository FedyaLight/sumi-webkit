import Foundation
import SumiDomain

/// Materializes one durable split group for one window and selects its stable
/// member. Focus never mutates the shared split structure.
@MainActor
final class SplitShortcutFocusService {
    private let runtimeConnection: TabRuntimePortConnection
    private let splitGroups: SplitGroupStore
    private let materialization: WindowSplitMaterializationService
    private let presentation: SplitShortcutFocusPresentationService

    init(
        runtimeConnection: TabRuntimePortConnection,
        splitGroups: SplitGroupStore,
        materialization: WindowSplitMaterializationService,
        presentation: SplitShortcutFocusPresentationService
    ) {
        self.runtimeConnection = runtimeConnection
        self.splitGroups = splitGroups
        self.materialization = materialization
        self.presentation = presentation
    }

    func focusSplitGroup(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID? = nil,
        in windowState: BrowserWindowState
    ) {
        _ = activateSplitGroup(
            group,
            preferredMemberID: preferredMemberID,
            in: windowState
        )
    }

    @discardableResult
    func activateSplitGroup(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID? = nil,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard runtimeConnection.current != nil else { return false }
        guard canFocus(group, in: windowState) else {
            return queueFocus(
                group,
                preferredMemberID: preferredMemberID,
                in: windowState
            )
        }
        guard applyFocus(
            group,
            preferredMemberID: preferredMemberID,
            in: windowState
        ) else {
            return false
        }
        presentation.persist(windowState)
        return true
    }

    func completePendingSplitGroupFocusIfReady(
        in windowState: BrowserWindowState,
        spaceId: UUID
    ) {
        guard runtimeConnection.current != nil,
              let request = windowState.presentationState.pendingSplitGroupFocusRequest,
              request.targetSpaceID == spaceId else {
            return
        }

        windowState.presentationState.pendingSplitGroupFocusRequest = nil
        guard let group = splitGroups.group(
            id: request.groupID
        ), applyFocus(
            group,
            preferredMemberID: request.preferredMemberID,
            in: windowState
        ) else {
            presentation.refresh(windowState)
            return
        }
        presentation.persist(windowState)
    }

    @discardableResult
    private func applyFocus(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID? = nil,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard canFocus(group, in: windowState) else { return false }
        let activeMemberID = resolvedActiveMemberID(
            preferredMemberID,
            in: group,
            windowState: windowState
        )
        guard let activeMemberID else { return false }
        let selection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: activeMemberID
        )
        guard materialization
            .withMaterialization(
                group,
                selection: selection,
                in: windowState,
                finalizing: { materialized in
                presentation.apply(materialized, in: windowState)
            }) else {
            return false
        }
        return true
    }

    func refreshPresentation(in windowState: BrowserWindowState) {
        presentation.refresh(windowState)
    }

    private func canFocus(
        _ group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        group.container.spaceId == nil
            || group.container.spaceId == windowState.currentSpaceId
    }

    @discardableResult
    private func queueFocus(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID?,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let hostSpaceID = group.container.spaceId else { return false }
        windowState.presentationState.pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
            groupID: group.id,
            preferredMemberID: preferredMemberID,
            targetSpaceID: hostSpaceID
        )
        return true
    }

    private func resolvedActiveMemberID(
        _ preferredMemberID: SplitMemberID?,
        in group: SumiDomain.SplitGroup,
        windowState: BrowserWindowState
    ) -> SplitMemberID? {
        if let preferredMemberID, group.contains(preferredMemberID) {
            return preferredMemberID
        }
        if let pinID = windowState.currentShortcutPinId {
            let memberID = SplitMemberID.shortcutPin(pinID)
            if group.contains(memberID) { return memberID }
        }
        if let tabID = windowState.currentTabId {
            let memberID = SplitMemberID.regularTab(tabID)
            if group.contains(memberID) { return memberID }
        }
        return group.memberIDs.first
    }
}
