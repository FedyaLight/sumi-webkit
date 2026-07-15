import Foundation
import WebKit

/// Chooses the initial Space/window target from exact explicit evidence or the
/// currently published fallback. Post-creation residence validation is a
/// separate transaction stage.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabInitialTargetResolver {
    private let browserContext: @MainActor () -> (any ExtensionTabTargetQuery)?
    private let tabProfiles: any ExtensionTabProfileResolving
    private let currentProfileID: @MainActor () -> UUID?
    private let windowProfileID: @MainActor (BrowserWindowState) -> UUID?
    private let publications: ExtensionWindowPublicationQuery
    private let windowEvidence: ExtensionRequestedWindowEvidence

    init(
        browserContext: @escaping @MainActor () -> (any ExtensionTabTargetQuery)?,
        tabProfiles: any ExtensionTabProfileResolving,
        currentProfileID: @escaping @MainActor () -> UUID?,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
        publications: ExtensionWindowPublicationQuery,
        windowEvidence: ExtensionRequestedWindowEvidence
    ) {
        self.browserContext = browserContext
        self.tabProfiles = tabProfiles
        self.currentProfileID = currentProfileID
        self.windowProfileID = windowProfileID
        self.publications = publications
        self.windowEvidence = windowEvidence
    }

    func resolve(
        requestedWindow: (any WKWebExtensionWindow)?,
        extensionContext: WKWebExtensionContext?,
        residencePolicy: ExtensionRequestedTabResidencePolicy
    ) throws -> ExtensionRequestedTabTarget {
        guard let browser = browserContext() else {
            throw ExtensionManagerCallbackError
                .requestedTabBrowserManagerUnavailable.nsError()
        }
        if let extensionContext,
           windowEvidence.currentIdentity(for: extensionContext) == nil {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }

        if let requestedWindow {
            switch try windowEvidence.explicitProjection(
                for: requestedWindow,
                extensionContext: extensionContext,
                browser: browser
            ) {
            case .auxiliary(let session):
                return target(
                    for: session.tab,
                    extensionContext: extensionContext,
                    residencePolicy: residencePolicy
                )
            case .normal(let window):
                return ExtensionRequestedTabTarget(
                    window: window,
                    space: targetSpace(
                        for: window,
                        contextProfileId: extensionContext.flatMap {
                            windowEvidence.currentIdentity(for: $0)?.profileID
                        }
                    )
                )
            }
        }

        if let extensionContext,
           let session = windowEvidence.firstPublishedMiniWindowSession(
               for: extensionContext,
               browser: browser
           ) {
            return target(
                for: session.tab,
                extensionContext: extensionContext,
                residencePolicy: residencePolicy
            )
        }

        let profileID = extensionContext.flatMap {
            windowEvidence.currentIdentity(for: $0)?.profileID
        } ?? currentProfileID()
        let window = browser.activeExtensionWindowState.flatMap {
            candidate -> BrowserWindowState? in
            let publicationIsCurrent = profileID.map { profileID in
                residencePolicy.requiresExtensionPublication == false
                    || publications.publishedWindowAdapter(
                        for: candidate,
                        profileID: profileID
                    ) != nil
            } ?? false
            guard browser.extensionWindowState(for: candidate.id)
                    === candidate,
                  let profileID,
                  windowProfileID(candidate) == profileID,
                  publicationIsCurrent
            else {
                return nil
            }
            return candidate
        }
        return ExtensionRequestedTabTarget(
            window: window,
            space: targetSpace(
                for: window,
                contextProfileId: profileID
            )
        )
    }

    func targetSpace(
        for window: BrowserWindowState?,
        contextProfileId: UUID?
    ) -> Space? {
        guard let browser = browserContext() else { return nil }
        let displayed = browser.extensionTargetSpace(for: window)
        guard let contextProfileId else { return displayed }
        if displayed?.profileId == contextProfileId { return displayed }
        return browser.extensionTargetSpace(
            matchingProfile: contextProfileId
        )
    }

    private func target(
        for openerTab: Tab,
        extensionContext: WKWebExtensionContext?,
        residencePolicy: ExtensionRequestedTabResidencePolicy
    ) -> ExtensionRequestedTabTarget {
        ExtensionRequestedTabTarget(
            window: eligibleNormalWindow(
                for: openerTab,
                extensionContext: extensionContext,
                residencePolicy: residencePolicy
            ),
            space: browserContext()?.extensionTargetSpace(for: openerTab)
        )
    }

    private func eligibleNormalWindow(
        for openerTab: Tab,
        extensionContext: WKWebExtensionContext?,
        residencePolicy: ExtensionRequestedTabResidencePolicy
    ) -> BrowserWindowState? {
        guard let browser = browserContext() else { return nil }
        let profileID = tabProfiles.profileID(for: openerTab)
            ?? extensionContext.flatMap {
            windowEvidence.currentIdentity(for: $0)?.profileID
        } ?? currentProfileID()
        let candidates = [
            browser.extensionWindowState(containing: openerTab),
            browser.activeExtensionWindowState,
        ]
        return candidates.compactMap { $0 }.first { window in
            let publicationIsCurrent = profileID.map { profileID in
                residencePolicy.requiresExtensionPublication == false
                    || publications.publishedWindowAdapter(
                        for: window,
                        profileID: profileID
                    ) != nil
            } ?? false
            guard browser.extensionWindowState(for: window.id) === window,
                  let profileID,
                  windowProfileID(window) == profileID,
                  publicationIsCurrent
            else {
                return false
            }
            return true
        }
    }
}
