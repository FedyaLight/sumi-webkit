import Foundation
import SumiDomain

enum ShortcutLiveTabSplitCloseOutcome {
    case notGrouped
    case rejected
    case committed
}

/// Retires one canonical live shortcut residence from its durable split
/// presentation without handling standalone fallback selection.
@MainActor
final class ShortcutLiveTabSplitCloseTransaction {
    private let splitGroups: SplitGroupStore
    private let hostedUnload: ShortcutHostedSplitUnloadService
    private let memberRestore: SplitShortcutMemberRestoreService

    init(
        splitGroups: SplitGroupStore,
        hostedUnload: ShortcutHostedSplitUnloadService,
        memberRestore: SplitShortcutMemberRestoreService
    ) {
        self.splitGroups = splitGroups
        self.hostedUnload = hostedUnload
        self.memberRestore = memberRestore
    }

    func close(
        pinID: UUID,
        in windowState: BrowserWindowState
    ) -> ShortcutLiveTabSplitCloseOutcome {
        guard let group = splitGroups.group(
            containing: .shortcutPin(pinID)
        ) else { return .notGrouped }
        if group.container.isShortcutSidebar {
            return hostedUnload.unloadShortcutHostedSplitGroup(
                group,
                in: windowState
            ) ? .committed : .rejected
        }
        return memberRestore.restoreShortcutSplitMember(
            .shortcutPin(pinID),
            from: group,
            in: windowState,
            preserveLiveInstance: false
        ) ? .committed : .rejected
    }
}
