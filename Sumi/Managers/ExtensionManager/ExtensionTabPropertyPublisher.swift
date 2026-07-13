import Foundation
import WebKit

/// Publishes coalesced Tab property changes only after the exact settled Tab,
/// adapter, controller, profile and optional live WebView have been proven.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabPropertyPublisher {
    private weak var publishedTabs: (any ExtensionPublishedTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var adapters: ExtensionBrowserAdapterStore?
    private weak var liveWebViews: (any ExtensionTabLiveWebViewQuery)?
    private let didPublish:
        ((UUID, WKWebExtension.TabChangedProperties) -> Void)?

    init(
        publishedTabs: any ExtensionPublishedTabQuery,
        profiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime,
        adapters: ExtensionBrowserAdapterStore,
        liveWebViews: any ExtensionTabLiveWebViewQuery,
        didPublish: ((UUID, WKWebExtension.TabChangedProperties) -> Void)? = nil
    ) {
        self.publishedTabs = publishedTabs
        self.profiles = profiles
        self.profileRuntime = profileRuntime
        self.adapters = adapters
        self.liveWebViews = liveWebViews
        self.didPublish = didPublish
    }

    func publishChange(
        for tab: Tab,
        requested: WKWebExtension.TabChangedProperties
    ) {
        guard publishedTabs?.containsPublishedTab(tab) == true,
              let profileID = profiles?.profileID(for: tab),
              let controller = profileRuntime?.controller(for: profileID),
              let adapter = adapters?.existingTabAdapter(for: tab.id),
              adapter.represents(tab),
              publishedTabs?.containsPublishedTab(tab) == true
        else {
            return
        }

        let liveURL: URL?
        if requested.contains(.URL) {
            let webView = liveWebViews?.extensionLiveWebView(for: tab)
            guard webView == nil
                || (webView as? FocusableWKWebView)?.owningTab === tab
            else {
                return
            }
            liveURL = webView?.url ?? tab.url
        } else {
            liveURL = nil
        }

        guard publishedTabs?.containsPublishedTab(tab) == true,
              profiles?.profileID(for: tab) == profileID,
              profileRuntime?.controller(for: profileID) === controller,
              adapters?.existingTabAdapter(for: tab.id) === adapter,
              adapter.represents(tab)
        else {
            return
        }

        var changed: WKWebExtension.TabChangedProperties = []
        if requested.contains(.URL),
           tab.extensionPageRuntimeOwner.recordReportedURLIfChanged(liveURL) {
            changed.insert(.URL)
        }
        if requested.contains(.loading),
           tab.extensionPageRuntimeOwner
           .recordReportedLoadingCompleteIfChanged(!tab.isLoading) {
            changed.insert(.loading)
        }
        if requested.contains(.title) {
            let title = tab.name.isEmpty ? nil : tab.name
            if tab.extensionPageRuntimeOwner
                .recordReportedTitleIfChanged(title) {
                changed.insert(.title)
            }
        }
        guard changed.isEmpty == false else { return }

        // The report state is claimed immediately before the synchronous
        // callback so reentrant model updates cannot publish the same value.
        controller.didChangeTabProperties(changed, for: adapter)
        didPublish?(tab.id, changed)
    }
}
