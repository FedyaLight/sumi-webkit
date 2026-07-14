import Foundation
import WebKit

/// Revalidates post-creation Tab/Space/window residence against the read-only
/// publication ledger. A registry window without an exact published adapter
/// cannot authorize registration or later selection.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabResidenceValidator {
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let publications: ExtensionWindowPublicationQuery
    private let windowEvidence: ExtensionRequestedWindowEvidence

    init(
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        publications: ExtensionWindowPublicationQuery,
        windowEvidence: ExtensionRequestedWindowEvidence
    ) {
        self.profileRuntime = profileRuntime
        self.runtime = runtime
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

        let currentRuntime = runtime()
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
            ?? profileRuntime.resolvedProfileId(
            for: tab,
            runtime: currentRuntime
        )
        let publicationIsCurrent = profileID.map { profileID in
            residencePolicy.requiresExtensionPublication == false
                || publications.publishedWindowAdapter(
                    for: window,
                    profileID: profileID
                ) != nil
        } ?? false
        guard let profileID,
              browser.extensionWindowState(for: window.id) === window,
              profileRuntime.windowMatchesProfile(
                  window,
                  profileId: profileID,
                  runtime: currentRuntime
              ), profileRuntime.resolvedProfileId(
                  for: tab,
                  runtime: currentRuntime
              ) == profileID,
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
