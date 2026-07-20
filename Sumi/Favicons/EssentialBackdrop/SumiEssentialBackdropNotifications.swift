import Foundation

extension Notification.Name {
    static let essentialBackdropUpdated = Notification.Name(
        "SumiEssentialBackdropUpdated"
    )
    static let essentialBackdropReferenceKey = "SumiEssentialBackdropReferenceKey"
    static let essentialBackdropPartitionKey = "SumiEssentialBackdropPartition"
}

enum SumiEssentialBackdropNotificationMatcher {
    static func update(
        _ notification: Notification,
        matches documentURL: URL,
        partition: SumiFaviconPartition
    ) -> Bool {
        guard let referenceKey = SumiFaviconLookupKey.referenceKey(
            for: documentURL
        ) else { return false }
        let userInfo = notification.userInfo
        return userInfo?[Notification.Name.essentialBackdropReferenceKey]
            as? String == referenceKey
            && userInfo?[Notification.Name.essentialBackdropPartitionKey]
            as? String == partition.storageComponent
    }
}
