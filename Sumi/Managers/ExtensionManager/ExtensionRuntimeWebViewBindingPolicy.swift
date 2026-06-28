import Foundation
import WebKit

@available(macOS 15.5, *)
enum ExtensionRuntimeWebViewBindingPolicy {
    static func canLateBindController(currentURL: URL?) -> Bool {
        guard let currentURL else {
            return true
        }

        let normalizedURL = currentURL.absoluteString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalizedURL.isEmpty || normalizedURL == "about:blank"
    }

    static func needsRuntimeRebuild(
        currentController: WKWebExtensionController?,
        expectedController: WKWebExtensionController?,
        currentURL: URL?
    ) -> Bool {
        guard let currentController else {
            return canLateBindController(currentURL: currentURL) == false
        }

        guard let expectedController else {
            return false
        }

        return currentController !== expectedController
    }
}
