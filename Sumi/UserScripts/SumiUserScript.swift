import CryptoKit
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

@MainActor
protocol SumiUserScriptsProvider: AnyObject {
    var userScripts: [SumiUserScript] { get }
    func loadWKUserScripts() async -> [WKUserScript]
}

enum SumiUserScriptBuilder {
    @MainActor
    static func makeWKUserScript(from userScript: SumiUserScript) -> WKUserScript {
        WKUserScript(
            source: preparedSource(from: userScript.source),
            injectionTime: userScript.injectionTime,
            forMainFrameOnly: userScript.forMainFrameOnly,
            in: userScript.getContentWorld()
        )
    }

    private static func preparedSource(from source: String) -> String {
        let hash = SHA256.hash(data: Data(source.utf8)).hashValue

        return """
        (() => {
            if (window.navigator._duckduckgoloader_ && window.navigator._duckduckgoloader_.includes('\(hash)')) {return}
            \(source)
            window.navigator._duckduckgoloader_ = window.navigator._duckduckgoloader_ || [];
            window.navigator._duckduckgoloader_.push('\(hash)')
        })()
        """
    }
}
