import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func noteChromeMV3ContentScriptLifecycleEntrypoint(
        tab: Tab,
        webView: WKWebView?,
        url: URL?,
        entrypoint: ChromeMV3ContentScriptLifecycleEntrypoint,
        reason: String
    ) {
        let profileID = tab.resolveProfile()?.id.uuidString ?? "unknown-profile"
        let surface: ChromeMV3WebViewSurface =
            webView?.configuration.sumiIsNormalTabWebViewConfiguration == true
                ? .normalTab
                : .helperWebView
        extensionRuntimeTrace(
            "[content-script-lifecycle] entrypoint=\(entrypoint.rawValue) tab=\(tab.id.uuidString) profile=\(profileID) url=\((url ?? webView?.url)?.absoluteString ?? "nil") surface=\(surface.rawValue) normalTabConfig=\(webView?.configuration.sumiIsNormalTabWebViewConfiguration == true) developerPreviewOnly=true extensionScoped=true explicitProfileTabGateRequired=true noGlobalRuntime=true reason=\(reason)"
        )
    }
}
