import Foundation
import WebKit

@MainActor
final class SumiBoostUserScript: NSObject, SumiUserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String] = []

    init(boost: SumiBoost) {
        self.source = SumiBoostCSSBuilder.installJavaScript(for: boost)
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        _ = message
    }
}
