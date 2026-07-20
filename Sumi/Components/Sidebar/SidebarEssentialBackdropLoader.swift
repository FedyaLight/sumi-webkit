import Observation
import SwiftUI

@MainActor
@Observable
final class SidebarEssentialBackdropLoader {
    private struct CacheKey: Hashable {
        let launchURL: URL
        let partition: String
    }

    private var refreshID = UUID()
    private var images: [CacheKey: Image] = [:]

    func image(
        for launchURL: URL,
        partition: SumiFaviconPartition
    ) -> Image? {
        images[cacheKey(launchURL, partition)]
    }

    func loadKey(
        launchURL: URL,
        partition: SumiFaviconPartition,
        isEnabled: Bool
    ) -> String {
        [
            launchURL.absoluteString,
            partition.storageComponent,
            isEnabled ? "enabled" : "disabled",
            refreshID.uuidString,
        ].joined(separator: "|")
    }

    func invalidateIfNeeded(
        for notification: Notification,
        launchURL: URL,
        partition: SumiFaviconPartition
    ) {
        guard SumiEssentialBackdropNotificationMatcher.update(
            notification,
            matches: launchURL,
            partition: partition
        ) else { return }
        images[cacheKey(launchURL, partition)] = nil
        refreshID = UUID()
    }

    func load(
        launchURL: URL,
        partition: SumiFaviconPartition,
        reader: any BrowserEssentialBackdropReading,
        isCurrentLaunchURL: (URL) -> Bool
    ) async {
        guard let image = await reader.loadBackdrop(
            for: launchURL,
            partition: partition
        ), !Task.isCancelled, isCurrentLaunchURL(launchURL)
        else { return }
        images[cacheKey(launchURL, partition)] = Image(nsImage: image)
    }

    private func cacheKey(
        _ launchURL: URL,
        _ partition: SumiFaviconPartition
    ) -> CacheKey {
        CacheKey(
            launchURL: launchURL,
            partition: partition.storageComponent
        )
    }
}
