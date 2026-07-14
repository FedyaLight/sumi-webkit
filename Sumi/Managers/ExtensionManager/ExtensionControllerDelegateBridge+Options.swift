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
        guard let manager = loadedManagerForCallback(),
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler(CancellationError())
            return
        }
        guard let invocation = ExtensionOptionsWindowCallbackComposition
            .invocation(from: manager, evidence: evidence)
        else {
            completionHandler(ExtensionOptionsPageResolution.notFoundError())
            return
        }
        manager.optionsWindows.presentOptionsPageWindow(
            invocation: invocation,
            completionHandler: completionHandler
        )
    }
}
