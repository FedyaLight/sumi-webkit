import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionControllerDelegateBridge {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let (invocation, windows) = optionsInvocation(
            context: extensionContext,
            controller: controller
        )
        else {
            completionHandler(CancellationError())
            return
        }
        windows.presentOptionsPageWindow(
            invocation: invocation,
            completionHandler: completionHandler
        )
    }
}
