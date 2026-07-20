import Foundation
import SumiDomain

@MainActor
struct ShortcutTabPromotionResult {
    let tab: Tab
    let retirement: ShortcutLiveTabRetirementResult
}

@MainActor
struct ShortcutTabPromotionPlan {
    let pinID: UUID
    let tab: Tab
    let chosenEntry: LiveShortcutTabEntry?
    let selectedWindowStates: [BrowserWindowState]
    let targetSpaceID: UUID
    let targetIndex: Int?
    let runtime: RuntimePortRegistry?
    let placement: PreparedRegularTabPlacement
}

@MainActor
struct PreparedShortcutTabPromotion {
    let tab: Tab
    let retirement: PreparedShortcutLiveRetirementBatch
    let result: ShortcutLiveTabRetirementResult
}

@MainActor
struct PreparedShortcutTabGroupPromotion {
    let retirement: PreparedShortcutLiveRetirementBatch
}

@MainActor
enum ShortcutTabPromotionSplitTransition {
    case none
    case replaced(groupID: UUID, memberID: SplitMemberID)
    case removed(groupID: UUID, remainingGroup: SumiDomain.SplitGroup?)
}
