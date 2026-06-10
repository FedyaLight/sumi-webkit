//
//  BitwardenFakeDesktopProxyTransport.swift
//  SumiTests
//
//  Fake desktop_proxy transport for Bitwarden adapter unit tests.
//

import Foundation
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class BitwardenFakeDesktopProxyTransport: BitwardenDesktopProxyTransporting {
    enum Mode: Equatable {
        case handshakeConnected
        case handshakeDisconnected
        case handshakeAppNotRunning
        case handshakeTimeout
        case handshakeMalformed
        case disconnectAfterConnect
    }

    private(set) var isConnected = false
    var onDisconnect: (() -> Void)?
    var onReceive: (([String: Any]) -> Void)?

    var mode: Mode
    var startDelay: Duration
    private(set) var sentMessages: [[String: Any]] = []
    var statusReply: [String: Any] = [
        "message": [
            "command": "getBiometricsStatus",
            "response": 0,
            "messageId": 1,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ],
    ]

    init(mode: Mode = .handshakeConnected, startDelay: Duration = .zero) {
        self.mode = mode
        self.startDelay = startDelay
    }

    func start(
        proxyExecutableURL: URL,
        handshakeTimeout: Duration
    ) async throws {
        _ = proxyExecutableURL
        _ = handshakeTimeout
        if startDelay > .zero {
            try await Task.sleep(for: startDelay)
        }
        switch mode {
        case .handshakeConnected:
            isConnected = true
        case .handshakeDisconnected:
            throw BitwardenDesktopProxyTransportError.desktopIntegrationDisabled
        case .handshakeAppNotRunning:
            throw BitwardenDesktopProxyTransportError.desktopNotRunning
        case .handshakeTimeout:
            throw BitwardenDesktopProxyTransportError.timeout
        case .handshakeMalformed:
            throw BitwardenDesktopProxyTransportError.malformedReply
        case .disconnectAfterConnect:
            isConnected = true
            onDisconnect?()
            isConnected = false
        }
    }

    func send(_ object: [String: Any]) throws {
        guard isConnected else {
            throw BitwardenDesktopProxyTransportError.portDisconnected
        }
        sentMessages.append(object)
        guard let nested = object["message"] as? [String: Any],
              let command = nested["command"] as? String
        else {
            return
        }
        switch command {
        case "getBiometricsStatus":
            onReceive?(statusReply)
        default:
            break
        }
    }

    func shutdown() {
        isConnected = false
    }

    func simulateIncoming(_ message: [String: Any]) {
        onReceive?(message)
    }

    func simulateDisconnect() {
        isConnected = false
        onDisconnect?()
    }
}
