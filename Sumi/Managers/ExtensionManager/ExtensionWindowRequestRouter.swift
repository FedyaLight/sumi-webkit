import Foundation
import WebKit

/// Routes WebKit normal-window requests either to an exact existing published
/// window for an external web flow, or to the browser's atomic initial-window
/// transaction. It never materializes a raw window adapter.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowRequestRouter {
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
        guard tabURLs.count <= 1 else {
            completion(
                nil,
                ExtensionManagerCallbackError
                    .multipleWindowTabsUnsupported.nsError()
            )
            return
        }
        guard let profileID = profileRuntime.profileId(for: controller),
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
               ExtensionActionPopupPresentation
                .isExtensionExternalWebPopupURL(firstURL),
               await self.openExternalTabInPublishedWindow(
                   firstURL,
                   profileID: profileID,
                   controller: controller,
                   extensionContext: extensionContext,
                   completion: completion
               ) {
                return
            }
            await self.openAtomicWindow(
                firstURL,
                profileID: profileID,
                controller: controller,
                extensionContext: extensionContext,
                completion: completion
            )
        }
    }

    private func openExternalTabInPublishedWindow(
        _ url: URL,
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
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
            extensionContext: extensionContext
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

        guard query.extensionWindowState(for: window.id) === window,
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
            extensionContext: extensionContext
        ), targetResolver.targetSpace(
            for: nil,
            contextProfileId: profileID
        ) === space,
           requestIsCurrent(
               profileID: profileID,
               controller: controller,
               extensionContext: extensionContext,
               load: load,
               space: space
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
            space: space
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
                  space: space
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
        extensionContext: WKWebExtensionContext?
    ) async -> Bool {
        guard requestIsCurrent(
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            load: load,
            space: targetSpace
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
            space: targetSpace
        )
    }

    private func requestIsCurrent(
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        load: ExtensionRequestedTabLoad,
        space: Space
    ) -> Bool {
        guard space.profileId == profileID,
              profileRuntime.profileId(for: controller) == profileID,
              profileRuntime.controllersByProfile[profileID] === controller
        else {
            return false
        }

        if let extensionContext {
            guard profileRuntime.profileId(for: extensionContext) == profileID
            else {
                return false
            }
        }

        if let loadContext = load.extensionContext {
            guard let loadURL = load.url,
                  profileRuntime.profileId(for: loadContext) == profileID,
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
        runtimeBundle.windowRequests.open(
            tabURLs: tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            completion: completionHandler
        )
    }
}
