import Foundation
import WebKit

@available(macOS 15.5, *)
struct ExtensionRequestedTabTarget {
    let window: BrowserWindowState?
    let space: Space?
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabTargetResolver {
    private let browserContext: @MainActor () -> (any ExtensionTabTargetQuery)?
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let miniWindows: @MainActor (String, UUID?) -> [ExtensionMiniWindowAdapter]

    init(
        browserContext: @escaping @MainActor () -> (any ExtensionTabTargetQuery)?,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        miniWindows: @escaping @MainActor (
            String,
            UUID?
        ) -> [ExtensionMiniWindowAdapter]
    ) {
        self.browserContext = browserContext
        self.profileRuntime = profileRuntime
        self.runtime = runtime
        self.miniWindows = miniWindows
    }

    func resolve(
        requestedWindow: (any WKWebExtensionWindow)?,
        extensionContext: WKWebExtensionContext?
    ) throws -> ExtensionRequestedTabTarget {
        guard let browserContext = browserContext() else {
            throw ExtensionManagerCallbackError
                .requestedTabBrowserManagerUnavailable.nsError()
        }

        if let miniWindowAdapter = requestedWindow as? ExtensionMiniWindowAdapter,
           let session = browserContext.auxiliaryWindowSession(
               for: miniWindowAdapter.sessionId
           ) {
            return target(
                for: session.tab,
                extensionContext: extensionContext
            )
        }

        if requestedWindow == nil,
           let extensionContext,
           let ownerExtensionID = profileRuntime.extensionId(for: extensionContext),
           let profileId = profileRuntime.profileId(for: extensionContext),
           let miniWindowAdapter = miniWindows(ownerExtensionID, profileId).first,
           let session = browserContext.auxiliaryWindowSession(
               for: miniWindowAdapter.sessionId
           ) {
            return target(
                for: session.tab,
                extensionContext: extensionContext
            )
        }

        let contextProfileId = extensionContext.flatMap {
            profileRuntime.profileId(for: $0)
        }
        let requestedWindowState = (requestedWindow as? ExtensionWindowAdapter)
            .flatMap { browserContext.extensionWindowState(for: $0.windowId) }
        let currentRuntime = runtime()
        let targetWindow = [
            requestedWindowState,
            browserContext.activeExtensionWindowState,
        ].compactMap(\.self).first { windowState in
            contextProfileId.map {
                profileRuntime.windowMatchesProfile(
                    windowState,
                    profileId: $0,
                    runtime: currentRuntime
                )
            } ?? true
        }
        return ExtensionRequestedTabTarget(
            window: targetWindow,
            space: targetSpace(
                for: targetWindow,
                contextProfileId: contextProfileId
            )
        )
    }

    func targetSpace(
        for windowState: BrowserWindowState?,
        contextProfileId: UUID?
    ) -> Space? {
        guard let browserContext = browserContext() else {
            return nil
        }
        let windowSpace = browserContext.extensionTargetSpace(for: windowState)

        guard let contextProfileId else { return windowSpace }
        if windowSpace?.profileId == contextProfileId { return windowSpace }
        return browserContext.extensionTargetSpace(
            matchingProfile: contextProfileId
        )
    }

    private func target(
        for openerTab: Tab,
        extensionContext: WKWebExtensionContext?
    ) -> ExtensionRequestedTabTarget {
        ExtensionRequestedTabTarget(
            window: normalWindow(
                for: openerTab,
                extensionContext: extensionContext
            ),
            space: browserContext()?.extensionTargetSpace(for: openerTab)
        )
    }

    private func normalWindow(
        for openerTab: Tab,
        extensionContext: WKWebExtensionContext?
    ) -> BrowserWindowState? {
        guard let browserContext = browserContext() else {
            return nil
        }
        let currentRuntime = runtime()
        let targetProfileId = profileRuntime.resolvedProfileId(
            for: openerTab,
            runtime: currentRuntime
        )
            ?? extensionContext.flatMap { profileRuntime.profileId(for: $0) }
            ?? profileRuntime.resolvedProfileId(
                explicitProfileId: nil,
                runtime: currentRuntime
            )
        let candidates = [
            browserContext.extensionWindowState(containing: openerTab),
            browserContext.activeExtensionWindowState,
        ]
        return candidates.compactMap { $0 }.first { windowState in
            targetProfileId.map {
                profileRuntime.windowMatchesProfile(
                    windowState,
                    profileId: $0,
                    runtime: currentRuntime
                )
            } ?? true
        }
    }
}
