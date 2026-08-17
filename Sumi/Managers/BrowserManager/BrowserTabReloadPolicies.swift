import Foundation
import SumiDomain
import WebKit

@MainActor
struct BrowserSafariContentBlockerPolicy:
    SafariContentBlockerPolicyReading {
    let extensions: SumiExtensionsModule

    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        extensions.safariContentBlockerAttachmentState(for: url)
    }
}

@MainActor
struct BrowserProtectionPolicy: ProtectionPolicyReading {
    let protection: SumiProtectionCoordinator

    func attachmentState(
        for url: URL?
    ) -> SumiProtectionAttachmentState {
        protection.desiredAttachmentState(for: url)
    }

    func surfaceHost(for url: URL?) -> String? {
        protection.surfaceEligibility(for: url).normalizedSiteHost
    }

}

@MainActor
struct BrowserAutoplayPolicy: AutoplayPolicyReading {
    let configuration: BrowserConfiguration
    let permissionController: any SumiRuntimePermissionControlling

    func policy(
        for url: URL?,
        profile: Profile?
    ) -> SumiAutoplayPolicy {
        guard let profile else { return .default }
        return configuration.resolvedAutoplayPolicy(
            for: url,
            profile: profile
        )
    }

    func evaluateChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult {
        permissionController.evaluateAutoplayPolicyChange(
            requestedState,
            for: webView
        )
    }
}
