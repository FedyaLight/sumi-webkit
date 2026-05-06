import AppKit
import SwiftUI

enum SumiCommandMenuLabels {
    static func bookmarkTitle(for entity: SumiBookmarkEntity) -> String {
        let displayTitle = entity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? entity.displayURL
            : entity.title
        let maxLength = 80
        guard displayTitle.count > maxLength else { return displayTitle }
        return String(displayTitle.prefix(maxLength - 1)) + "…"
    }

    static func recentlyClosedTitle(for item: RecentlyClosedItem) -> String {
        switch item {
        case .tab(let tab):
            return tab.title.isEmpty ? tab.url.absoluteString : tab.title
        case .window(let window):
            return window.title.isEmpty ? "Window" : window.title
        }
    }

    static func site(_ title: String, url: URL?) -> some View {
        Label {
            Text(title)
        } icon: {
            menuIcon(SumiFaviconResolver.menuImage(for: url))
        }
    }

    static func system(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            menuIcon(SumiFaviconResolver.menuSystemImage(systemImage))
        }
    }

    private static func menuIcon(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: 16, height: 16)
    }
}
