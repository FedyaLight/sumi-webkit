import Foundation
import WebKit

@available(macOS 15.5, *)
struct ExtensionRequestedTabTarget {
    let window: BrowserWindowState?
    let space: Space?
}

/// Public requested-Tab target transaction surface. Initial policy, explicit
/// adapter proof, and post-creation residence validation remain independent.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabTargetResolver {
    private let browserContext: @MainActor () -> (any ExtensionTabTargetQuery)?
    private let initial: ExtensionRequestedTabInitialTargetResolver
    private let residence: ExtensionRequestedTabResidenceValidator

    init(
        browserContext: @escaping @MainActor () -> (any ExtensionTabTargetQuery)?,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        publications: ExtensionWindowPublicationQuery
    ) {
        self.browserContext = browserContext
        let evidence = ExtensionRequestedWindowEvidence(
            profileRuntime: profileRuntime,
            runtime: runtime,
            publications: publications
        )
        initial = ExtensionRequestedTabInitialTargetResolver(
            browserContext: browserContext,
            profileRuntime: profileRuntime,
            runtime: runtime,
            publications: publications,
            windowEvidence: evidence
        )
        residence = ExtensionRequestedTabResidenceValidator(
            profileRuntime: profileRuntime,
            runtime: runtime,
            publications: publications,
            windowEvidence: evidence
        )
    }

    func resolve(
        requestedWindow: (any WKWebExtensionWindow)?,
        extensionContext: WKWebExtensionContext?
    ) throws -> ExtensionRequestedTabTarget {
        try initial.resolve(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext
        )
    }

    func publishedResidence(
        for tab: Tab,
        target: ExtensionRequestedTabTarget,
        extensionContext: WKWebExtensionContext?
    ) throws -> BrowserWindowState? {
        guard let browser = browserContext() else {
            throw ExtensionManagerCallbackError
                .requestedTabBrowserManagerUnavailable.nsError()
        }
        return try residence.validate(
            tab,
            target: target,
            extensionContext: extensionContext,
            browser: browser
        )
    }

    func targetSpace(
        for windowState: BrowserWindowState?,
        contextProfileId: UUID?
    ) -> Space? {
        initial.targetSpace(
            for: windowState,
            contextProfileId: contextProfileId
        )
    }
}
