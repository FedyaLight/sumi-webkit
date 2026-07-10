import Foundation

final class SumiFaviconUpdatePublisher: @unchecked Sendable {
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func publish(
        domain: String?,
        partition: SumiFaviconPartition?,
        revision: String?
    ) {
        Task { @MainActor [notificationCenter] in
            var userInfo: [AnyHashable: Any] = [:]
            if let domain {
                userInfo[NSNotification.Name.faviconCacheUpdatedDomainKey] = domain
            }
            if let partition {
                userInfo[NSNotification.Name.faviconCacheUpdatedPartitionKey] = partition.storageComponent
            }
            if let revision {
                userInfo["SumiFaviconRevision"] = revision
            }
            notificationCenter.post(
                name: .faviconCacheUpdated,
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
