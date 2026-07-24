import Foundation
import SumiDomain
import SwiftUI

struct CommandPaletteSpacePresentation: Equatable {
    let id: UUID
    let title: String
}

/// Reads Space presentation and resolves execution from durable identity at
/// activation time. Ordinal shortcuts never leak into palette identity.
@MainActor
final class CommandPaletteSpaceCatalog {
    private let spaces: TabSpaceCollectionStateOwner

    init(spaces: TabSpaceCollectionStateOwner) {
        self.spaces = spaces
    }

    func presentations(
        in windowState: BrowserWindowState
    ) -> [CommandPaletteSpacePresentation] {
        guard !windowState.isIncognito else { return [] }
        let currentProfileID = windowState.currentSpaceId
            .flatMap { spaces.space(with: $0)?.profileId }
            ?? windowState.currentProfileId

        return spaces.spaces.compactMap { space in
            guard space.profileId == currentProfileID,
                  SpaceSwitchShortcuts.action(
                    forSpaceAt: spaces.index(of: space.id) ?? -1
                  ) != nil else {
                return nil
            }
            return CommandPaletteSpacePresentation(
                id: space.id,
                title: space.name
            )
        }
    }

    func shortcutAction(
        for id: UUID,
        in windowState: BrowserWindowState
    ) -> ShortcutAction? {
        guard presentations(in: windowState).contains(where: {
            $0.id == id
        }), let index = spaces.index(of: id) else {
            return nil
        }
        return SpaceSwitchShortcuts.action(forSpaceAt: index)
    }

    func accentColor(in windowState: BrowserWindowState) -> Color? {
        guard let currentSpaceID = windowState.currentSpaceId,
              let space = spaces.space(with: currentSpaceID) else {
            return nil
        }
        return Color(nsColor: space.color)
    }
}
