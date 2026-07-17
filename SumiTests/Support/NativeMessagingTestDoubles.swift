import Foundation
@testable import Sumi

@MainActor
final class NativeMessagingTestHostLauncher: SumiHostApplicationLaunching {
    var bundleURLs: [String: URL] = [:]
    private(set) var openedBundleIdentifiers: [String] = []
    var openError: (any Error)?

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        bundleURLs[bundleIdentifier]
    }

    func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
        if let openError {
            throw openError
        }
        openedBundleIdentifiers.append(bundleIdentifier)
    }
}

@MainActor
final class NativeMessagingTestPort: SumiNativeMessagingPortReplyRecording {
    var applicationIdentifier: String?
    private(set) var isDisconnected = false
    var messageHandler: ((Any?, (any Error)?) -> Void)?
    var disconnectHandler: (((any Error)?) -> Void)?
    private(set) var disconnectError: (any Error)?
    private(set) var repliesSent: [Any] = []
    var didDisconnect: (() -> Void)?

    func recordReplyToExtension(_ message: Any) {
        repliesSent.append(message)
    }

    func disconnect() {
        isDisconnected = true
        didDisconnect?()
        disconnectHandler?(disconnectError)
    }

    func disconnect(throwing error: (any Error)?) {
        disconnectError = error
        disconnect()
    }

    func simulateIncomingMessage(_ message: Any?, error: (any Error)? = nil) {
        messageHandler?(message, error)
    }

    func simulateDisconnect(error: (any Error)? = nil) {
        isDisconnected = true
        disconnectHandler?(error)
    }
}
