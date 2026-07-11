import Foundation
import SumiDomain

/// ID-only split commands exposed to sidebar views.
///
/// Views and delayed animation completions never retain a mutable group
/// snapshot or a window object. Each invocation resolves the exact current
/// group and window, so a removed member or closed window becomes a no-op.
@MainActor
struct SidebarSplitCommands {
    let focusGroup: (UUID, SplitMemberID?, UUID) -> Void
    let restoreMember: (UUID, SplitMemberID, UUID) -> Void
    let closeMember: (UUID, SplitMemberID, UUID) -> Void

    init(
        focusGroup: @escaping (UUID, SplitMemberID?, UUID) -> Void,
        restoreMember: @escaping (UUID, SplitMemberID, UUID) -> Void,
        closeMember: @escaping (UUID, SplitMemberID, UUID) -> Void
    ) {
        self.focusGroup = focusGroup
        self.restoreMember = restoreMember
        self.closeMember = closeMember
    }
}
