import Foundation
import SumiDomain

@MainActor
struct SplitInsertionAdmission {
    let windowID: UUID
    let currentTab: Tab
    let targetMemberID: SplitMemberID
    let target: SplitDropTarget
}

/// Resolves high-level split insertion commands into exact durable drop
/// targets. Structural commit remains owned by `SplitDropService`.
@MainActor
final class SplitInsertionService {
    private let currentTab: (BrowserWindowState) -> Tab?
    private let memberIsGrouped: (SplitMemberID) -> Bool
    private let members: SplitRuntimeMemberResolver
    private let drops: SplitDropService

    init(
        currentTab: @escaping (BrowserWindowState) -> Tab?,
        memberIsGrouped: @escaping (SplitMemberID) -> Bool,
        members: SplitRuntimeMemberResolver,
        drops: SplitDropService
    ) {
        self.currentTab = currentTab
        self.memberIsGrouped = memberIsGrouped
        self.members = members
        self.drops = drops
    }

    @discardableResult
    func enterSplit(
        with tab: Tab,
        side: SplitDropSide,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let admission = admission(side: side, in: windowState) else {
            return false
        }
        return enterSplit(with: tab, admission: admission, in: windowState)
    }

    func admission(
        side: SplitDropSide,
        in windowState: BrowserWindowState
    ) -> SplitInsertionAdmission? {
        guard let current = currentTab(windowState),
              current.representsSumiNativeSurface == false,
              let targetMemberID = windowState.splitSelection?.activeMemberID
                ?? members.memberID(for: current) else {
            return nil
        }
        return SplitInsertionAdmission(
            windowID: windowState.id,
            currentTab: current,
            targetMemberID: targetMemberID,
            target: target(
                memberID: targetMemberID,
                side: side
            )
        )
    }

    @discardableResult
    func enterSplit(
        with tab: Tab,
        admission: SplitInsertionAdmission,
        in windowState: BrowserWindowState
    ) -> Bool {
        let windowMatches = admission.windowID == windowState.id
        let currentMatches = currentTab(windowState) === admission.currentTab
            || (
                admission.targetMemberID.isShortcutPin
                    && currentTab(windowState) === tab
            )
        let targetIsRegular =
            admission.currentTab.representsSumiNativeSurface == false
        let memberMatches = (windowState.splitSelection?.activeMemberID
                ?? members.memberID(for: admission.currentTab))
            == admission.targetMemberID
        let targetMatches = target(
            memberID: admission.targetMemberID,
            side: admission.target.side
        ) == admission.target
        guard windowMatches,
              currentMatches,
              targetIsRegular,
              memberMatches,
              targetMatches else { return false }
        return drops.drop(tab, on: admission.target, in: windowState)
    }

    private func target(
        memberID: SplitMemberID,
        side: SplitDropSide
    ) -> SplitDropTarget {
        SplitInsertionTargetResolver.target(
            memberID: memberID,
            side: side,
            memberIsGrouped: memberIsGrouped(memberID)
        )
    }
}
