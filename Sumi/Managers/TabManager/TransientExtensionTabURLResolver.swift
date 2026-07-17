import Foundation
import SumiDomain
import WebKit

@MainActor
final class TransientExtensionTabURLResolver {
    private let runtimeConnection: TabRuntimePortConnection

    init(runtimeConnection: TabRuntimePortConnection) {
        self.runtimeConnection = runtimeConnection
    }

    func resolve(_ input: String) -> URL {
        let queryTemplate = runtimeConnection.current?.settings?
            .resolvedSearchEngineTemplate
            ?? SearchProvider.google.queryTemplate
        let normalizedURL = normalizeURL(input, queryTemplate: queryTemplate)
        return URL(string: normalizedURL) ?? SumiSurface.emptyTabURL
    }
}
