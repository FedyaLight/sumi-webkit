import Foundation

enum SumiLiveFolderItemMerge {
    /// Zen keeps surviving tabs in their current order and appends only newly
    /// discovered results. This also prevents rows from jumping when a
    /// provider changes result ordering between refreshes.
    static func retainingExistingOrder(
        _ fetchedItems: [SumiLiveFolderItem],
        with cachedItems: [SumiLiveFolderItem],
        at date: Date
    ) -> [SumiLiveFolderItem] {
        let fetchedIDs = Set(fetchedItems.map(\.id))
        var retainedIDs = Set<String>()
        let retained = cachedItems.compactMap { cached -> SumiLiveFolderItem? in
            guard fetchedIDs.contains(cached.id) else { return nil }
            retainedIDs.insert(cached.id)
            var item = cached
            item.lastSeenAt = date
            return item
        }
        let appended = fetchedItems.compactMap { fetched -> SumiLiveFolderItem? in
            guard retainedIDs.insert(fetched.id).inserted else { return nil }
            var item = fetched
            item.firstSeenAt = date
            item.lastSeenAt = date
            return item
        }
        return retained + appended
    }
}
