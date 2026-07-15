import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowAdapterIdentityProjection {
    private let contextPublications: ExtensionContextPublicationQuery
    private let profileIDForWindow: @MainActor (BrowserWindowState) -> UUID?
    private let profileIDForTab: @MainActor (Tab) -> UUID?
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?

    init(
        contextPublications: ExtensionContextPublicationQuery,
        profileIDForWindow: @escaping @MainActor (BrowserWindowState) -> UUID?,
        profileIDForTab: @escaping @MainActor (Tab) -> UUID?,
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?
    ) {
        self.contextPublications = contextPublications
        self.profileIDForWindow = profileIDForWindow
        self.profileIDForTab = profileIDForTab
        self.extensionIDForContext = extensionIDForContext
    }

    func profileID(for context: WKWebExtensionContext) -> UUID? {
        contextPublications.currentIdentity(for: context)?.profileID
    }

    func profileID(for window: BrowserWindowState) -> UUID? {
        profileIDForWindow(window)
    }

    func profileID(for tab: Tab) -> UUID? { profileIDForTab(tab) }

    func extensionID(for context: WKWebExtensionContext) -> String? {
        extensionIDForContext(context)
    }
}
