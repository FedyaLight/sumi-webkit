import Foundation

@MainActor
enum BrowserAuthenticationRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> AuthenticationManagerRuntime {
        AuthenticationManagerRuntime(
            presentBasicAuthSheet: { [weak browserManager] session, tab in
                guard let browserManager else { return false }
                return browserManager.chromeBundle.nativeDialogPresentationOwner.presentBasicAuthSheet(
                    session,
                    in: browserManager.shellRuntime.windowTabs.windowState(containing: tab)
                )
            },
            presentCertificateTrustWarning: { [weak browserManager] session, tab, webView in
                if browserManager?.shellRuntime.windowTabs.windowState(
                    containing: tab
                ) != nil {
                    return tab.beginCertificateTrustWarningPresentation(session)
                }
                return webView?.sumiReaderPresentationHost?
                    .presentCertificateTrustWarning(session) ?? false
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
            },
            dismissCertificateTrustWarning: { session, tab, webView in
                tab?.endCertificateTrustWarningPresentation(session)
                webView?.sumiReaderPresentationHost?
                    .dismissCertificateTrustWarning()
            }
        )
    }
}
