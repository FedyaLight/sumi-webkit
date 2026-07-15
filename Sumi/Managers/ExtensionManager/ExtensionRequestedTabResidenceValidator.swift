import Foundation
import WebKit

/// Revalidates post-creation Tab/Space/window residence against the read-only
/// publication ledger. A registry window without an exact published adapter
/// cannot authorize registration or later selection.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabResidenceValidator {
    private let tabProfiles: any ExtensionTabProfileResolving
    private let windowProfileID: @MainActor (BrowserWindowState) -> UUID?
    private let publications: ExtensionWindowPublicationQuery
    private let windowEvidence: ExtensionRequestedWindowEvidence

    init(
        tabProfiles: any ExtensionTabProfileResolving,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
        publications: ExtensionWindowPublicationQuery,
        windowEvidence: ExtensionRequestedWindowEvidence
    ) {
        self.tabProfiles = tabProfiles
        self.windowProfileID = windowProfileID
        self.publications = publications
        self.windowEvidence = windowEvidence
    }

    func validate(
        _ tab: Tab,
        target: ExtensionRequestedTabTarget,
        extensionContext: WKWebExtensionContext?,
        residencePolicy: ExtensionRequestedTabResidencePolicy,
        browser: any ExtensionTabTargetQuery
    ) throws -> BrowserWindowState? {
        let window = target.window
            ?? browser.preferredExtensionWindowState(containing: tab)
        guard let window else { return nil }

        let contextIdentity: (extensionID: String, profileID: UUID)?
        if let extensionContext {
            guard let current = windowEvidence.currentIdentity(
                for: extensionContext
            ) else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
            contextIdentity = current
        } else {
            contextIdentity = nil
        }
        let profileID = contextIdentity?.profileID
            ?? tabProfiles.profileID(for: tab)
        let publicationIsCurrent = profileID.map { profileID in
            residencePolicy.requiresExtensionPublication == false
                || publications.publishedWindowAdapter(
                    for: window,
                    profileID: profileID
                ) != nil
        } ?? false
        guard let profileID,
              browser.extensionWindowState(for: window.id) === window,
              windowProfileID(window) == profileID,
              tabProfiles.profileID(for: tab) == profileID,
              let tabSpace = browser.extensionTargetSpace(for: tab),
              let windowSpace = targetSpace(
                  for: window,
                  profileID: profileID,
                  browser: browser
              ), tabSpace === windowSpace,
              publicationIsCurrent
        else {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }
        return window
    }

    private func targetSpace(
        for window: BrowserWindowState,
        profileID: UUID,
        browser: any ExtensionTabTargetQuery
    ) -> Space? {
        let displayed = browser.extensionTargetSpace(for: window)
        if displayed?.profileId == profileID { return displayed }
        return browser.extensionTargetSpace(matchingProfile: profileID)
    }
}
