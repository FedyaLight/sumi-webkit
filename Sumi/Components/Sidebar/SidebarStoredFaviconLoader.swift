import SwiftUI

@MainActor
final class SidebarStoredFaviconLoader: ObservableObject {
    private struct LoadedFavicon {
        let launchURL: URL
        let image: Image
    }

    @Published private var refreshID = UUID()
    @Published private var loadedFavicon: LoadedFavicon?

    func image(for launchURL: URL) -> Image? {
        loadedFavicon?.launchURL == launchURL ? loadedFavicon?.image : nil
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
        launchURL: URL
    ) {
        guard PinnedTileAccentResolver.faviconUpdate(notification, matches: launchURL) else { return }
        loadedFavicon = nil
        refreshID = UUID()
    }

    func load(
        launchURL: URL,
        partition: SumiFaviconPartition,
        isCurrentLaunchURL: (URL) -> Bool
    ) async {
        guard let image = await TabFaviconStore.loadCachedLauncherImage(
            forDocumentURL: launchURL,
            partition: partition
        ),
              !Task.isCancelled,
              isCurrentLaunchURL(launchURL)
        else { return }

        loadedFavicon = LoadedFavicon(
            launchURL: launchURL,
            image: Image(nsImage: image)
        )
    }
}
