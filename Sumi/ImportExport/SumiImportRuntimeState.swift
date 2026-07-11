import Foundation
import SumiDomain

@MainActor
struct SumiImportRuntimeState {
    let profiles: [Profile]
    let currentProfile: Profile?
    let spaces: [Space]
    let tabsBySpace: [UUID: [Tab]]
    let foldersBySpace: [UUID: [TabFolder]]
    let pinnedByProfile: [UUID: [ShortcutPin]]
    let spacePinnedShortcuts: [UUID: [ShortcutPin]]
    let pendingPinnedWithoutProfile: [ShortcutPin]
    let splitGroups: [SplitGroup]
    let currentSpace: Space?
    let currentTab: Tab?
}

@MainActor
protocol SumiImportRuntimeMaterializing: AnyObject {
    func materialize(
        _ plan: SumiImportPlan,
        preserving checkpoint: SumiImportRuntimeState
    ) throws -> SumiImportRuntimeState
}

@MainActor
protocol SumiImportRuntimeMutating: AnyObject {
    func checkpoint() -> SumiImportRuntimeState
    func install(_ state: SumiImportRuntimeState) async throws
    func restore(_ checkpoint: SumiImportRuntimeState) async throws
}

@MainActor
protocol SumiImportProfileSelection: AnyObject {
    var currentProfile: Profile? { get set }
}
