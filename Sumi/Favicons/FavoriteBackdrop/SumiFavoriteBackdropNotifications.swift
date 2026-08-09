import Foundation

extension Notification.Name {
    static let favoriteBackdropUpdated = Notification.Name(
        "SumiFavoriteBackdropUpdated"
    )
    static let favoriteBackdropReferenceKey = "SumiFavoriteBackdropReferenceKey"
    static let favoriteBackdropPartitionKey = "SumiFavoriteBackdropPartition"
}

enum SumiFavoriteBackdropNotificationMatcher {
    static func update(
        _ notification: Notification,
        matches documentURL: URL,
        partition: SumiFaviconPartition
    ) -> Bool {
        guard let referenceKey = SumiFaviconLookupKey.referenceKey(
            for: documentURL
        ) else { return false }
        let userInfo = notification.userInfo
        return userInfo?[Notification.Name.favoriteBackdropReferenceKey]
            as? String == referenceKey
            && userInfo?[Notification.Name.favoriteBackdropPartitionKey]
            as? String == partition.storageComponent
    }
}
