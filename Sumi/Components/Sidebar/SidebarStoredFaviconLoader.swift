import SwiftUI

@MainActor
final class SidebarStoredFaviconLoader: ObservableObject {
    private struct CacheKey: Hashable {
        let launchURL: URL
        let partition: String
    }

    @Published private var refreshID = UUID()
    @Published private var loadedFavicons: [CacheKey: Image] = [:]

    func image(
        for launchURL: URL,
        partition: SumiFaviconPartition
    ) -> Image? {
        loadedFavicons[cacheKey(launchURL, partition)]
    }

    func loadKey(
        launchURL: URL,
        partition: SumiFaviconPartition,
        isEnabled: Bool = true,
        disabledID: String? = nil
    ) -> String {
        guard isEnabled else {
            return "disabled|\(disabledID ?? launchURL.absoluteString)|\(refreshID.uuidString)"
        }

        return [
            launchURL.absoluteString,
            partition.storageComponent,
            refreshID.uuidString,
        ].joined(separator: "|")
    }

    func invalidateIfNeeded(
        for notification: Notification,
        launchURL: URL,
        partition: SumiFaviconPartition
    ) {
        guard SumiFaviconNotificationMatcher.update(
            notification,
            matches: launchURL,
            partition: partition
        ) else { return }
        loadedFavicons[cacheKey(launchURL, partition)] = nil
        refreshID = UUID()
    }

    func load(
        launchURL: URL,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading,
        isCurrentLaunchURL: (URL) -> Bool
    ) async {
        guard let image = await TabFaviconStore.loadCachedLauncherImage(
            forDocumentURL: launchURL,
            partition: partition,
            imageReader: imageReader
        ),
              !Task.isCancelled,
              isCurrentLaunchURL(launchURL)
        else { return }

        loadedFavicons[cacheKey(launchURL, partition)] = Image(nsImage: image)
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
