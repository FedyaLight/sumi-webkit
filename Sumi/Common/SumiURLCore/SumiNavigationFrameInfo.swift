import Foundation

struct SumiFrameHandle: Hashable, Sendable {
    let frameID: UInt64

    init(frameID: UInt64) {
        self.frameID = frameID
    }
}

struct SumiNavigationFrameInfo: Equatable, Sendable {
    let securityOrigin: SumiSecurityOrigin
    let isMainFrame: Bool
    let url: URL?
    let handle: SumiFrameHandle?

    init(
        securityOrigin: SumiSecurityOrigin,
        isMainFrame: Bool,
        url: URL?,
        handle: SumiFrameHandle? = nil
    ) {
        self.securityOrigin = securityOrigin
        self.isMainFrame = isMainFrame
        self.url = url
        self.handle = handle
    }
}

extension SumiSecurityOrigin {
    init(navigationFrame frame: SumiNavigationFrameInfo) {
        self = frame.securityOrigin
    }
}
