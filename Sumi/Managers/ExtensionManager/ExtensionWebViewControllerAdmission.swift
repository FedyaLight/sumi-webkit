import Foundation
import WebKit

@available(macOS 15.5, *)
enum ExtensionWebViewControllerAdmissionOutcome: Equatable {
    case alreadyBound
    case requiresRebuild
    case rejected

    var isUsable: Bool {
        self == .alreadyBound
    }
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWebViewControllerAdmitting: AnyObject {
    func admit(
        _ controller: WKWebExtensionController,
        profileID: UUID,
        to webView: WKWebView,
        for tab: Tab
    ) -> ExtensionWebViewControllerAdmissionOutcome
}

/// Mutates one exact WebView using an explicitly supplied existing controller.
/// It never provisions controllers, scans Tabs, or initiates rebuilds.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWebViewControllerAdmission:
    ExtensionWebViewControllerAdmitting {
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var webViews: ExtensionExactTabWebViewQuery?
    private weak var preludeInstaller: (any ExtensionPreludeInstalling)?

    init(
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime,
        webViews: ExtensionExactTabWebViewQuery,
        preludeInstaller: any ExtensionPreludeInstalling
    ) {
        self.tabs = tabs
        self.profiles = profiles
        self.profileRuntime = profileRuntime
        self.webViews = webViews
        self.preludeInstaller = preludeInstaller
    }

    func admit(
        _ controller: WKWebExtensionController,
        profileID: UUID,
        to webView: WKWebView,
        for tab: Tab
    ) -> ExtensionWebViewControllerAdmissionOutcome {
        guard isCurrent(
            tab,
            webView: webView,
            profileID: profileID,
            controller: controller
        ) else { return .rejected }

        if let current = webView.configuration.webExtensionController {
            guard current === controller else { return .requiresRebuild }
            installPreludes(into: webView, profileID: profileID)
            return isBoundAndCurrent(
                tab,
                webView: webView,
                profileID: profileID,
                controller: controller
            ) ? .alreadyBound : .rejected
        }

        return .requiresRebuild
    }

    private func isCurrent(
        _ tab: Tab,
        webView: WKWebView,
        profileID: UUID,
        controller: WKWebExtensionController
    ) -> Bool {
        tab.isEphemeral == false
            && tabs?.extensionTab(for: tab.id) === tab
            && (webView as? FocusableWKWebView)?.owningTab === tab
            && webViews?.contains(webView, for: tab) == true
            && profiles?.profileID(for: tab) == profileID
            && profileRuntime?.controller(for: profileID) === controller
    }

    private func installPreludes(into webView: WKWebView, profileID: UUID) {
        preludeInstaller?.installPreludes(
            into: webView.configuration.userContentController,
            profileId: profileID
        )
    }

    private func isBoundAndCurrent(
        _ tab: Tab,
        webView: WKWebView,
        profileID: UUID,
        controller: WKWebExtensionController
    ) -> Bool {
        isCurrent(
            tab,
            webView: webView,
            profileID: profileID,
            controller: controller
        ) && webView.configuration.webExtensionController === controller
    }
}
