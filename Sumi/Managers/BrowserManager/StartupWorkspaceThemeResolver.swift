import Foundation
import OSLog
import SwiftData

@MainActor
enum StartupWorkspaceThemeResolver {
    private static let logger = Logger.sumi(category: "WorkspaceTheme")

    static func resolve(
        userDefaults: UserDefaults = .standard,
        lastWindowSessionKey: String,
        modelContext: ModelContext
    ) -> WorkspaceTheme? {
        guard let snapshot = WindowSessionSnapshotStore(
            key: lastWindowSessionKey,
            userDefaults: userDefaults
        ).loadSnapshot()?.snapshot,
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
        let spaces: [SpaceEntity]
        do {
            spaces = try modelContext.fetch(FetchDescriptor<SpaceEntity>())
        } catch {
            logger.error(
                "Failed to fetch spaces for startup workspace theme: \(String(describing: error), privacy: .public)"
            )
            return nil
        }

        guard let space = spaces.first(where: { $0.id == spaceId }) else {
            return nil
        }

        return decodeWorkspaceTheme(from: space)
    }

    static func decodeWorkspaceTheme(from space: SpaceEntity) -> WorkspaceTheme {
        WorkspaceTheme.decode(space.workspaceThemeData ?? Data()) ?? .default
    }
}
