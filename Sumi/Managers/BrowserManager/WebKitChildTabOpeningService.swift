import Foundation
import WebKit

/// Installs WebKit's exact child configuration into a new Tab in the physical
/// source window. Profile/data-store checks settle before structural mutation.
@MainActor
final class WebKitChildTabOpeningService: WebKitChildTabOpening {
    private let sources: PhysicalWebViewSourceResolver
    private let creation: WebKitChildTabCreationTransaction
    private let settlement: WebKitChildTabSettlementTransaction

    init(
        sources: PhysicalWebViewSourceResolver,
        creation: WebKitChildTabCreationTransaction,
        settlement: WebKitChildTabSettlementTransaction
    ) {
        self.sources = sources
        self.creation = creation
        self.settlement = settlement
    }

    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        from sourceWebView: FocusableWKWebView,
        selected: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard let source = sources.resolve(sourceWebView),
              configuration.websiteDataStore === source.dataStore,
              let admission = settlement.admit(
                  isExtensionOriginated: isExtensionOriginated
              ),
              let prepared = creation.prepare(
                  from: source,
                  requestURL: requestURL,
                  selected: selected
              )
        else {
            return nil
        }
        return settlement.commit(
            prepared,
            admission: admission,
            configuration: configuration,
            requestURL: requestURL,
            source: source,
            selected: selected,
            isExtensionOriginated: isExtensionOriginated
        )
    }
}
