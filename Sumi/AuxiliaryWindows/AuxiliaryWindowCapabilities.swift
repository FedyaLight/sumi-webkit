import AppKit
import Foundation
import WebKit

@MainActor
protocol AuxiliaryWindowContextResolving: AnyObject {
    var activeWindow: BrowserWindowState? { get }
    var currentProfileID: UUID? { get }
    var currentSpace: Space? { get }

    func currentTab(in windowState: BrowserWindowState) -> Tab?
    func parentWindow(for tab: Tab) -> NSWindow?
}

@MainActor
protocol AuxiliaryWindowTabLifecycle: AnyObject {
    var canInstallMiniWindowWebView: Bool { get }

    func createMiniWindowTab(
        openerTab: Tab?,
        profileID: UUID?,
        urlString: String?,
        extensionContext: WKWebExtensionContext?
    ) -> Tab?

    func install(_ webView: WKWebView, for tab: Tab)
    func registerExtensionCreatedTab(_ tab: Tab, reason: String)
    func notifyTabClosed(_ tab: Tab)
    func removeMiniWindowTab(_ tab: Tab)
}

@MainActor
protocol AuxiliaryWindowPermissionHandling: AnyObject {
    func evaluatePopupPermission(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult?

    func handleFilePickerOpenPanel(
        _ request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext,
        webView: WKWebView?,
        currentPageID: @escaping @MainActor () -> String?,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) -> Bool
}

@MainActor
protocol AuxiliaryWindowMutationAdmitting: AnyObject {
    func admissionIsBlocked(profileID: UUID) -> Bool
    func waitForAdmission(profileID: UUID) async -> Bool
}

@MainActor
protocol AuxiliaryWindowExtensionRuntimeResolving: AnyObject {
    func loadedEnabledAuxiliaryWindowIntegration()
        -> AuxiliaryWindowExtensionIntegration?
}

@MainActor
protocol AuxiliaryWindowExtensionEventHandling: AnyObject {
    func notifyAuxiliaryWindowOpened(_ session: AuxiliaryWindowSession)
    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession)
    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession)
}
