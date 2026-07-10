import Foundation
import SwiftData

enum TabStoreRecordQueries {
    static func tabs(in context: ModelContext, ids: Set<UUID>) throws -> [UUID: TabEntity] {
        guard ids.isEmpty == false else { return [:] }
        let targetIds = ids
        let predicate = #Predicate<TabEntity> { targetIds.contains($0.id) }
        let tabs = try context.fetch(FetchDescriptor<TabEntity>(predicate: predicate))
        return Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func folders(in context: ModelContext, ids: Set<UUID>) throws -> [UUID: FolderEntity] {
        guard ids.isEmpty == false else { return [:] }
        let targetIds = ids
        let predicate = #Predicate<FolderEntity> { targetIds.contains($0.id) }
        let folders = try context.fetch(FetchDescriptor<FolderEntity>(predicate: predicate))
        return Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func spaces(in context: ModelContext, ids: Set<UUID>) throws -> [UUID: SpaceEntity] {
        guard ids.isEmpty == false else { return [:] }
        let targetIds = ids
        let predicate = #Predicate<SpaceEntity> { targetIds.contains($0.id) }
        let spaces = try context.fetch(FetchDescriptor<SpaceEntity>(predicate: predicate))
        return Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func tabs(in context: ModelContext, spaceId: UUID) throws -> [TabEntity] {
        let targetSpaceId = spaceId
        let predicate = #Predicate<TabEntity> { $0.spaceId == targetSpaceId }
        return try context.fetch(FetchDescriptor<TabEntity>(predicate: predicate))
    }

    static func folders(in context: ModelContext, spaceId: UUID) throws -> [FolderEntity] {
        let targetSpaceId = spaceId
        let predicate = #Predicate<FolderEntity> { $0.spaceId == targetSpaceId }
        return try context.fetch(FetchDescriptor<FolderEntity>(predicate: predicate))
    }
}
