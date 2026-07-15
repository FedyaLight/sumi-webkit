import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Website-data admission only; retained by the context-lifecycle graph.
    @MainActor
    final class WebsiteDataAdmission {
        private let attachedAdmission: @MainActor () ->
            ExtensionWebsiteDataMutationAdmission?

        init(attachment: ExtensionBrowserAttachmentAuthority) {
            attachedAdmission = { [weak attachment] in
                attachment?.websiteDataMutationAdmission()
            }
        }

        func wait(profileID: UUID) async -> Bool {
            guard let admission = attachedAdmission() else { return true }
            return await admission.wait(profileID: profileID)
        }

        func isBlocked(profileID: UUID) -> Bool {
            attachedAdmission()?.isBlocked(profileID: profileID) ?? false
        }
    }
}
