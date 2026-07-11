import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionWindowPresentationAdapter:
    ExtensionWindowPresentation
{
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let windowQuery: any ExtensionWindowQuery
    private let popups: AuxiliaryPopupOpeningService
    private let extensionWindows: ExtensionAuxiliaryWindowOpeningService
    private let urlHubAnchorView: @MainActor (UUID) -> NSView?
    private let settings: @MainActor () -> SumiSettingsService?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        windowQuery: any ExtensionWindowQuery,
        popups: AuxiliaryPopupOpeningService,
        extensionWindows: ExtensionAuxiliaryWindowOpeningService,
        urlHubAnchorView: @escaping @MainActor (UUID) -> NSView?,
        settings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.windowRegistry = windowRegistry
        self.windowQuery = windowQuery
        self.popups = popups
        self.extensionWindows = extensionWindows
        self.urlHubAnchorView = urlHubAnchorView
        self.settings = settings
    }

    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        openerWindow: NSWindow,
        openerProfileID: UUID,
        shouldActivateApp: Bool,
        extensionOwnedSourceURL: URL?,
        ownerExtensionID: String?
    ) -> WKWebView? {
        popups.presentExtensionExternalWebPopup(
            configuration: configuration,
            request: request,
            windowFeatures: windowFeatures,
            openerTab: openerTab,
            explicitOpenerWindow: openerWindow,
            explicitOpenerProfileID: openerProfileID,
            shouldActivateApp: shouldActivateApp,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            ownerExtensionID: ownerExtensionID
        )
    }

    func presentExtensionPopupWindow(
        configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        extensionManager: ExtensionManager,
        parentWindow: NSWindow?
    ) async -> ExtensionMiniWindowAdapter? {
        await extensionWindows.present(
            configuration: configuration,
            controller: controller,
            extensionContext: extensionContext,
            extensionManager: extensionManager,
            parentWindow: parentWindow
        )
    }

    func extensionURLHubFallbackAnchorView(for windowId: UUID) -> NSView? {
        urlHubAnchorView(windowId)
    }

    func extensionActionPopupAppearance(
        forAnchorWindow window: NSWindow,
        fallback: NSAppearance?
    ) -> NSAppearance? {
        guard let settings = settings(),
              let registry = windowRegistry(),
              let windowState = windowQuery.extensionWindowState(
                forAppKitWindow: window
              )
        else {
            return nil
        }
        return windowState.nativeSurfaceAppearance(
            settings: settings,
            fallback: fallback,
            in: registry
        )
    }
}
