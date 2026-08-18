import Foundation
import WebKit

/// Immutable authority for one requested-Tab invocation. It binds an optional
/// WebKit callback receipt to the exact source/load extension context and has
/// no mutation or materialization capability.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabInvocationAuthority {
    private let profileRuntime: ExtensionProfileRuntime
    private let controller: WKWebExtensionController
    private let sourceContext: WKWebExtensionContext?
    private let evidence: ExtensionControllerCallbackEvidence?
    private let callbackAdmission: ExtensionControllerCallbackAdmission?

    init(
        profileRuntime: ExtensionProfileRuntime,
        controller: WKWebExtensionController,
        sourceContext: WKWebExtensionContext?,
        evidence: ExtensionControllerCallbackEvidence?,
        callbackAdmission: ExtensionControllerCallbackAdmission?
    ) {
        self.profileRuntime = profileRuntime
        self.controller = controller
        self.sourceContext = sourceContext
        self.evidence = evidence
        self.callbackAdmission = callbackAdmission
    }

    var isCurrent: Bool {
        guard let evidence else { return true }
        return callbackAdmission?.isCurrent(evidence) == true
            && evidence.controller === controller
            && evidence.context === sourceContext
    }

    func validateSource(for load: ExtensionRequestedTabLoad) throws {
        let controllerProfileID = profileRuntime.profileId(for: controller)
        let sourceIdentity = sourceContext.flatMap {
            profileRuntime.exactContextIdentity(for: $0)
        }
        if let sourceContext {
            guard let sourceIdentity,
                  let controllerProfileID,
                  profileRuntime.owns(
                    sourceContext,
                    extensionID: sourceIdentity.extensionId,
                    in: controllerProfileID
                  )
            else {
                throw unavailableError()
            }
        }
        if let loadContext = load.extensionContext {
            guard let sourceIdentity,
                  let loadIdentity = profileRuntime.exactContextIdentity(
                      for: loadContext
                  ),
                  let controllerProfileID,
                  profileRuntime.owns(
                    loadContext,
                    extensionID: loadIdentity.extensionId,
                    in: controllerProfileID
                  ),
                  sourceContext === loadContext,
                  sourceIdentity == loadIdentity
            else {
                throw unavailableError()
            }
        }
        if load.isOrdinaryBrowserRequest == false,
           load.extensionContext == nil {
            throw unavailableError()
        }
    }

    private func unavailableError() -> NSError {
        ExtensionManagerCallbackError.requestedTabUnavailable.nsError()
    }
}
