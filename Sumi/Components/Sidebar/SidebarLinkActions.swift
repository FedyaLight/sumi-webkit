import AppKit

@MainActor
enum SidebarLinkActions {
    static func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    static func copyLinkAsMarkdown(title: String, url: URL) {
        let escapedTitle = title.replacingOccurrences(of: "]", with: "\\]")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "[\(escapedTitle)](\(url.absoluteString))",
            forType: .string
        )
    }

    static func presentSharePicker(
        for url: URL,
        source: SidebarTransientPresentationSource?,
        presentation: BrowserNativeDialogPresentationOwner
    ) {
        if let source {
            presentation.presentSharingServicePicker([url], source: source)
            return
        }
        presentSharePicker(for: [url])
    }

    static func presentSharePicker(for urls: [URL]) {
        guard !urls.isEmpty, let contentView = NSApp.keyWindow?.contentView else {
            return
        }
        let picker = NSSharingServicePicker(items: urls)
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}
