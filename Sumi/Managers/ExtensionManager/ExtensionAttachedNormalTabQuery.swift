import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Read-only normal-tab projection for diagnostics and UI routing.
    @MainActor
    final class NormalTabQuery {
        struct TabEnvironment {
            let adapters: ExtensionAdapterCatalog
            let publishedTabs: ExtensionPublishedNormalTabQuery
            let profiles: ExtensionTabProfileResolution
        }

        struct ControllerEnvironment {
            let contextCompatibility: ExtensionContextTabCompatibilityQuery
            let webViews: ExtensionExactTabWebViewQuery
            let tabWebViewResolver: ExtensionTabWebViewResolver
            let controllers: ExtensionExistingExactTabControllerQuery
        }

        struct BrowserEnvironment {
            let windows: BrowserExtensionWindowQueryAdapter
            let webViews: BrowserExtensionWebViewAdapter
            let profileQuery: ExtensionBrowserProfileQuery
        }

        struct Environment {
            let tabs: TabEnvironment
            let controller: ControllerEnvironment
            let browser: BrowserEnvironment
        }

        struct TargetSnapshot {
            let contextMatches: Bool
            let isPublished: Bool
            let hasStableAdapter: Bool
            let liveWebView: WKWebView?
            let extensionWebView: WKWebView?
            let expectedController: WKWebExtensionController?
        }

        private let attachedEnvironment: @MainActor () -> Environment?

        init(attachment: ExtensionBrowserAttachmentAuthority) {
            attachedEnvironment = { [weak attachment] in
                attachment?.normalTabQueryEnvironment()
            }
        }

        func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
            attachedEnvironment()?.tabs.adapters.stableAdapter(for: tab)
        }

        func isPublished(_ tab: Tab) -> Bool {
            attachedEnvironment()?.tabs.publishedTabs
                .containsPublishedTab(tab) ?? false
        }

        func context(
            _ context: WKWebExtensionContext,
            matches tab: Tab
        ) -> Bool {
            attachedEnvironment()?.controller.contextCompatibility.matches(
                tab,
                context: context
            ) ?? false
        }

        func liveWebView(for tab: Tab) -> WKWebView? {
            attachedEnvironment()?.controller.webViews.liveWebView(for: tab)
        }

        func liveWebViews(for tab: Tab) -> [WKWebView] {
            attachedEnvironment()?.browser.webViews
                .extensionLiveWebViews(for: tab) ?? []
        }

        func currentTab() -> Tab? {
            attachedEnvironment()?.browser.windows
                .currentExtensionTabForActiveWindow()
        }

        func profileID(for tab: Tab) -> UUID? {
            attachedEnvironment()?.tabs.profiles.profileID(for: tab)
        }

        func currentBrowserProfileID() -> UUID? {
            attachedEnvironment()?.browser.profileQuery.currentProfile()?.id
        }

        func targetSnapshot(
            tab: Tab,
            context: WKWebExtensionContext
        ) -> TargetSnapshot? {
            guard let environment = attachedEnvironment() else { return nil }
            return TargetSnapshot(
                contextMatches: environment.controller.contextCompatibility
                    .matches(tab, context: context),
                isPublished: environment.tabs.publishedTabs
                    .containsPublishedTab(tab),
                hasStableAdapter:
                    environment.tabs.adapters.stableAdapter(for: tab) != nil,
                liveWebView: environment.controller.webViews
                    .liveWebView(for: tab),
                extensionWebView: environment.controller.tabWebViewResolver
                    .extensionWebView(
                        for: tab,
                        extensionContext: context
                    ),
                expectedController: environment.controller.controllers
                    .existingController(for: tab)
            )
        }
    }
}
