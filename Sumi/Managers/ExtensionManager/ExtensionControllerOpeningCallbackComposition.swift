import Foundation
import WebKit

#if DEBUG
@available(macOS 15.5, *)
@MainActor
enum ExtensionControllerOpeningCallbackComposition {
    struct Invocation {
        let evidence: ExtensionControllerCallbackEvidence
        let runtime: ExtensionControllerOpeningCallbackRuntime
    }

    static func invocation(
        callbacks: ExtensionBrowserAttachmentAuthority.ControllerCallbacks,
        context: WKWebExtensionContext,
        controller: WKWebExtensionController
    ) -> Invocation? {
        callbacks.openingInvocation(
            context: context,
            controller: controller
        )
    }
}
#endif
