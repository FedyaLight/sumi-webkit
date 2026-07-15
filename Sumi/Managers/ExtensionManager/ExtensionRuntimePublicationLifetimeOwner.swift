import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimePublicationLifetimeOwner {
    private let attachment: ExtensionBrowserAttachmentAuthority
    private let browserEvents: ExtensionBrowserAttachmentAuthority.BrowserEvents
    private let reloads: ExtensionBrowserAttachmentAuthority.Reloads
    private let attacher: ExtensionBrowserRuntimeAttacher

    init(
        attachment: ExtensionBrowserAttachmentAuthority,
        browserEvents: ExtensionBrowserAttachmentAuthority.BrowserEvents,
        reloads: ExtensionBrowserAttachmentAuthority.Reloads,
        attacher: ExtensionBrowserRuntimeAttacher
    ) {
        self.attachment = attachment
        self.browserEvents = browserEvents
        self.reloads = reloads
        self.attacher = attacher
    }
}
