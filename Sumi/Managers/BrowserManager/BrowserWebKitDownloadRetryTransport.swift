import Foundation
import WebKit

@MainActor
final class BrowserWebKitDownloadRetryTransport:
    DownloadRetryTransportStarting
{
    private weak var shellRuntime: BrowserShellRuntime?
    private weak var webViewRouting: BrowserWebViewRoutingService?
    private let transportFactory: any DownloadWebKitTransportAdapting

    init(
        shellRuntime: BrowserShellRuntime,
        webViewRouting: BrowserWebViewRoutingService,
        transportFactory: any DownloadWebKitTransportAdapting
    ) {
        self.shellRuntime = shellRuntime
        self.webViewRouting = webViewRouting
        self.transportFactory = transportFactory
    }

    @discardableResult
    func startRetry(
        _ request: DownloadRetryRequest,
        completion: @escaping @MainActor (any DownloadTransport) -> Void
    ) -> Bool {
        guard let shellRuntime,
              let webViewRouting,
              let activeWindow = shellRuntime.windowRegistry?.activeWindow,
              let currentTab = shellRuntime.windowTabs.currentTab(
                for: activeWindow
              ),
              let webView = webViewRouting.windowOwnedWebView(
                for: currentTab,
                in: activeWindow.id
              )
        else {
            return false
        }

        let callback: @MainActor @Sendable (WKDownload) -> Void = {
            [transportFactory] download in
            completion(transportFactory.makeTransport(for: download))
        }
        if let resumeData = request.resumeData {
            webView.resumeDownload(
                fromResumeData: resumeData,
                completionHandler: callback
            )
        } else {
            webView.startDownload(
                using: URLRequest(url: request.sourceURL),
                completionHandler: callback
            )
        }
        return true
    }
}
