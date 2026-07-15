import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Evidence capture plus attached callback execution for controller
    /// opening/options callbacks. No callback runtime service is returned.
    @MainActor
    final class ControllerCallbacks {
        struct Environment {
            let openingCallbacks: ExtensionControllerOpeningCallbackRuntime
            let optionsComposer: ExtensionOptionsWindowCallbackComposer
        }

        private let attachedEnvironment: @MainActor () -> Environment?
        private let admission: ExtensionControllerCallbackAdmission

        init(
            attachment: ExtensionBrowserAttachmentAuthority,
            admission: ExtensionControllerCallbackAdmission
        ) {
            attachedEnvironment = { [weak attachment] in
                attachment?.controllerCallbackEnvironment()
            }
            self.admission = admission
        }

        #if DEBUG
            func openingInvocation(
                context: WKWebExtensionContext,
                controller: WKWebExtensionController
            ) -> ExtensionControllerOpeningCallbackComposition.Invocation? {
                guard let evidence = admission.capture(
                    context: context,
                    controller: controller
                ), let environment = attachedEnvironment()
                else { return nil }
                return ExtensionControllerOpeningCallbackComposition.Invocation(
                    evidence: evidence,
                    runtime: environment.openingCallbacks
                )
            }

            func optionsInvocation(
                evidence: ExtensionControllerCallbackEvidence
            ) -> ExtensionOptionsWindowCallbackComposition.Invocation? {
                attachedEnvironment()?.optionsComposer.invocation(
                    evidence: evidence
                )
            }

        #endif

        func optionsInvocation(
            context: WKWebExtensionContext,
            controller: WKWebExtensionController
        ) -> ExtensionOptionsWindowCallbackComposition.Invocation? {
            guard let evidence = admission.capture(
                context: context,
                controller: controller
            ) else { return nil }
            return attachedEnvironment()?.optionsComposer.invocation(
                evidence: evidence
            )
        }
    }
}
