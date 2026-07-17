import Foundation
import SumiDomain

@MainActor
struct SplitShortcutMemberRestorePreparation {
    let sourceGroups: [SumiDomain.SplitGroup]
    let replacementGroups: [SumiDomain.SplitGroup]
    let retiringPinID: UUID?
    let launcher: PreparedShortcutSplitLauncherRestorationBatch
}
