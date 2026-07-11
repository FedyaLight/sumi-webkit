import Foundation
import WebKit

/// Presents an auxiliary Web popup only from a current physical source whose
/// execution partition matches WebKit's supplied child configuration.
@MainActor
final class PhysicalWebPopupOpeningService: PhysicalWebPopupOpening {
    private let sources: PhysicalWebViewSourceResolver
    private weak var popups: AuxiliaryPopupOpeningService?

    init(
        sources: PhysicalWebViewSourceResolver,
        popups: AuxiliaryPopupOpeningService
    ) {
        self.sources = sources
        self.popups = popups
    }

    func open(
        configuration: WKWebViewConfiguration,
        request: URLRequest,
        windowFeatures: WKWindowFeatures,
        from sourceWebView: FocusableWKWebView,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard let source = sources.resolve(sourceWebView),
              configuration.websiteDataStore === source.dataStore,
              let sourceWindow = source.appKitWindow,
              let popups
        else {
            return nil
        }
        return popups.presentWebPopup(
            configuration: configuration,
            request: request,
            windowFeatures: windowFeatures,
            openerTab: source.tab,
            explicitOpenerWindow: sourceWindow,
            explicitOpenerProfileID: source.executionProfile.id,
            isExtensionOriginated: isExtensionOriginated,
            shouldActivateApp: true
        )
    }
}
