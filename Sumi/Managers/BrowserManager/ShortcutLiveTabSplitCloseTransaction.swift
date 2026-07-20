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

    init(
        splitGroups: SplitGroupStore,
        hostedUnload: ShortcutHostedSplitUnloadService
    ) {
        self.splitGroups = splitGroups
        self.hostedUnload = hostedUnload
    }

    func close(
        pinID: UUID,
        in windowState: BrowserWindowState
    ) -> ShortcutLiveTabSplitCloseOutcome {
        guard let group = splitGroups.group(
            containing: .shortcutPin(pinID)
        ) else { return .notGrouped }
        guard group.container.isShortcutSidebar else { return .rejected }
        return hostedUnload.unloadShortcutHostedSplitGroup(
            group,
            in: windowState
        ) ? .committed : .rejected
    }
}
