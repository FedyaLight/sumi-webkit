import Foundation
import SumiDomain

@MainActor
final class SplitShortcutMemberRestorePreparationService {
    private let splitGroups: SplitGroupStore
    private let pins: ShortcutPinCollectionStateOwner
    private let liveShortcuts: LiveShortcutTabRegistry
    private let runtimeConnection: TabRuntimePortConnection
    private let launcherPlacement: ShortcutSplitLauncherPlacementService

    init(
        splitGroups: SplitGroupStore,
        pins: ShortcutPinCollectionStateOwner,
        liveShortcuts: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        launcherPlacement: ShortcutSplitLauncherPlacementService
    ) {
        self.splitGroups = splitGroups
        self.pins = pins
        self.liveShortcuts = liveShortcuts
        self.runtimeConnection = runtimeConnection
        self.launcherPlacement = launcherPlacement
    }

    func prepare(
        _ memberID: SplitMemberID,
        from group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) -> SplitShortcutMemberRestorePreparation? {
        guard splitGroups.group(id: group.id) == group else {
            return nil
        }
        guard let resolution = SplitShortcutMemberResolver.resolve(
                  memberID: memberID,
                  in: group,
                  windowState: windowState,
                  pins: pins
              ) else { return nil }
        guard let launcher = launcherPlacement.prepareRestorations(
                  for: [resolution.member]
              ) else { return nil }

        let sourceGroups = splitGroups.groups
        guard let index = sourceGroups.firstIndex(of: group) else { return nil }
        var replacementGroups = sourceGroups
        if let remaining = group.removingMember(memberID) {
            replacementGroups[index] = remaining
        } else {
            replacementGroups.remove(at: index)
        }
        let retiringPinID: UUID?
        if preserveLiveInstance {
            retiringPinID = nil
        } else {
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            let liveTab = liveShortcuts.tab(
                for: pinID, in: windowState.id
            )
            guard liveTab == nil || runtimeConnection.current != nil
            else { return nil }
            retiringPinID = liveTab == nil ? nil : pinID
        }

        return SplitShortcutMemberRestorePreparation(
            sourceGroups: sourceGroups,
            replacementGroups: replacementGroups,
            retiringPinID: retiringPinID,
            launcher: launcher
        )
    }
}
