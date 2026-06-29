import Foundation
import SwiftData

@MainActor
enum StartupWorkspaceThemeResolver {
    static func resolve(
        userDefaults: UserDefaults = .standard,
        lastWindowSessionKey: String,
        modelContext: ModelContext
    ) -> WorkspaceTheme? {
        guard let snapshot = WindowSessionBootstrapOverride.resolvedSnapshot(
            userDefaults: userDefaults,
            lastWindowSessionKey: lastWindowSessionKey
        )?.snapshot,
              let currentSpaceId = snapshot.currentSpaceId
        else {
            return nil
        }

        return workspaceTheme(for: currentSpaceId, modelContext: modelContext)
    }

    static func workspaceTheme(
        for spaceId: UUID,
        modelContext: ModelContext
    ) -> WorkspaceTheme? {
        guard let spaces = try? modelContext.fetch(FetchDescriptor<SpaceEntity>()),
              let space = spaces.first(where: { $0.id == spaceId })
        else {
            return nil
        }

        return decodeWorkspaceTheme(from: space)
    }

    static func decodeWorkspaceTheme(from space: SpaceEntity) -> WorkspaceTheme {
        WorkspaceTheme.decode(space.workspaceThemeData ?? Data()) ?? .default
    }
}
