import Foundation
import WebKit

/// Exact authority for one WebKit action-popup callback. Runtime binding and
/// installed-record authority must both survive every asynchronous boundary.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPopupCallbackEvidence {
    let runtimeBinding: ExtensionControllerCallbackEvidence
    let installedRecordRevision: UInt64
    let invocation: ExtensionActionPopupInvocationReceipt?

    var context: WKWebExtensionContext { runtimeBinding.context }
    var controller: WKWebExtensionController { runtimeBinding.controller }
    var extensionID: String { runtimeBinding.extensionID }
    var profileID: UUID { runtimeBinding.profileID }

    func attaching(
        invocation: ExtensionActionPopupInvocationReceipt?
    ) -> Self {
        .init(
            runtimeBinding: runtimeBinding,
            installedRecordRevision: installedRecordRevision,
            invocation: invocation
        )
    }

    func matches(_ receipt: ExtensionContextBindingReceipt) -> Bool {
        let binding = runtimeBinding
        return receipt.key.profileId == binding.profileID
            && receipt.key.extensionId == binding.extensionID
            && receipt.contextIdentifier == ObjectIdentifier(binding.context)
            && receipt.bindingRevision == binding.contextBindingRevision
            && receipt.controllerIdentifier == ObjectIdentifier(binding.controller)
            && receipt.controllerBindingRevision
                == binding.controllerBindingRevision
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupCallbackAdmission {
    private let runtimeBindingAdmission: ExtensionControllerCallbackAdmission
    private let installedExtensions: InstalledExtensionCollection

    init(
        runtimeBindingAdmission: ExtensionControllerCallbackAdmission,
        installedExtensions: InstalledExtensionCollection
    ) {
        self.runtimeBindingAdmission = runtimeBindingAdmission
        self.installedExtensions = installedExtensions
    }

    func capture(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController
    ) -> ExtensionActionPopupCallbackEvidence? {
        guard let runtimeBinding = runtimeBindingAdmission.capture(
                  context: context,
                  controller: controller
              ),
              installedExtensions.record(
                  for: runtimeBinding.extensionID
              )?.isEnabled == true
        else {
            return nil
        }
        return ExtensionActionPopupCallbackEvidence(
            runtimeBinding: runtimeBinding,
            installedRecordRevision: installedExtensions.recordRevision(
                for: runtimeBinding.extensionID
            ),
            invocation: nil
        )
    }

    func isCurrent(_ evidence: ExtensionActionPopupCallbackEvidence) -> Bool {
        runtimeBindingAdmission.isCurrent(evidence.runtimeBinding)
            && installedExtensions.recordRevision(for: evidence.extensionID)
                == evidence.installedRecordRevision
            && installedExtensions.record(for: evidence.extensionID)?
                .isEnabled == true
    }
}
