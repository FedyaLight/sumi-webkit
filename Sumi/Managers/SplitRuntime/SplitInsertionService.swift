import Foundation
import SumiDomain

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
        guard let current = currentTab(windowState),
              current.representsSumiNativeSurface == false,
              let targetMemberID = windowState.splitSelection?.activeMemberID
                ?? members.memberID(for: current) else {
            return false
        }
        return drops.drop(
            tab,
            on: SplitInsertionTargetResolver.target(
                memberID: targetMemberID,
                side: side,
                memberIsGrouped: memberIsGrouped(targetMemberID)
            ),
            in: windowState
        )
    }
}
