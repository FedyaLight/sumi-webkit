import AppKit

@MainActor
enum SidebarLinkActions {
    static func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    static func presentSharePicker(
        for url: URL,
        source: SidebarTransientPresentationSource?,
        presentationActions: SidebarBrowserPresentationActions
    ) {
        if let source {
            presentationActions.presentSharingServicePicker([url], source)
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}
