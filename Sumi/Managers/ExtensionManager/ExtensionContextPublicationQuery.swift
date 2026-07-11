import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextPublicationQuery {
    private weak var profileRuntime: ExtensionProfileRuntime?

    init(profileRuntime: ExtensionProfileRuntime) {
        self.profileRuntime = profileRuntime
    }

    func currentIdentity(
        for context: WKWebExtensionContext
    ) -> (extensionID: String, profileID: UUID)? {
        guard let identity = profileRuntime?.exactContextIdentity(for: context)
        else {
            return nil
        }
        return (identity.extensionId, identity.profileId)
    }

    func isCurrent(
        _ context: WKWebExtensionContext,
        extensionID: String,
        profileID: UUID
    ) -> Bool {
        guard let identity = currentIdentity(for: context) else {
            return false
        }
        return identity.extensionID == extensionID
            && identity.profileID == profileID
    }
}
