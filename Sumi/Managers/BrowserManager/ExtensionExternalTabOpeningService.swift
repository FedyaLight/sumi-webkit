import Foundation

/// Opens an extension-owned external URL from the exact physical source and
/// publishes extension Tab lifecycle only after structural creation succeeds.
@MainActor
final class ExtensionExternalTabOpeningService: ExtensionExternalTabOpening {
    private let sources: PhysicalWebViewSourceResolver
    private let tabs: PhysicalSourceTabOpeningService
    private weak var extensionTabs: (any ExtensionCreatedTabRegistering)?

    init(
        sources: PhysicalWebViewSourceResolver,
        tabs: PhysicalSourceTabOpeningService,
        extensionTabs: any ExtensionCreatedTabRegistering
    ) {
        self.sources = sources
        self.tabs = tabs
        self.extensionTabs = extensionTabs
    }

    func open(
        _ url: URL,
        from sourceWebView: FocusableWKWebView
    ) -> Bool {
        guard let extensionTabs,
              let source = sources.resolve(sourceWebView),
              let child = tabs.open(
                  url,
                  from: source,
                  selected: true,
                  foregroundLoadPolicy: .immediate
              )
        else {
            return false
        }
        extensionTabs.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
            child,
            reason: "ExtensionExternalTabOpeningService.open"
        )
        return true
    }
}
