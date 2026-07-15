import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionWindowPresentationAdapter:
    ExtensionWindowPresentation {
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let windowQuery: any ExtensionWindowQuery
    private let extensionWindows: ExtensionAuxiliaryWindowOpeningService
    private let urlHubAnchorView: @MainActor (UUID) -> NSView?
    private let settings: @MainActor () -> SumiSettingsService?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        windowQuery: any ExtensionWindowQuery,
        extensionWindows: ExtensionAuxiliaryWindowOpeningService,
        urlHubAnchorView: @escaping @MainActor (UUID) -> NSView?,
        settings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.windowRegistry = windowRegistry
        self.windowQuery = windowQuery
        self.extensionWindows = extensionWindows
        self.urlHubAnchorView = urlHubAnchorView
        self.settings = settings
    }

    func presentExtensionPopupWindow(
        request: ExtensionWindowOpeningRequest,
        evidence: ExtensionControllerCallbackEvidence,
        admission: ExtensionControllerCallbackAdmission,
        runtime: ExtensionAuxiliaryWindowCallbackRuntime,
        parentWindow: NSWindow?
    ) async -> ExtensionPopupWindowPresentationReceipt? {
        await extensionWindows.present(
            request: request,
            evidence: evidence,
            callbackAdmission: admission,
            runtime: runtime,
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
