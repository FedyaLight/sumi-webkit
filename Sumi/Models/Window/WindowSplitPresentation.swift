import Foundation
import SumiDomain

/// Window-local rendering of one durable split group. It contains identities
/// only: tabs and WebViews remain owned by their existing runtime registries.
struct WindowSplitPresentation: Equatable, Sendable {
    let windowID: UUID
    let group: SumiDomain.SplitGroup
    let selection: WindowSplitSelection
    let liveTabIDByMemberID: [SplitMemberID: UUID]
    let activeTabID: UUID

    init?(
        windowID: UUID,
        group: SumiDomain.SplitGroup,
        selection: WindowSplitSelection,
        liveTabIDByMemberID: [SplitMemberID: UUID]
    ) {
        let memberIDs = group.memberIDs
        guard let activeTabID = liveTabIDByMemberID[selection.activeMemberID],
              selection.groupID == group.id,
              memberIDs.contains(selection.activeMemberID),
              Set(liveTabIDByMemberID.keys) == Set(memberIDs),
              Set(liveTabIDByMemberID.values).count == memberIDs.count
        else {
            return nil
        }
        self.windowID = windowID
        self.group = group
        self.selection = selection
        self.liveTabIDByMemberID = liveTabIDByMemberID
        self.activeTabID = activeTabID
    }

    var groupID: UUID { group.id }

    var activeMemberID: SplitMemberID {
        selection.activeMemberID
    }

    var visibleTabIDs: [UUID] {
        group.memberIDs.compactMap { liveTabIDByMemberID[$0] }
    }

    func tabID(for memberID: SplitMemberID) -> UUID? {
        liveTabIDByMemberID[memberID]
    }

    func memberID(for tabID: UUID) -> SplitMemberID? {
        group.memberIDs.first { liveTabIDByMemberID[$0] == tabID }
    }

    func contains(tabID: UUID) -> Bool {
        liveTabIDByMemberID.values.contains(tabID)
    }
}
