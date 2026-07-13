import Foundation
import WebKit

/// Immutable proof that one WebKit callback came from the exact context and
/// controller currently bound to an extension profile runtime generation.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerCallbackEvidence {
    let context: WKWebExtensionContext
    let controller: WKWebExtensionController
    let profileID: UUID
    let extensionID: String
    let controllerBindingRevision: UInt64
    let contextBindingRevision: UInt64
    let extensionLoadRevision: ExtensionLoadRevision
}

/// Captures and revalidates exact WebKit callback authority. It deliberately
/// has no manager root and performs no fallback identity resolution or repair.
@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerCallbackAdmission {
    private let profileRuntime: ExtensionProfileRuntime
    private let extensionLoadRevisions: ExtensionLoadRevisionAuthority

    init(
        profileRuntime: ExtensionProfileRuntime,
        extensionLoadRevisions: ExtensionLoadRevisionAuthority
    ) {
        self.profileRuntime = profileRuntime
        self.extensionLoadRevisions = extensionLoadRevisions
    }

    func capture(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController
    ) -> ExtensionControllerCallbackEvidence? {
        guard let identity = profileRuntime.exactContextIdentity(for: context),
              profileRuntime.contexts(for: identity.profileId)[
                  identity.extensionId
              ] === context,
              profileRuntime.controller(for: identity.profileId) === controller
        else {
            return nil
        }

        return ExtensionControllerCallbackEvidence(
            context: context,
            controller: controller,
            profileID: identity.profileId,
            extensionID: identity.extensionId,
            controllerBindingRevision: profileRuntime
                .controllerBindingRevision(for: identity.profileId),
            contextBindingRevision: profileRuntime.contextBindingRevision(
                extensionId: identity.extensionId,
                profileId: identity.profileId
            ),
            extensionLoadRevision: extensionLoadRevisions.issue()
        )
    }

    func isCurrent(_ evidence: ExtensionControllerCallbackEvidence) -> Bool {
        extensionLoadRevisions.isCurrent(evidence.extensionLoadRevision)
            && profileRuntime.controllerBindingRevision(
                for: evidence.profileID
            ) == evidence.controllerBindingRevision
            && profileRuntime.contextBindingRevision(
                extensionId: evidence.extensionID,
                profileId: evidence.profileID
            ) == evidence.contextBindingRevision
            && profileRuntime.controller(for: evidence.profileID)
                === evidence.controller
            && profileRuntime.contexts(for: evidence.profileID)[
                evidence.extensionID
            ] === evidence.context
            && profileRuntime.exactContextIdentity(for: evidence.context)
                .map {
                    $0.profileId == evidence.profileID
                        && $0.extensionId == evidence.extensionID
                } == true
    }
}
