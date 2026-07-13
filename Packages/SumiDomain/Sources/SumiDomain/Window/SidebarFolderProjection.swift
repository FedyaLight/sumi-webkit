import Foundation

public struct SidebarFolderProjectionState: Equatable, Sendable {
    public var projectedChildIDs: [UUID] = []
    public var hasActiveProjection: Bool = false

    public init(
        projectedChildIDs: [UUID] = [],
        hasActiveProjection: Bool = false
    ) {
        self.projectedChildIDs = projectedChildIDs
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
