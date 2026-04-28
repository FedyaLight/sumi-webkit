//
//  ExtensionManager+ExternallyConnectableNativeMessaging.swift
//  Sumi
//
//  Native messaging and port lifecycle for externally_connectable.
//

import Foundation
import Navigation
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
    func handleExternallyConnectableNativeMessage(
        _ message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.name == Self.externallyConnectableNativeBridgeHandlerName else {
            replyHandler(nil, "Unknown externally_connectable bridge handler")
            return
        }

        guard let body = message.body as? [String: Any],
              let envelope = ExternallyConnectableBridgeCodec.decode(
                  ExternallyConnectableBridgeEnvelope.self,
                  from: body
              )
        else {
            replyHandler(nil, "Invalid externally_connectable request payload")
            return
        }

        switch message.world {
        case .page:
            guard envelope.featureName == "runtime" else {
                replyHandler(nil, "Unsupported externally_connectable page request")
                return
            }
            switch envelope.method {
            case "sendMessage":
                guard let request = envelope.decodeParams(
                    ExternallyConnectableNativeSendMessageRequest.self
                ) else {
                    replyHandler(nil, "Invalid externally_connectable request payload")
                    return
                }
                handleExternallyConnectableNativeSendMessageRequest(
                    request,
                    message: message,
                    replyHandler: replyHandler
                )
            case "runtime.connect.open",
                 "runtime.connect.postMessage",
                 "runtime.connect.disconnect":
                guard let request = Self.decodeExternallyConnectableNativeConnectRequest(
                    operation: envelope.method,
                    envelope: envelope
                ) else {
                    replyHandler(nil, "Invalid externally_connectable request payload")
                    return
                }
                handleExternallyConnectableNativeConnectRequest(
                    request: request,
                    message: message,
                    replyHandler: replyHandler
                )
            default:
                replyHandler(nil, "Unsupported externally_connectable page request")
            }
        case .defaultClient:
            guard envelope.featureName == "runtime.connect.event" else {
                replyHandler(nil, "Unsupported externally_connectable adapter request")
                return
            }
            switch envelope.method {
            case "runtime.connect.event.message":
                guard let event = envelope.decodeParams(
                    ExternallyConnectableNativeConnectMessageEvent.self
                ) else {
                    replyHandler(nil, "Invalid externally_connectable request payload")
                    return
                }
                handleExternallyConnectableNativeConnectAdapterEvent(
                    event: .message(event),
                    message: message,
                    replyHandler: replyHandler
                )
            case "runtime.connect.event.disconnect":
                guard let event = envelope.decodeParams(
                    ExternallyConnectableNativeConnectDisconnectEvent.self
                ) else {
                    replyHandler(nil, "Invalid externally_connectable request payload")
                    return
                }
                handleExternallyConnectableNativeConnectAdapterEvent(
                    event: .disconnect(event),
                    message: message,
                    replyHandler: replyHandler
                )
            default:
                replyHandler(nil, "Unsupported externally_connectable adapter request")
            }
        default:
            replyHandler(nil, "Unsupported externally_connectable content world")
        }
    }

    private enum ExternallyConnectableNativeConnectRequest {
        case open(ExternallyConnectableNativeConnectOpenRequest)
        case postMessage(ExternallyConnectableNativeConnectPostMessageRequest)
        case disconnect(ExternallyConnectableNativeConnectDisconnectRequest)
    }

    private enum ExternallyConnectableNativeConnectAdapterEvent {
        case message(ExternallyConnectableNativeConnectMessageEvent)
        case disconnect(ExternallyConnectableNativeConnectDisconnectEvent)
    }

    private static func decodeExternallyConnectableNativeConnectRequest(
        operation: String,
        envelope: ExternallyConnectableBridgeEnvelope
    ) -> ExternallyConnectableNativeConnectRequest? {
        switch operation {
        case "runtime.connect.open":
            return envelope.decodeParams(ExternallyConnectableNativeConnectOpenRequest.self)
                .map(ExternallyConnectableNativeConnectRequest.open)
        case "runtime.connect.postMessage":
            return envelope.decodeParams(ExternallyConnectableNativeConnectPostMessageRequest.self)
                .map(ExternallyConnectableNativeConnectRequest.postMessage)
        case "runtime.connect.disconnect":
            return envelope.decodeParams(ExternallyConnectableNativeConnectDisconnectRequest.self)
                .map(ExternallyConnectableNativeConnectRequest.disconnect)
        default:
            return nil
        }
    }

    private static func acceptedBridgeResponse(
        portId: String? = nil
    ) -> Any? {
        ExternallyConnectableBridgeCodec.foundationObject(
            from: ExternallyConnectableNativeAcceptedResponse(
                accepted: true,
                portId: portId
            )
        )
    }

    private func handleExternallyConnectableNativeSendMessageRequest(
        _ request: ExternallyConnectableNativeSendMessageRequest,
        message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let webView = message.webView else {
            replyHandler(nil, "Externally connectable request is missing a source webView")
            return
        }

        guard let extensionId = normalizeExternallyConnectableExtensionID(
            request.extensionId
        ) else {
            replyHandler(nil, "Externally connectable request is missing an extension identifier")
            return
        }

        let sourceURL = message.frameInfo.safeRequest?.url
        let sourceOrigin = Self.originString(for: sourceURL)
        let webViewID = ObjectIdentifier(webView)
        let requestID = UUID()

        guard let validation = validateExternallyConnectableNativeSendMessageTarget(
            extensionId: extensionId,
            webView: webView,
            isMainFrame: message.frameInfo.isMainFrame,
            sourceURL: sourceURL,
            sourceOrigin: sourceOrigin
        ) else {
            replyHandler(nil, "Externally connectable request was rejected by policy")
            return
        }

        let pendingRequest = PendingExternallyConnectableNativeRequest(
            id: requestID,
            extensionId: extensionId,
            webViewIdentifier: webViewID,
            replyHandler: replyHandler
        )
        if let rejection = ecRegistry.addRequest(pendingRequest) {
            replyHandler(nil, rejection)
            return
        }

        logExternallyConnectableBridgeEvent(
            "Accepted native sendMessage request id=\(requestID.uuidString) ext=\(extensionId) origin=\(sourceOrigin ?? "(unknown)")"
        )

        Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            guard let webView else {
                self.resolveExternallyConnectablePendingRequest(
                    id: requestID,
                    reply: nil,
                    errorMessage: "Source webView is no longer available"
                )
                return
            }

            do {
                let response = try await self.relayExternallyConnectableNativeSendMessage(
                    via: webView,
                    frameInfo: message.frameInfo,
                    extensionId: validation.extensionId,
                    message: request.message?.foundationObject
                )
                self.resolveExternallyConnectablePendingRequest(
                    id: requestID,
                    reply: response,
                    errorMessage: nil
                )
            } catch {
                self.resolveExternallyConnectablePendingRequest(
                    id: requestID,
                    reply: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    private func handleExternallyConnectableNativeConnectRequest(
        request: ExternallyConnectableNativeConnectRequest,
        message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let webView = message.webView else {
            replyHandler(nil, "Externally connectable request is missing a source webView")
            return
        }

        switch request {
        case .open(let openRequest):
            guard let extensionId = normalizeExternallyConnectableExtensionID(
                openRequest.extensionId
            ) else {
                replyHandler(nil, "Externally connectable connect is missing an extension identifier")
                return
            }

            let sourceURL = message.frameInfo.safeRequest?.url
            let sourceOrigin = Self.originString(for: sourceURL)
            guard let validation = validateExternallyConnectableNativeConnectOpenTarget(
                extensionId: extensionId,
                webView: webView,
                isMainFrame: message.frameInfo.isMainFrame,
                sourceURL: sourceURL,
                sourceOrigin: sourceOrigin
            ) else {
                replyHandler(nil, "Externally connectable request was rejected by policy")
                return
            }

            let portId = (
                normalizeExternallyConnectableExtensionID(openRequest.portId)
                ?? "sumi_ec_native_port_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            )
            guard !ecRegistry.portExists(portId) else {
                replyHandler(nil, "Externally connectable port already exists")
                return
            }

            let connectInfo = (openRequest.connectInfo ?? [:]).mapValues(\.foundationObject)
            let session = ExternallyConnectableNativePortSession(
                portId: portId,
                extensionId: validation.extensionId,
                webView: webView,
                frameInfo: message.frameInfo,
                sourceOrigin: sourceOrigin,
                isMainFrame: message.frameInfo.isMainFrame,
                frameURLString: sourceURL?.absoluteString,
                connectName: (connectInfo["name"] as? String) ?? "",
                state: .opening
            )
            if let rejection = registerExternallyConnectableNativePortSession(session) {
                replyHandler(nil, rejection)
                return
            }
            logExternallyConnectableBridgeEvent(
                "Accepted native connect open portId=\(portId) ext=\(validation.extensionId) origin=\(sourceOrigin ?? "(unknown)")"
            )

            let timeoutMilliseconds = timeoutMilliseconds(from: openRequest.timeoutMs)
            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                guard let webView else {
                    self.finishExternallyConnectableNativePort(
                        portId: portId,
                        errorMessage: "Source webView is no longer available",
                        notifyPage: true
                    )
                    return
                }

                do {
                    try await self.relayExternallyConnectableNativeConnectOpen(
                        via: webView,
                        frameInfo: message.frameInfo,
                        session: session,
                        connectInfo: connectInfo,
                        timeoutMilliseconds: timeoutMilliseconds
                    )

                    guard let currentSession = self.ecRegistry.port(for: portId) else {
                        return
                    }

                    if currentSession.state == .disconnecting {
                        try? await self.relayExternallyConnectableNativeConnectDisconnect(
                            via: webView,
                            frameInfo: currentSession.frameInfo,
                            portId: portId
                        )
                        self.finishExternallyConnectableNativePort(
                            portId: portId,
                            errorMessage: nil,
                            notifyPage: false
                        )
                        return
                    }

                    currentSession.state = .open
                    do {
                        try await self.dispatchExternallyConnectableNativePortOpened(
                            for: currentSession
                        )
                    } catch {
                        self.finishExternallyConnectableNativePort(
                            portId: portId,
                            errorMessage: "Extension port disconnected because the page is no longer available",
                            notifyPage: false
                        )
                    }
                } catch {
                    self.finishExternallyConnectableNativePort(
                        portId: portId,
                        errorMessage: error.localizedDescription,
                        notifyPage: session.state != .disconnecting
                    )
                }
            }

            replyHandler(Self.acceptedBridgeResponse(portId: portId), nil)

        case .postMessage(let postMessageRequest):
            guard let portId = normalizeExternallyConnectableExtensionID(postMessageRequest.portId),
                  let session = validateExternallyConnectableNativePortSession(
                      portId: portId,
                      webView: webView
                  )
            else {
                replyHandler(nil, "Externally connectable port is unavailable")
                return
            }

            if session.state == .opening {
                replyHandler(nil, "Externally connectable port is not ready")
                return
            }

            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    try await self.relayExternallyConnectableNativeConnectPostMessage(
                        via: webView,
                        frameInfo: session.frameInfo,
                        portId: portId,
                        message: postMessageRequest.message?.foundationObject
                    )
                } catch {
                    self.finishExternallyConnectableNativePort(
                        portId: portId,
                        errorMessage: error.localizedDescription,
                        notifyPage: true
                    )
                }
            }
            replyHandler(Self.acceptedBridgeResponse(), nil)

        case .disconnect(let disconnectRequest):
            guard let portId = normalizeExternallyConnectableExtensionID(disconnectRequest.portId),
                  let session = validateExternallyConnectableNativePortSession(
                      portId: portId,
                      webView: webView,
                      allowDisconnecting: true
                  )
            else {
                replyHandler(Self.acceptedBridgeResponse(), nil)
                return
            }

            if session.state == .disconnecting || session.state == .closed {
                replyHandler(Self.acceptedBridgeResponse(), nil)
                return
            }

            let wasOpening = session.state == .opening
            session.state = .disconnecting
            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                guard let webView else {
                    self.finishExternallyConnectableNativePort(
                        portId: portId,
                        errorMessage: nil,
                        notifyPage: false
                    )
                    return
                }

                if wasOpening {
                    return
                }

                if session.state == .open || session.state == .disconnecting {
                    try? await self.relayExternallyConnectableNativeConnectDisconnect(
                        via: webView,
                        frameInfo: session.frameInfo,
                        portId: portId
                    )
                }
                self.finishExternallyConnectableNativePort(
                    portId: portId,
                    errorMessage: nil,
                    notifyPage: false
                )
            }
            replyHandler(Self.acceptedBridgeResponse(), nil)
        }
    }

    private func handleExternallyConnectableNativeConnectAdapterEvent(
        event: ExternallyConnectableNativeConnectAdapterEvent,
        message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.world == .defaultClient else {
            replyHandler(nil, "Externally connectable adapter events must originate from the isolated world")
            return
        }

        let portId: String?
        switch event {
        case .message(let messageEvent):
            portId = normalizeExternallyConnectableExtensionID(messageEvent.portId)
        case .disconnect(let disconnectEvent):
            portId = normalizeExternallyConnectableExtensionID(disconnectEvent.portId)
        }

        guard let portId,
              let session = ecRegistry.port(for: portId)
        else {
            replyHandler(["accepted": false], nil)
            return
        }

        switch event {
        case .message(let messageEvent):
            if session.state == .disconnecting || session.state == .closed {
                replyHandler(["accepted": false], nil)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.dispatchExternallyConnectableNativePortMessage(
                        for: session,
                        message: messageEvent.message?.foundationObject
                    )
                } catch {
                    self.finishExternallyConnectableNativePort(
                        portId: portId,
                        errorMessage: "Extension port disconnected because the page is no longer available",
                        notifyPage: false
                    )
                }
            }
            replyHandler(Self.acceptedBridgeResponse(), nil)

        case .disconnect(let disconnectEvent):
            finishExternallyConnectableNativePort(
                portId: portId,
                errorMessage: disconnectEvent.error,
                notifyPage: session.state != .disconnecting
            )
            replyHandler(Self.acceptedBridgeResponse(), nil)
        }
    }

    func cancelExternallyConnectablePendingRequests(
        for webView: WKWebView,
        reason: String
    ) {
        let requestIDs = ecRegistry.removeRequestIDs(for: webView)
        guard !requestIDs.isEmpty else { return }
        for requestID in requestIDs {
            resolveExternallyConnectablePendingRequest(
                id: requestID,
                reply: nil,
                errorMessage: reason
            )
        }
    }

    func cancelExternallyConnectablePendingRequests(
        for extensionId: String,
        reason: String
    ) {
        for requestID in ecRegistry.requestIDs(forExtension: extensionId) {
            resolveExternallyConnectablePendingRequest(
                id: requestID,
                reply: nil,
                errorMessage: reason
            )
        }
    }

    func clearExternallyConnectablePendingRequests() {
        for requestID in ecRegistry.allRequestIDs {
            resolveExternallyConnectablePendingRequest(
                id: requestID,
                reply: nil,
                errorMessage: "Extension request canceled during runtime reset"
            )
        }
        ecRegistry.clearAllRequests()
        ecRegistry.clearAllTrackedPageURLs()
    }

    func clearExternallyConnectableNativePorts() {
        for portId in ecRegistry.allPortIDs {
            finishExternallyConnectableNativePort(
                portId: portId,
                errorMessage: "Extension port disconnected during runtime reset",
                notifyPage: true
            )
        }
        ecRegistry.clearAllPorts()
    }

    func closeExternallyConnectableNativePorts(
        for webView: WKWebView,
        reason: String,
        notifyPage: Bool
    ) {
        for portId in ecRegistry.removePortIDs(for: webView) {
            finishExternallyConnectableNativePort(
                portId: portId,
                errorMessage: reason,
                notifyPage: notifyPage
            )
        }
    }

    func closeExternallyConnectableNativePorts(
        for extensionId: String,
        reason: String,
        notifyPage: Bool
    ) {
        for portId in ecRegistry.removePortIDs(forExtension: extensionId) {
            finishExternallyConnectableNativePort(
                portId: portId,
                errorMessage: reason,
                notifyPage: notifyPage
            )
        }
    }

    private func resolveExternallyConnectablePendingRequest(
        id: UUID,
        reply: Any?,
        errorMessage: String?
    ) {
        guard let pendingRequest = ecRegistry.removeRequest(id: id) else {
            return
        }

        if let errorMessage {
            logExternallyConnectableBridgeEvent(
                "Rejected native sendMessage request id=\(id.uuidString): \(errorMessage)"
            )
        } else {
            logExternallyConnectableBridgeEvent(
                "Resolved native sendMessage request id=\(id.uuidString)"
            )
        }

        pendingRequest.resolve(reply: reply, errorMessage: errorMessage)
    }

    struct ExternallyConnectableValidationResult {
        let extensionId: String
    }

    func validateExternallyConnectableNativeSendMessageTarget(
        extensionId: String,
        webView: WKWebView,
        isMainFrame: Bool,
        sourceURL: URL?,
        sourceOrigin: String?
    ) -> ExternallyConnectableValidationResult? {
        validateExternallyConnectableNativeOperationTarget(
            operation: "sendMessage",
            extensionId: extensionId,
            webView: webView,
            isMainFrame: isMainFrame,
            sourceURL: sourceURL,
            sourceOrigin: sourceOrigin
        )
    }

    func validateExternallyConnectableNativeConnectOpenTarget(
        extensionId: String,
        webView: WKWebView,
        isMainFrame: Bool,
        sourceURL: URL?,
        sourceOrigin: String?
    ) -> ExternallyConnectableValidationResult? {
        validateExternallyConnectableNativeOperationTarget(
            operation: "connect.open",
            extensionId: extensionId,
            webView: webView,
            isMainFrame: isMainFrame,
            sourceURL: sourceURL,
            sourceOrigin: sourceOrigin
        )
    }

    private func validateExternallyConnectableNativeOperationTarget(
        operation: String,
        extensionId: String,
        webView: WKWebView,
        isMainFrame: Bool,
        sourceURL: URL?,
        sourceOrigin: String?
    ) -> ExternallyConnectableValidationResult? {
        guard let policy = externallyConnectablePolicies[extensionId] else {
            logExternallyConnectableBridgeEvent(
                "Native \(operation) validation failed for \(extensionId): policy missing"
            )
            return nil
        }

        guard installedExtensions.contains(where: {
            $0.id == extensionId && $0.isEnabled
        }) else {
            logExternallyConnectableBridgeEvent(
                "Native \(operation) validation failed for \(extensionId): extension disabled"
            )
            return nil
        }

        guard extensionContexts[extensionId] != nil else {
            logExternallyConnectableBridgeEvent(
                "Native \(operation) validation failed for \(extensionId): context unavailable"
            )
            return nil
        }

        guard policy.matches(url: sourceURL) else {
            logExternallyConnectableBridgeEvent(
                "Native \(operation) validation failed for \(extensionId): origin=\(sourceOrigin ?? "(unknown)") policy mismatch"
            )
            return nil
        }

        if isMainFrame,
           let trackedURLString = ecRegistry.trackedPageURL(for: webView),
           let sourceURL,
           trackedURLString != sourceURL.absoluteString
        {
            logExternallyConnectableBridgeEvent(
                "Native \(operation) validation failed for \(extensionId): source URL no longer matches active navigation"
            )
            return nil
        }

        return ExternallyConnectableValidationResult(
            extensionId: extensionId
        )
    }

    private func validateExternallyConnectableNativePortSession(
        portId: String,
        webView: WKWebView,
        allowDisconnecting: Bool = false
    ) -> ExternallyConnectableNativePortSession? {
        guard let session = ecRegistry.port(for: portId) else {
            return nil
        }

        guard session.webViewIdentifier == ObjectIdentifier(webView) else {
            logExternallyConnectableBridgeEvent(
                "Native connect validation failed for \(portId): webView mismatch"
            )
            return nil
        }

        guard session.state == .open || session.state == .opening
            || (allowDisconnecting && session.state == .disconnecting)
        else {
            logExternallyConnectableBridgeEvent(
                "Native connect validation failed for \(portId): invalid state"
            )
            return nil
        }

        guard installedExtensions.contains(where: {
            $0.id == session.extensionId && $0.isEnabled
        }) else {
            logExternallyConnectableBridgeEvent(
                "Native connect validation failed for \(portId): extension disabled"
            )
            return nil
        }

        guard extensionContexts[session.extensionId] != nil else {
            logExternallyConnectableBridgeEvent(
                "Native connect validation failed for \(portId): context unavailable"
            )
            return nil
        }

        if session.isMainFrame,
           let trackedURLString = ecRegistry.trackedPageURL(forWebViewIdentifier: session.webViewIdentifier),
           let frameURLString = session.frameURLString,
           trackedURLString != frameURLString
        {
            logExternallyConnectableBridgeEvent(
                "Native connect validation failed for \(portId): source URL no longer matches active navigation"
            )
            return nil
        }

        return session
    }

    private func registerExternallyConnectableNativePortSession(
        _ session: ExternallyConnectableNativePortSession
    ) -> String? {
        ecRegistry.addPort(session)
    }

    private func finishExternallyConnectableNativePort(
        portId: String,
        errorMessage: String?,
        notifyPage: Bool
    ) {
        guard let session = ecRegistry.removePort(portId: portId) else {
            return
        }

        session.state = .closed

        if notifyPage {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.dispatchExternallyConnectableNativePortDisconnected(
                    for: session,
                    errorMessage: errorMessage
                )
            }
        }
    }

    private func timeoutMilliseconds(from timeoutValue: Double?) -> Double {
        guard let timeoutValue, timeoutValue > 0 else {
            return 30_000
        }
        return timeoutValue
    }

    private func relayExternallyConnectableNativeSendMessage(
        via webView: WKWebView,
        frameInfo: WKFrameInfo,
        extensionId: String,
        message: Any?
    ) async throws -> Any? {
        logExternallyConnectableBridgeEvent(
            "Starting isolated-world delivery for native sendMessage ext=\(extensionId)"
        )

        guard let extensionContext = extensionContexts[extensionId] else {
            throw NSError(
                domain: "ExternallyConnectable",
                code: 1004,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Extension context is unavailable for externally connectable messaging",
                ]
            )
        }

        // Public WebKit API has delegate callbacks for extension→app native messaging, but no
        // supported host→background `runtime.sendMessage` equivalent; ensure background
        // availability once, then deliver via the extension's isolated `runtime` in this tab.
        try await ensureBackgroundAvailableIfRequired(
            for: extensionContext.webExtension,
            context: extensionContext,
            reason: .externallyConnectable
        )

        let sourceOrigin: String
        if let url = frameInfo.safeRequest?.url {
            sourceOrigin = Self.originString(for: url) ?? url.absoluteString
        } else {
            sourceOrigin = ""
        }

        do {
            let result = try await webView.callAsyncJavaScript(
                """
                var runtimeAPI = null;
                try {
                    if (typeof browser !== 'undefined' && browser.runtime && typeof browser.runtime.sendMessage === 'function') {
                        runtimeAPI = browser.runtime;
                    } else if (typeof chrome !== 'undefined' && chrome.runtime && typeof chrome.runtime.sendMessage === 'function') {
                        runtimeAPI = chrome.runtime;
                    }
                } catch (_) {}

                if (!runtimeAPI) {
                    throw new Error('Extension runtime unavailable in isolated world');
                }

                var envelope = {
                    __sumi_ec_external_message: true,
                    payload: bridgeMessage,
                    sender: {
                        origin: senderOrigin || null,
                        url: senderURL || null,
                        frameId: isMainFrame ? 0 : null
                    },
                    targetRuntimeId: extensionId
                };

                return await runtimeAPI.sendMessage(envelope);
                """,
                arguments: [
                    "bridgeMessage": message ?? NSNull(),
                    "extensionId": extensionId,
                    "senderOrigin": sourceOrigin,
                    "senderURL": frameInfo.safeRequest?.url?.absoluteString ?? NSNull(),
                    "isMainFrame": frameInfo.isMainFrame,
                ],
                in: frameInfo,
                contentWorld: .defaultClient
            )

            logExternallyConnectableBridgeEvent(
                "Completed isolated-world delivery for native sendMessage ext=\(extensionId)"
            )
            return result
        } catch {
            logExternallyConnectableBridgeEvent(
                "Isolated-world delivery failed for native sendMessage ext=\(extensionId): \(error.localizedDescription)"
            )
            throw error
        }
    }

    private func relayExternallyConnectableNativeConnectOpen(
        via webView: WKWebView,
        frameInfo: WKFrameInfo,
        session: ExternallyConnectableNativePortSession,
        connectInfo: [String: Any],
        timeoutMilliseconds: Double
    ) async throws {
        logExternallyConnectableBridgeEvent(
            "Starting native connect open portId=\(session.portId) ext=\(session.extensionId)"
        )

        _ = try await webView.callAsyncJavaScript(
            """
            const normalizedTimeoutMs = typeof timeoutMs === 'number' && timeoutMs > 0 ? timeoutMs : 30000;
            return await new Promise((resolve, reject) => {
                let settled = false;
                let timeoutHandle = null;

                function cleanup() {
                    window.removeEventListener('message', handleBridgeEvent);
                    if (timeoutHandle !== null) {
                        clearTimeout(timeoutHandle);
                    }
                }

                function finishWithError(message) {
                    if (settled) {
                        return;
                    }
                    settled = true;
                    cleanup();
                    reject(new Error(message));
                }

                function finishWithValue(value) {
                    if (settled) {
                        return;
                    }
                    settled = true;
                    cleanup();
                    resolve(value);
                }

                function handleBridgeEvent(event) {
                    if (event.source !== window) {
                        return;
                    }

                    const data = event.data;
                    if (!data || data.portId !== portId) {
                        return;
                    }
                    if (data.targetRuntimeId !== extensionId) {
                        return;
                    }

                    if (data.type === 'sumi_ec_connect_opened') {
                        finishWithValue(true);
                        return;
                    }

                    if (data.type === 'sumi_ec_connect_disconnect') {
                        finishWithError(data.error ? String(data.error) : 'Extension port disconnected during open');
                    }
                }

                window.addEventListener('message', handleBridgeEvent);
                timeoutHandle = setTimeout(() => {
                    finishWithError('Extension port open timeout');
                }, normalizedTimeoutMs);

                window.postMessage({
                    type: 'sumi_ec_connect_open',
                    targetRuntimeId: extensionId,
                    extensionId: extensionId,
                    connectInfo: connectInfo,
                    nativeExternal: true,
                    portId: portId,
                    sender: sender
                }, '*');
            });
            """,
            arguments: [
                "portId": session.portId,
                "extensionId": session.extensionId,
                "connectInfo": connectInfo,
                "sender": [
                    "origin": session.sourceOrigin as Any,
                    "url": session.frameURLString as Any,
                    "frameId": session.isMainFrame ? 0 : NSNull(),
                ] as [String: Any],
                "timeoutMs": timeoutMilliseconds,
            ],
            in: frameInfo,
            contentWorld: .defaultClient
        )
    }

    private func relayExternallyConnectableNativeConnectPostMessage(
        via webView: WKWebView,
        frameInfo: WKFrameInfo,
        portId: String,
        message: Any?
    ) async throws {
        guard let extensionId = ecRegistry.extensionIdForPort(portId) else {
            throw NSError(
                domain: "ExternallyConnectable",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Extension port is unavailable"]
            )
        }

        _ = try await webView.callAsyncJavaScript(
            """
            window.postMessage({
                type: 'sumi_ec_connect_post',
                targetRuntimeId: extensionId,
                portId: portId,
                message: bridgeMessage
            }, '*');
            return true;
            """,
            arguments: [
                "extensionId": extensionId,
                "portId": portId,
                "bridgeMessage": message ?? NSNull(),
            ],
            in: frameInfo,
            contentWorld: .page
        )
    }

    private func relayExternallyConnectableNativeConnectDisconnect(
        via webView: WKWebView,
        frameInfo: WKFrameInfo,
        portId: String
    ) async throws {
        let extensionId = ecRegistry.extensionIdForPort(portId) ?? ""
        _ = try await webView.callAsyncJavaScript(
            """
            window.postMessage({
                type: 'sumi_ec_connect_close',
                targetRuntimeId: extensionId,
                portId: portId
            }, '*');
            return true;
            """,
            arguments: [
                "extensionId": extensionId,
                "portId": portId,
            ],
            in: frameInfo,
            contentWorld: .page
        )
    }

    private func dispatchExternallyConnectableNativePortOpened(
        for session: ExternallyConnectableNativePortSession
    ) async throws {
        guard let webView = session.webView else {
            throw NSError(
                domain: "ExternallyConnectable",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Source webView is unavailable"]
            )
        }

        _ = try await webView.callAsyncJavaScript(
            """
            if (typeof window.__sumiEcNativePortOpened !== 'function') {
                return false;
            }
            return !!window.__sumiEcNativePortOpened(portId, payload);
            """,
            arguments: [
                "portId": session.portId,
                "payload": [
                    "name": session.connectName,
                    "extensionId": session.extensionId,
                ] as [String: Any],
            ],
            in: session.frameInfo,
            contentWorld: .page
        )
    }

    private func dispatchExternallyConnectableNativePortMessage(
        for session: ExternallyConnectableNativePortSession,
        message: Any?
    ) async throws {
        guard let webView = session.webView else {
            throw NSError(
                domain: "ExternallyConnectable",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Source webView is unavailable"]
            )
        }

        _ = try await webView.callAsyncJavaScript(
            """
            if (typeof window.__sumiEcNativePortMessage !== 'function') {
                return false;
            }
            return !!window.__sumiEcNativePortMessage(portId, portMessage);
            """,
            arguments: [
                "portId": session.portId,
                "portMessage": message ?? NSNull(),
            ],
            in: session.frameInfo,
            contentWorld: .page
        )
    }

    private func dispatchExternallyConnectableNativePortDisconnected(
        for session: ExternallyConnectableNativePortSession,
        errorMessage: String?
    ) async throws {
        guard let webView = session.webView else { return }

        _ = try await webView.callAsyncJavaScript(
            """
            if (typeof window.__sumiEcNativePortDisconnected !== 'function') {
                return false;
            }
            return !!window.__sumiEcNativePortDisconnected(portId, errorMessage);
            """,
            arguments: [
                "portId": session.portId,
                "errorMessage": errorMessage as Any,
            ],
            in: session.frameInfo,
            contentWorld: .page
        )
    }
}
