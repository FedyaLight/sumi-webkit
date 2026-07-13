import WebKit

@available(macOS 15.5, *)
enum ExtensionRuntimeWebViewBindingPolicy {
    static func needsRuntimeRebuild(
        currentController: WKWebExtensionController?,
        expectedController: WKWebExtensionController?
    ) -> Bool {
        guard let currentController else {
            return expectedController != nil
        }

        guard let expectedController else {
            return false
        }

        return currentController !== expectedController
    }
}
