import Foundation
import SumiDomain
import WebKit

/// Routes WebKit normal-window requests either to an exact existing published
/// window for an external web flow, or to the browser's atomic initial-window
/// transaction. It never materializes a raw window adapter.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowRequestRouter {
    private struct CallbackAuthority {
        let evidence: ExtensionControllerCallbackEvidence
        let admission: ExtensionControllerCallbackAdmission

        @MainActor
        func isCurrent() -> Bool {
            admission.isCurrent(evidence)
        }
    }
    private let profileRuntime: ExtensionProfileRuntime
    private let targetResolver: ExtensionRequestedTabTargetResolver
    private let loadResolver: ExtensionRequestedTabLoadResolver
    private let contextPreloader: ExtensionRequestedTabContextPreloader
    private let tabOpening: ExtensionRequestedTabOpeningService
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let windowCreation:
        @MainActor () -> (any ExtensionRequestedWindowCreating)?
    private let publishedWindow: @MainActor (
        BrowserWindowState,
        UUID
    ) -> ExtensionWindowAdapter?

    init(
        profileRuntime: ExtensionProfileRuntime,
        targetResolver: ExtensionRequestedTabTargetResolver,
        loadResolver: ExtensionRequestedTabLoadResolver,
        contextPreloader: ExtensionRequestedTabContextPreloader,
        tabOpening: ExtensionRequestedTabOpeningService,
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        windowCreation:
            @escaping @MainActor () -> (any ExtensionRequestedWindowCreating)?,
        publishedWindow: @escaping @MainActor (
            BrowserWindowState,
            UUID
        ) -> ExtensionWindowAdapter?
    ) {
        self.profileRuntime = profileRuntime
        self.targetResolver = targetResolver
        self.loadResolver = loadResolver
        self.contextPreloader = contextPreloader
        self.tabOpening = tabOpening
        self.windowQuery = windowQuery
        self.windowCreation = windowCreation
        self.publishedWindow = publishedWindow
    }

    func open(
        tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        open(
            tabURLs: tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            authority: nil,
            completion: completion
        )
    }

    func open(
        tabURLs: [URL],
        evidence: ExtensionControllerCallbackEvidence,
        admission: ExtensionControllerCallbackAdmission,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        open(
            tabURLs: tabURLs,
            controller: evidence.controller,
            extensionContext: evidence.context,
            authority: CallbackAuthority(
                evidence: evidence,
                admission: admission
            ),
            completion: completion
        )
    }

    private func open(
        tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        authority: CallbackAuthority?,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        guard tabURLs.count <= 1 else {
            completion(
                nil,
                ExtensionManagerCallbackError
                    .multipleWindowTabsUnsupported.nsError()
            )
            return
        }
        guard authority?.isCurrent() ?? true,
              let profileID = profileRuntime.profileId(for: controller),
              profileRuntime.controllersByProfile[profileID] === controller,
              extensionContext.map({
                  profileRuntime.profileId(for: $0) == profileID
              }) ?? true
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion(
                    nil,
                    ExtensionManagerCallbackError
                        .extensionManagerUnavailable.nsError()
                )
                return
            }
            let firstURL = tabURLs.first
            if let firstURL,
               Self.isExternalWebPopupURL(firstURL),
               await self.openExternalTabInPublishedWindow(
                   firstURL,
                   profileID: profileID,
                   controller: controller,
                   extensionContext: extensionContext,
                   authority: authority,
                   completion: completion
               ) {
                return
            }
            await self.openAtomicWindow(
                firstURL,
                profileID: profileID,
                controller: controller,
                extensionContext: extensionContext,
                authority: authority,
                completion: completion
            )
        }
    }

    private nonisolated static func isExternalWebPopupURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              ExtensionURLIdentity.isOwned(url) == false
        else { return false }
        return true
    }

    private func openExternalTabInPublishedWindow(
        _ url: URL,
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        authority: CallbackAuthority?,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) async -> Bool {
        guard let query = windowQuery(),
              let window = query.activeExtensionWindowState,
              query.extensionWindowState(for: window.id) === window,
              let adapter = publishedWindow(window, profileID),
              let space = targetResolver.targetSpace(
                  for: window,
                  contextProfileId: profileID
              ),
              space.profileId == profileID
        else {
            return false
        }

        let load = loadResolver.resolve(url, controller: controller)
        guard await prepare(
            load,
            targetWindow: window,
            targetSpace: space,
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            authority: authority
        ), query.extensionWindowState(for: window.id) === window,
           publishedWindow(window, profileID) === adapter,
           targetResolver.targetSpace(
               for: window,
               contextProfileId: profileID
           ) === space
        else {
            return false
        }

        do {
            _ = try tabOpening.open(
                url: url,
                shouldBeActive: true,
                shouldBePinned: false,
                requestedWindow: adapter,
                controller: controller,
                extensionContext: extensionContext,
                evidence: authority?.evidence,
                callbackAdmission: authority?.admission,
                reason: "ExtensionWindowRequestRouter.externalTab"
            )
        } catch {
            completion(
                nil,
                ExtensionManagerCallbackError
                    .extensionExternalTabUnavailable.nsError()
            )
            return true
        }

        guard authority?.isCurrent() ?? true,
              query.extensionWindowState(for: window.id) === window,
              publishedWindow(window, profileID) === adapter
        else {
            completion(
                nil,
                ExtensionManagerCallbackError
                    .extensionExternalTabUnavailable.nsError()
            )
            return true
        }
        completion(adapter, nil)
        return true
    }

    private func openAtomicWindow(
        _ url: URL?,
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        authority: CallbackAuthority?,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) async {
        guard let space = targetResolver.targetSpace(
            for: nil,
            contextProfileId: profileID
        ), space.profileId == profileID else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }
        let load = loadResolver.resolve(url, controller: controller)
        guard await prepare(
            load,
            targetWindow: nil,
            targetSpace: space,
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            authority: authority
        ), targetResolver.targetSpace(
            for: nil,
            contextProfileId: profileID
        ) === space,
           requestIsCurrent(
               profileID: profileID,
               controller: controller,
               extensionContext: extensionContext,
               load: load,
               space: space,
               authority: authority
           ),
           let creator = windowCreation(),
           let preparedWindow = creator.prepareExtensionRequestedWindow(
               ExtensionRequestedWindowSeed(
                   profileID: profileID,
                   space: space,
                   url: load.url,
                   webExtensionContext: load.extensionContext
               )
           )
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }

        let window = preparedWindow.window
        guard requestIsCurrent(
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            load: load,
            space: space,
            authority: authority
        ), let adapter = publishedWindow(window, profileID)
        else {
            preparedWindow.cancel()
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }

        guard preparedWindow.present(),
              requestIsCurrent(
                  profileID: profileID,
                  controller: controller,
                  extensionContext: extensionContext,
                  load: load,
                  space: space,
                  authority: authority
              ),
              publishedWindow(window, profileID) === adapter,
              preparedWindow.accept()
        else {
            preparedWindow.cancel()
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }
        completion(adapter, nil)
    }

    private func prepare(
        _ load: ExtensionRequestedTabLoad,
        targetWindow: BrowserWindowState?,
        targetSpace: Space,
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        authority: CallbackAuthority?
    ) async -> Bool {
        guard requestIsCurrent(
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            load: load,
            space: targetSpace,
            authority: authority
        ) else {
            return false
        }
        let preparedProfileID = await contextPreloader.prepare(
            load: load,
            targetWindow: targetWindow,
            targetSpace: targetSpace,
            controller: controller
        )
        if load.requiresContentScriptPreload,
           preparedProfileID != profileID {
            return false
        }
        return requestIsCurrent(
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            load: load,
            space: targetSpace,
            authority: authority
        )
    }

    private func requestIsCurrent(
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        load: ExtensionRequestedTabLoad,
        space: Space,
        authority: CallbackAuthority?
    ) -> Bool {
        guard authority?.isCurrent() ?? true,
              space.profileId == profileID,
              profileRuntime.profileId(for: controller) == profileID,
              profileRuntime.controllersByProfile[profileID] === controller
        else {
            return false
        }

        if let extensionContext {
            guard profileRuntime.exactContextIdentity(
                for: extensionContext
            )?.profileId == profileID
            else {
                return false
            }
        }

        if let loadContext = load.extensionContext {
            guard let loadURL = load.url,
                  profileRuntime.exactContextIdentity(
                    for: loadContext
                  )?.profileId == profileID,
                  extensionContext.map({ $0 === loadContext }) ?? true,
                  controller.extensionContext(for: loadURL) === loadContext
            else {
                return false
            }
        }
        return true
    }
}

@available(macOS 15.5, *)
extension ExtensionWindowRequestRouter {
    convenience init(manager: ExtensionManager) {
        self.init(
            profileRuntime: manager.profileRuntime,
            targetResolver: manager.requestedTabTargetResolver,
            loadResolver: manager.requestedTabLoadResolver,
            contextPreloader: manager.requestedTabContextPreloader,
            tabOpening: manager.requestedTabOpening,
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            windowCreation: { [weak manager] in
                manager?.extensionRequestedWindowCreation
            },
            publishedWindow: { [weak manager] window, profileID in
                manager?.windowPublications.publishedWindowAdapter(
                    for: window,
                    profileID: profileID
                )
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func openExtensionWindowUsingTabURLs(
        _ configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        completionHandler: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            completionHandler: completionHandler
        )
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        completionHandler: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        guard tabURLs.count <= 1 else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError
                    .multipleWindowTabsUnsupported.nsError()
            )
            return
        }
        guard attachedBrowserManager != nil,
              controllerRuntimeComposition != nil
        else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.browserManagerUnavailable
                    .nsError()
            )
            return
        }
        extensionWindowRequestRouter.open(
            tabURLs: tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            completion: completionHandler
        )
    }
}
