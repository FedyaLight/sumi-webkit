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
            presentCertificateTrustWarning: { session, webView in
                webView?.sumiReaderPresentationHost?.presentCertificateTrustWarning(session) ?? false
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
            },
            dismissCertificateTrustWarning: { webView in
                webView?.sumiReaderPresentationHost?
                    .dismissCertificateTrustWarning()
            }
        )
    }
}
