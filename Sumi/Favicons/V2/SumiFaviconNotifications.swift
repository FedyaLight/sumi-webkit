import Foundation
import SumiDomain

extension NSNotification.Name {
    static let faviconCacheUpdated = NSNotification.Name("FaviconCacheUpdatedNotification")
    static let faviconCacheUpdatedDomainKey = "SumiFaviconCacheUpdatedDomain"
    static let faviconCacheUpdatedPartitionKey = "SumiFaviconPartition"
}

enum SumiFaviconNotificationMatcher {
    static func update(
        _ notification: Notification,
        matches documentURL: URL?,
        partition: SumiFaviconPartition? = nil
    ) -> Bool {
        if let partition,
           let updatedPartition = notification.userInfo?[NSNotification.Name.faviconCacheUpdatedPartitionKey] as? String,
           updatedPartition != partition.storageComponent {
            return false
        }

        guard let updatedDomain = notification.userInfo?[NSNotification.Name.faviconCacheUpdatedDomainKey] as? String else {
            return true
        }
        guard let host = SumiSiteNormalizer().host(for: documentURL) else { return false }
        return host == SumiSiteNormalizer().host(fromRawHost: updatedDomain)
    }
}
