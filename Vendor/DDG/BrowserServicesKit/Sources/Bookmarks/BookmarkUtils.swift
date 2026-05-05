//
//  BookmarkUtils.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import CoreData

public struct BookmarkUtils {

    public static func fetchRootFolder(_ context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), BookmarkEntity.Constants.rootFolderID)
        request.returnsObjectsAsFaults = false

        let result = (try? context.fetch(request)) ?? []

        // We cannot use simply sort descriptor as this is to-many on both sides of a relationship.
        return result.sorted(by: { ($0.children?.count ?? 0) > ($1.children?.count ?? 0) }).first
    }

    public static func fetchFavoritesFolder(withUUID uuid: String, in context: NSManagedObjectContext) -> BookmarkEntity? {
        assert(BookmarkEntity.isValidFavoritesFolderID(uuid))

        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), uuid)
        request.returnsObjectsAsFaults = false

        let result = (try? context.fetch(request)) ?? []

        // We cannot use simply sort descriptor as this is to-many on both sides of a relationship.
        return result.sorted(by: { ($0.favorites?.count ?? 0) > ($1.favorites?.count ?? 0) }).first
    }

    public static func prepareFoldersStructure(in context: NSManagedObjectContext) {

        if fetchRootFolder(context) == nil {
            insertRootFolder(uuid: BookmarkEntity.Constants.rootFolderID, into: context)
        }

        for uuid in BookmarkEntity.Constants.favoriteFoldersIDs where fetchFavoritesFolder(withUUID: uuid, in: context) == nil {
            insertRootFolder(uuid: uuid, into: context)
        }
    }

    public static func fetchAllBookmarksUUIDs(in context: NSManagedObjectContext) -> [String] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "BookmarkEntity")
        request.predicate = NSPredicate(format: "%K == NO AND %K == NO AND (%K == NO OR %K == nil)",
                                        #keyPath(BookmarkEntity.isFolder),
                                        #keyPath(BookmarkEntity.isPendingDeletion),
                                        #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub))
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [#keyPath(BookmarkEntity.uuid)]

        let result = (try? context.fetch(request) as? [[String: Any]]) ?? []
        return result.compactMap { $0[#keyPath(BookmarkEntity.uuid)] as? String }
    }

    // MARK: Internal

    @discardableResult
    static func insertRootFolder(uuid: String, into context: NSManagedObjectContext) -> BookmarkEntity {
        let folder = BookmarkEntity(entity: BookmarkEntity.entity(in: context),
                                    insertInto: context)
        folder.uuid = uuid
        folder.title = uuid
        folder.isFolder = true

        return folder
    }
}
