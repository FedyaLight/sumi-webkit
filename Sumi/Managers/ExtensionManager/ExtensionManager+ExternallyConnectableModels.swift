//
//  ExtensionManager+ExternallyConnectableModels.swift
//  Sumi
//
//  Shared models for externally_connectable runtime state.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
struct ExternallyConnectablePolicy {
    let extensionId: String
    let matchPatternStrings: [String]
    let matchPatterns: [WKWebExtension.MatchPattern]

    @MainActor
    var normalizedHostnames: [String] {
        Array(
            Set(
                matchPatterns.compactMap { pattern in
                    guard let host = pattern.host, host != "*" else { return nil }
                    return host.replacingOccurrences(of: "*.", with: "")
                }
            )
        ).sorted()
    }

    @MainActor
    func matches(url: URL?) -> Bool {
        guard let url else { return false }
        return matchPatterns.contains { $0.matches(url) }
    }
}

@available(macOS 15.5, *)
@MainActor
final class PendingExternallyConnectableNativeRequest {
    let id: UUID
    let extensionId: String
    let webViewIdentifier: ObjectIdentifier

    private var replyHandler: ((Any?, String?) -> Void)?

    init(
        id: UUID,
        extensionId: String,
        webViewIdentifier: ObjectIdentifier,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        self.id = id
        self.extensionId = extensionId
        self.webViewIdentifier = webViewIdentifier
        self.replyHandler = replyHandler
    }

    func resolve(reply: Any?, errorMessage: String?) {
        guard let replyHandler else { return }
        self.replyHandler = nil
        replyHandler(reply, errorMessage)
    }
}

@available(macOS 15.5, *)
enum ExternallyConnectableNativePortState {
    case opening
    case open
    case disconnecting
    case closed
}

@available(macOS 15.5, *)
@MainActor
final class ExternallyConnectableNativePortSession {
    let portId: String
    let extensionId: String
    let webViewIdentifier: ObjectIdentifier
    weak var webView: WKWebView?
    let frameInfo: WKFrameInfo
    let sourceOrigin: String?
    let isMainFrame: Bool
    let frameURLString: String?
    let connectName: String
    var state: ExternallyConnectableNativePortState

    init(
        portId: String,
        extensionId: String,
        webView: WKWebView,
        frameInfo: WKFrameInfo,
        sourceOrigin: String?,
        isMainFrame: Bool,
        frameURLString: String?,
        connectName: String,
        state: ExternallyConnectableNativePortState
    ) {
        self.portId = portId
        self.extensionId = extensionId
        self.webViewIdentifier = ObjectIdentifier(webView)
        self.webView = webView
        self.frameInfo = frameInfo
        self.sourceOrigin = sourceOrigin
        self.isMainFrame = isMainFrame
        self.frameURLString = frameURLString
        self.connectName = connectName
        self.state = state
    }
}
