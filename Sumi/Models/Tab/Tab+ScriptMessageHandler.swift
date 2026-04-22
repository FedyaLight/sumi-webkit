import AppKit
import Foundation
import WebKit

// MARK: - WKScriptMessageHandler
extension Tab: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case coreScriptMessageHandlerName("linkHover"):
            let href = message.body as? String
            DispatchQueue.main.async {
                self.onLinkHover?(href)
            }

        case coreScriptMessageHandlerName("commandHover"):
            let href = message.body as? String
            DispatchQueue.main.async {
                self.onCommandHover?(href)
            }

        case coreScriptMessageHandlerName("commandClick"):
            if let payload = message.body as? [String: Any],
               let href = payload["href"] as? String,
               let url = URL(string: href)
            {
                let flags = modifierFlags(from: payload)
                DispatchQueue.main.async {
                    self.handleModifiedLinkClick(url: url, flags: flags)
                }
            } else if let href = message.body as? String, let url = URL(string: href) {
                DispatchQueue.main.async {
                    self.handleModifiedLinkClick(url: url, flags: [.command])
                }
            }

        case coreScriptMessageHandlerName("SumiIdentity"):
            handleOAuthRequest(message: message)

        default:
            break
        }
    }

    func setClickModifierFlags(_ flags: NSEvent.ModifierFlags) {
        clickModifierFlags = flags.intersection([.command, .option, .control, .shift])
    }

    func isGlanceTriggerActive(_ flags: NSEvent.ModifierFlags? = nil) -> Bool {
        guard sumiSettings?.glanceEnabled ?? true else { return false }

        let activeFlags = flags ?? clickModifierFlags
        switch sumiSettings?.glanceActivationMethod ?? .alt {
        case .ctrl:
            return activeFlags.contains(.control)
        case .alt:
            return activeFlags.contains(.option)
        case .shift:
            return activeFlags.contains(.shift)
        case .meta:
            return activeFlags.contains(.command)
        }
    }

    func openURLInGlance(_ url: URL) {
        browserManager?.peekManager.presentExternalURL(url, from: self)
    }

    private func modifierFlags(from payload: [String: Any]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (payload["metaKey"] as? Bool) == true { flags.insert(.command) }
        if (payload["altKey"] as? Bool) == true { flags.insert(.option) }
        if (payload["ctrlKey"] as? Bool) == true { flags.insert(.control) }
        if (payload["shiftKey"] as? Bool) == true { flags.insert(.shift) }
        return flags
    }

    private func handleModifiedLinkClick(url: URL, flags: NSEvent.ModifierFlags) {
        if isGlanceTriggerActive(flags) {
            openURLInGlance(url)
        } else if flags.contains(.command) {
            let context = BrowserManager.TabOpenContext.background(
                windowState: browserManager?.windowState(containing: self),
                sourceTab: self,
                preferredSpaceId: spaceId
            )
            browserManager?.openNewTab(
                url: url.absoluteString,
                context: context
            )
        }
    }

    func navigationModifierFlags(from navigationAction: WKNavigationAction) -> NSEvent.ModifierFlags {
        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        return flags.isEmpty ? clickModifierFlags : flags
    }

    private func handleOAuthRequest(message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let urlString = dict["url"] as? String,
              let url = URL(string: urlString) else {
            RuntimeDiagnostics.emit("❌ [Tab] Invalid OAuth request: missing or invalid URL")
            return
        }
        let interactive = dict["interactive"] as? Bool ?? true
        let rawRequestId = (dict["requestId"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let requestId = (rawRequestId?.isEmpty == false ? rawRequestId! : UUID().uuidString)

        RuntimeDiagnostics.emit(
            "🔐 [Tab] OAuth request received: id=\(requestId) url=\(url.absoluteString) interactive=\(interactive)"
        )

        guard let manager = browserManager else {
            finishIdentityFlow(requestId: requestId, with: .failure(.unableToStart))
            return
        }

        let identityRequest = AuthenticationManager.IdentityRequest(
            requestId: requestId,
            url: url,
            interactive: interactive
        )

        manager.authenticationManager.beginIdentityFlow(identityRequest, from: self)
    }

    func finishIdentityFlow(
        requestId: String,
        with result: AuthenticationManager.IdentityFlowResult
    ) {
        guard let webView = existingWebView else {
            RuntimeDiagnostics.emit("⚠️ [Tab] Unable to deliver identity result; webView missing")
            return
        }

        var payload: [String: Any] = ["requestId": requestId]

        switch result {
        case .success(let url):
            payload["status"] = "success"
            payload["url"] = url.absoluteString
        case .cancelled:
            payload["status"] = "cancelled"
            payload["code"] = "cancelled"
            payload["message"] = "Authentication cancelled by user."
        case .failure(let failure):
            payload["status"] = "failure"
            payload["code"] = failure.code
            payload["message"] = failure.message
        }

        if let status = payload["status"] as? String {
            let urlDescription = payload["url"] as? String ?? "nil"
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Identity flow completed: id=\(requestId) status=\(status) url=\(urlDescription)"
            )
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            RuntimeDiagnostics.emit("❌ [Tab] Failed to serialise identity payload for requestId=\(requestId)")
            return
        }

        let script =
            "window.__nookCompleteIdentityFlow && window.__nookCompleteIdentityFlow(\(jsonString));"
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                RuntimeDiagnostics.emit("❌ [Tab] Failed to deliver identity result: \(error.localizedDescription)")
            }
        }
    }

    func shouldRedirectToPeek(url: URL) -> Bool {
        if isGlanceTriggerActive() {
            return true
        }

        guard let currentHost = self.url.host,
              let newHost = url.host else { return false }

        return currentHost != newHost
    }
}
