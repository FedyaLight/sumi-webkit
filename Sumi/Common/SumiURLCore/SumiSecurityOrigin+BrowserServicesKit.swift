import Navigation
import WebKit

extension SumiFrameHandle {
    init(_ handle: FrameHandle) {
        self.init(frameID: handle.frameID)
    }

    var navigationFrameHandle: FrameHandle? {
        FrameHandle(rawValue: frameID)
    }
}

extension SumiNavigationFrameInfo {
    init(navigationFrame frame: FrameInfo) {
        let origin = frame.securityOrigin
        self.init(
            securityOrigin: SumiSecurityOrigin(
                protocol: origin.`protocol`,
                host: origin.host,
                port: origin.port
            ),
            isMainFrame: frame.isMainFrame,
            url: frame.url,
            handle: SumiFrameHandle(frame.handle)
        )
    }

    @MainActor
    init(webKitFrame frame: WKFrameInfo) {
        self.init(
            securityOrigin: SumiSecurityOrigin(webKitSecurityOrigin: frame.securityOrigin),
            isMainFrame: frame.isMainFrame,
            url: frame.sumiWebKitRequestURL,
            handle: nil
        )
    }
}

extension SumiSecurityOrigin {
    init(navigationFrame frame: FrameInfo) {
        self = SumiNavigationFrameInfo(navigationFrame: frame).securityOrigin
    }

    @MainActor
    init(webKitSecurityOrigin origin: WKSecurityOrigin) {
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
