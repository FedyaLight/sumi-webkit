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

struct SumiImportRuntimeMutationSession: Equatable, Hashable {
    let id = UUID()
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
    func beginMutation(
        covering candidates: [SumiImportRuntimeState]
    ) throws -> SumiImportRuntimeMutationSession
    func install(
        _ state: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws
    func restore(
        _ checkpoint: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws
    func endMutation(_ session: SumiImportRuntimeMutationSession) -> Bool
}

@MainActor
protocol SumiImportProfileSelection: AnyObject {
    var currentProfile: Profile? { get }
    func applyImportProfileSelection(_ profile: Profile?)
}
