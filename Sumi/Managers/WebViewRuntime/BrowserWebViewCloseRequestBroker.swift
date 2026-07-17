import Combine
import Foundation
import WebKit

struct BrowserWebViewCloseRequest {
    let id: UUID
    let webView: WKWebView
}

@MainActor
final class BrowserWebViewCloseRequestBroker {
    private let subject = PassthroughSubject<BrowserWebViewCloseRequest, Never>()
    private var pendingResults: [UUID: Bool] = [:]

    var publisher: AnyPublisher<BrowserWebViewCloseRequest, Never> {
        subject.eraseToAnyPublisher()
    }

    func requestClose(_ webView: WKWebView) -> Bool {
        let request = BrowserWebViewCloseRequest(id: UUID(), webView: webView)
        pendingResults[request.id] = false
        subject.send(request)
        return pendingResults.removeValue(forKey: request.id) == true
    }

    func resolve(_ request: BrowserWebViewCloseRequest, handled: Bool) {
        guard pendingResults[request.id] != nil else { return }
        pendingResults[request.id] = handled
    }
}
