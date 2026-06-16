import Foundation
import WebKit

@MainActor
protocol SumiUserScript: WKScriptMessageHandler {
    var source: String { get }
    var injectionTime: WKUserScriptInjectionTime { get }
    var forMainFrameOnly: Bool { get }
    var requiresRunInPageContentWorld: Bool { get }
    var messageNames: [String] { get }
}

extension SumiUserScript {
    var requiresRunInPageContentWorld: Bool {
        false
    }

    func getContentWorld() -> WKContentWorld {
        requiresRunInPageContentWorld ? .page : .defaultClient
    }
}

enum SumiUserScriptBuilder {
    @MainActor
    static func makeWKUserScript(from userScript: SumiUserScript) -> WKUserScript {
        WKUserScript(
            source: userScript.source,
            injectionTime: userScript.injectionTime,
            forMainFrameOnly: userScript.forMainFrameOnly,
            in: userScript.getContentWorld()
        )
    }
}
