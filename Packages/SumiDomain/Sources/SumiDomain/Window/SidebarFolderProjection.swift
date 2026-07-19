import Foundation

public struct SidebarFolderProjectionState: Equatable, Sendable {
    /// Items (launcher pins or split groups) the user made sticky while the
    /// folder is collapsed: selected at collapse time, or activated while
    /// collapsed. Cleared on expand; pruned when an item leaves the folder.
    public var stickyItemIDs: [UUID] = []
    /// Whether the collapsed folder currently shows sticky rows.
    public var hasActiveProjection: Bool = false

    public init(
        stickyItemIDs: [UUID] = [],
        hasActiveProjection: Bool = false
    ) {
        self.stickyItemIDs = stickyItemIDs
        self.hasActiveProjection = hasActiveProjection
    }

    public static let empty = SidebarFolderProjectionState()
}

public struct SidebarFolderProjectionStore: Equatable, Sendable {
    private var projectionsByFolderID: [UUID: SidebarFolderProjectionState] = [:]

    public init() {}

    public func projection(for folderID: UUID) -> SidebarFolderProjectionState {
        projectionsByFolderID[folderID] ?? .empty
    }

    public mutating func setProjection(
        _ projection: SidebarFolderProjectionState,
        for folderID: UUID
    ) {
        if projection == .empty {
            projectionsByFolderID.removeValue(forKey: folderID)
            return
        }
        projectionsByFolderID[folderID] = projection
    }
}
