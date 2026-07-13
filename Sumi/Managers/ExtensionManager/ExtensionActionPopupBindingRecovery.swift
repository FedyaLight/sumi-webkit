import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionExactContextRetiring: AnyObject {
    func retire(
        _ receipt: ExtensionContextBindingReceipt
    ) -> ExtensionContextRetirement.Outcome
}

@available(macOS 15.5, *)
extension ExtensionContextRetirement: ExtensionExactContextRetiring {}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionActionPopupContextLoading: AnyObject {
    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext?
}

@available(macOS 15.5, *)
extension ExtensionContextResidencyOwner: ExtensionActionPopupContextLoading {}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionActionPopupBindingRecovering: AnyObject {
    func recover(_ stalled: ExtensionContextBindingReceipt) async -> Bool
}

/// Recovers WebKit's pre-presentation popup failure mode by replacing the
/// entire exact context binding. A local timer or WKWebView reload cannot
/// distinguish a delayed callback from a newer click because WebKit exposes
/// no invocation token.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupBindingRecovery:
    ExtensionActionPopupBindingRecovering {
    private let contextRetirement: any ExtensionExactContextRetiring
    private let contextLoading: any ExtensionActionPopupContextLoading
    private let profileRuntime: ExtensionProfileRuntime

    init(
        contextRetirement: any ExtensionExactContextRetiring,
        contextLoading: any ExtensionActionPopupContextLoading,
        profileRuntime: ExtensionProfileRuntime
    ) {
        self.contextRetirement = contextRetirement
        self.contextLoading = contextLoading
        self.profileRuntime = profileRuntime
    }

    func recover(_ stalled: ExtensionContextBindingReceipt) async -> Bool {
        switch contextRetirement.retire(stalled) {
        case .retired, .superseded:
            break
        case .notBound, .controllerUnavailable, .unloadFailed,
             .retirementInProgress:
            return false
        }

        let key = stalled.key
        let loadedContext: WKWebExtensionContext?
        do {
            loadedContext = try await contextLoading.ensureExtensionLoaded(
                extensionId: key.extensionId,
                profileId: key.profileId
            )
        } catch {
            return false
        }
        guard let context = loadedContext,
              let fresh = profileRuntime.contextBindingReceipt(
                  extensionId: key.extensionId,
                  profileId: key.profileId
              ),
              let controller = profileRuntime.controller(ifCurrent: fresh),
              fresh.contextIdentifier == ObjectIdentifier(context),
              fresh.contextIdentifier != stalled.contextIdentifier,
              fresh.bindingRevision != stalled.bindingRevision,
              context.webExtensionController === controller,
              controller.extensionContexts.contains(where: { $0 === context })
        else {
            return false
        }
        return true
    }
}
