import Foundation
import SumiDomain

/// Materializes one durable split group for one window and selects its stable
/// member. Focus never mutates the shared split structure.
@MainActor
final class SplitShortcutFocusService {
    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let selectTabWithoutPersistence: (Tab, BrowserWindowState) -> Void
    private let refreshCompositor: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        selectTabWithoutPersistence: @escaping (Tab, BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        self.refreshCompositor = refreshCompositor
        self.persistWindowSession = persistWindowSession
    }

    func focusSplitGroup(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID? = nil,
        in windowState: BrowserWindowState
    ) {
        guard let runtime = runtimeLease() else { return }
        guard canFocus(group, in: windowState) else {
            queueFocus(
                group,
                preferredMemberID: preferredMemberID,
                in: windowState
            )
            return
        }
        guard applyFocusWithinRuntimeLease(
            group,
            preferredMemberID: preferredMemberID,
            in: windowState,
            runtime: runtime
        ) else {
            return
        }
        persistWindowSession(windowState)
    }

    func completePendingSplitGroupFocusIfReady(
        in windowState: BrowserWindowState,
        spaceId: UUID
    ) {
        guard let runtime = runtimeLease(),
              let request = windowState.presentationState.pendingSplitGroupFocusRequest,
              request.targetSpaceID == spaceId else {
            return
        }

        windowState.presentationState.pendingSplitGroupFocusRequest = nil
        guard let group = runtime.tabManager.splitGroupStore.group(
            id: request.groupID
        ), applyFocusWithinRuntimeLease(
            group,
            preferredMemberID: request.preferredMemberID,
            in: windowState,
            runtime: runtime
        ) else {
            refreshCompositor(windowState)
            return
        }
        persistWindowSession(windowState)
    }

    /// Used by a larger operation that already holds the runtime lease and
    /// owns the final session write.
    @discardableResult
    func applyFocusWithinRuntimeLease(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID? = nil,
        in windowState: BrowserWindowState,
        runtime: SplitShortcutRuntimeLease
    ) -> Bool {
        guard canFocus(group, in: windowState) else { return false }
        let tabManager = runtime.tabManager
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
        guard let materialized = WindowSplitMaterializationService()
            .materialize(
                group,
                selection: selection,
                in: windowState,
                tabManager: tabManager
            ) else {
            return false
        }

        selectTabWithoutPersistence(materialized.activeTab, windowState)
        windowState.splitSelection = materialized.presentation.selection
        refreshCompositor(windowState)
        return true
    }

    func refreshPresentation(in windowState: BrowserWindowState) {
        refreshCompositor(windowState)
    }

    private func canFocus(
        _ group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        group.container.spaceId == nil
            || group.container.spaceId == windowState.currentSpaceId
    }

    private func queueFocus(
        _ group: SumiDomain.SplitGroup,
        preferredMemberID: SplitMemberID?,
        in windowState: BrowserWindowState
    ) {
        guard let hostSpaceID = group.container.spaceId else { return }
        windowState.presentationState.pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
            groupID: group.id,
            preferredMemberID: preferredMemberID,
            targetSpaceID: hostSpaceID
        )
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
