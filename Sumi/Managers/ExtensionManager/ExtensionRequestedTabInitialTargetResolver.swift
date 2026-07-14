import Foundation
import WebKit

/// Chooses the initial Space/window target from exact explicit evidence or the
/// currently published fallback. Post-creation residence validation is a
/// separate transaction stage.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabInitialTargetResolver {
    private let browserContext: @MainActor () -> (any ExtensionTabTargetQuery)?
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let publications: ExtensionWindowPublicationQuery
    private let windowEvidence: ExtensionRequestedWindowEvidence

    init(
        browserContext: @escaping @MainActor () -> (any ExtensionTabTargetQuery)?,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        publications: ExtensionWindowPublicationQuery,
        windowEvidence: ExtensionRequestedWindowEvidence
    ) {
        self.browserContext = browserContext
        self.profileRuntime = profileRuntime
        self.runtime = runtime
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

        let currentRuntime = runtime()
        let profileID = extensionContext.flatMap {
            windowEvidence.currentIdentity(for: $0)?.profileID
        } ?? profileRuntime.resolvedProfileId(
            explicitProfileId: nil,
            runtime: currentRuntime
        )
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
                  profileRuntime.windowMatchesProfile(
                      candidate,
                      profileId: profileID,
                      runtime: currentRuntime
                  ), publicationIsCurrent
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
        let currentRuntime = runtime()
        let profileID = profileRuntime.resolvedProfileId(
            for: openerTab,
            runtime: currentRuntime
        ) ?? extensionContext.flatMap {
            windowEvidence.currentIdentity(for: $0)?.profileID
        } ?? profileRuntime.resolvedProfileId(
            explicitProfileId: nil,
            runtime: currentRuntime
        )
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
                  profileRuntime.windowMatchesProfile(
                      window,
                      profileId: profileID,
                      runtime: currentRuntime
                  ), publicationIsCurrent
            else {
                return false
            }
            return true
        }
    }
}
