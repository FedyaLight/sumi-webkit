import Navigation
import WebKit

extension SumiSecurityOrigin {
    init(navigationFrame frame: FrameInfo) {
        let origin = frame.securityOrigin
        self.init(protocol: origin.`protocol`, host: origin.host, port: origin.port)
    }

    func navigationFrameInfo(
        webView: WKWebView,
        handle: FrameHandle,
        isMainFrame: Bool,
        url: URL
    ) -> FrameInfo {
        let seedOrigin = FrameInfo.mainFrame(for: webView).securityOrigin
        let securityOrigin = type(of: seedOrigin).init(
            protocol: self.`protocol`,
            host: host,
            port: port
        )
        return FrameInfo(
            webView: webView,
            handle: handle,
            isMainFrame: isMainFrame,
            url: url,
            securityOrigin: securityOrigin
        )
    }
}
