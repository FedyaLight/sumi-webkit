import Foundation
import WebKit

/// A browser-managed page script installed through Sumi's shared WebKit pipeline.
/// This is infrastructure for built-in browser behavior and extension diagnostics,
/// not a user-installable scripting API.
@MainActor
protocol SumiPageScript: WKScriptMessageHandler {
    var source: String { get }
    var injectionTime: WKUserScriptInjectionTime { get }
    var forMainFrameOnly: Bool { get }
    var requiresRunInPageContentWorld: Bool { get }
    var messageNames: [String] { get }
}

extension SumiPageScript {
    var requiresRunInPageContentWorld: Bool {
        false
    }

    func getContentWorld() -> WKContentWorld {
        requiresRunInPageContentWorld ? .page : .defaultClient
    }
}

enum SumiPageScriptBuilder {
    @MainActor
    static func makeWKUserScript(from pageScript: SumiPageScript) -> WKUserScript {
        WKUserScript(
            source: pageScript.source,
            injectionTime: pageScript.injectionTime,
            forMainFrameOnly: pageScript.forMainFrameOnly,
            in: pageScript.getContentWorld()
        )
    }
}
