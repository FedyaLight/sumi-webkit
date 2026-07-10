import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabWebViewMaterializer {
    private let browserContext: @MainActor () -> (any ExtensionTabWebViewHosting)?
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let runtimePreparation: any ExtensionWebViewRuntimePreparing
    private let controllerBinding: any ExtensionControllerBinding

    init(
        browserContext: @escaping @MainActor () -> (any ExtensionTabWebViewHosting)?,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        runtimePreparation: any ExtensionWebViewRuntimePreparing,
        controllerBinding: any ExtensionControllerBinding
    ) {
        self.browserContext = browserContext
        self.profileRuntime = profileRuntime
        self.runtime = runtime
        self.runtimePreparation = runtimePreparation
        self.controllerBinding = controllerBinding
    }

    func materializeNormalTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        targetWindow: BrowserWindowState?
    ) {
        guard isActive,
              tab.webExtensionContextOverride == nil,
              tab.requiresPrimaryWebView
        else {
            return
        }

        if let targetWindow {
            browserContext()?
                .materializeVisibleExtensionTabWebViewIfNeeded(
                    tab,
                    in: targetWindow
                )
        }
        prepareNormalTabWebView(
            tab,
            targetWindow: targetWindow
        )
    }

    func materializeExtensionOwnedTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        hasWindowSelection: Bool
    ) {
        guard tab.webExtensionContextOverride != nil,
              ExtensionUtils.isExtensionOwnedURL(tab.url),
              tab.isUnloaded
        else {
            return
        }
        guard isActive == false || hasWindowSelection == false else { return }
        tab.loadWebViewIfNeeded()
    }

    private func prepareNormalTabWebView(
        _ tab: Tab,
        targetWindow: BrowserWindowState?
    ) {
        let currentWebView: WKWebView?
        if let targetWindow {
            currentWebView = browserContext()?
                .extensionWindowOwnedWebView(for: tab, in: targetWindow.id)
        } else {
            currentWebView = controllerBinding
                .ownedUntrackedCurrentWebView(for: tab)
        }

        if let currentWebView,
           normalTabWebViewIsUsable(currentWebView, for: tab) {
            runtimePreparation.prepareWebViewForExtensionRuntime(
                currentWebView,
                currentURL: tab.url,
                reason: "ExtensionManager.extensionRequestedNormalTab"
            )
            return
        }

        let reason = "ExtensionManager.extensionRequestedNormalTab.replacement"
        _ = browserContext()?.replaceExtensionLiveWebView(
            for: tab,
            in: targetWindow,
            reason: reason,
            prepareConfiguration: { [weak tab] configuration in
                guard let tab,
                      let profileId = resolvedProfileId(for: tab)
                else {
                    return
                }
                runtimePreparation.prepareWebViewConfigForExtensionRuntime(
                    configuration,
                    profileId: profileId,
                    reason: "\(reason).configuration"
                )
            },
            prepareCommittedReplacement: { [weak tab] webView in
                guard let tab else { return }
                runtimePreparation.prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: tab.url,
                    reason: reason
                )
            },
            validate: { [weak tab] webView in
                guard let tab else { return false }
                return normalTabWebViewIsUsable(
                    webView,
                    for: tab
                )
            }
        )
    }

    private func normalTabWebViewIsUsable(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard let expectedController = controllerBinding
            .extensionController(for: tab),
              controllerBinding.attachExtensionControllerIfNeeded(
                  to: webView,
                  for: tab
              )
        else {
            return false
        }
        return webView.configuration.webExtensionController === expectedController
    }

    private func resolvedProfileId(for tab: Tab) -> UUID? {
        profileRuntime.resolvedProfileId(for: tab, runtime: runtime())
    }
}
