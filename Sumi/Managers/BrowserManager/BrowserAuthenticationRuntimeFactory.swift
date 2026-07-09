import Foundation

@MainActor
enum BrowserAuthenticationRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> AuthenticationManagerRuntime {
        AuthenticationManagerRuntime(
            presentBasicAuthSheet: { [weak browserManager] session, tab in
                guard let browserManager else { return false }
                return browserManager.chromeBundle.nativeDialogPresentationOwner.presentBasicAuthSheet(
                    session,
                    in: browserManager.windowSessionBundle.tabContextOwner.windowState(containing: tab)
                )
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
            }
        )
    }
}
