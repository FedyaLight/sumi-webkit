import Foundation
import SumiDomain

/// Decides whether a shortcut-sidebar split may stop being presented, and which
/// pins the caller must retire. A group is admitted only while the tab runtime
/// is connected, the group is still canonical, and every member is a shortcut
/// pin — a group holding anything else is not a hosted split.
@MainActor
struct ShortcutHostedSplitUnloadAdmission {
    private let runtimeConnection: TabRuntimePortConnection
    private let splitGroups: SplitGroupStore

    init(
        runtimeConnection: TabRuntimePortConnection,
        splitGroups: SplitGroupStore
    ) {
        self.runtimeConnection = runtimeConnection
        self.splitGroups = splitGroups
    }

    func admittedPinIDs(for group: SumiDomain.SplitGroup) -> Set<UUID>? {
        guard runtimeConnection.current != nil,
              group.container.isShortcutSidebar,
              splitGroups.group(id: group.id) == group
        else { return nil }

        let pinIDs = Set(group.memberIDs.compactMap { memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        })
        guard pinIDs.count == group.memberIDs.count else { return nil }
        return pinIDs
    }
}
