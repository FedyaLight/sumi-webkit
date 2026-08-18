import AppKit
import Foundation
import SumiDomain
import WebKit

/// Routes every WebKit normal-window request through the browser's reversible
/// initial-window transaction. The completion is settled only after all
/// requested URL tabs are published in the new window.
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
            request: ExtensionWindowOpeningRequest(
                windowType: .normal,
                frame: CGRect(
                    x: CGFloat.nan,
                    y: CGFloat.nan,
                    width: CGFloat.nan,
                    height: CGFloat.nan
                ),
                tabURLs: tabURLs,
                shouldBeFocused: true,
                shouldBePrivate: false
            ),
            controller: controller,
            extensionContext: extensionContext,
            authority: nil,
            completion: completion
        )
    }

    func open(
        request: ExtensionWindowOpeningRequest,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        open(
            request: request,
            controller: controller,
            extensionContext: extensionContext,
            authority: nil,
            completion: completion
        )
    }

    func open(
        request: ExtensionWindowOpeningRequest,
        evidence: ExtensionControllerCallbackEvidence,
        admission: ExtensionControllerCallbackAdmission,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        open(
            request: request,
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
        request: ExtensionWindowOpeningRequest,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        authority: CallbackAuthority?,
        completion: @escaping (
            (any WKWebExtensionWindow)?,
            (any Error)?
        ) -> Void
    ) {
        guard request.tabs.isEmpty else {
            completion(
                nil,
                ExtensionManagerCallbackError
                    .existingWindowTabMoveUnsupported.nsError()
            )
            return
        }
        guard authority?.isCurrent() ?? true,
              let profileID = profileRuntime.profileId(for: controller),
              profileRuntime.controller(for: profileID) === controller,
              extensionContext.map({
                  profileRuntime.owns($0, in: profileID)
              }) ?? true
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }
        guard windowQuery() != nil else {
            completion(
                nil,
                ExtensionManagerCallbackError.browserManagerUnavailable
                    .nsError()
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
            await self.openAtomicWindow(
                request,
                profileID: profileID,
                controller: controller,
                extensionContext: extensionContext,
                authority: authority,
                completion: completion
            )
        }
    }

    private func openAtomicWindow(
        _ request: ExtensionWindowOpeningRequest,
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
        let requestedURLs: [URL?] = request.tabURLs.isEmpty
            ? [nil]
            : request.tabURLs.map(Optional.some)
        let loads = requestedURLs.map {
            loadResolver.resolve($0, controller: controller)
        }
        guard loads.allSatisfy({ $0.hasUnresolvedExtensionOwnership == false })
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }
        for load in loads {
            guard await prepare(
                load,
                targetWindow: nil,
                targetSpace: space,
                profileID: profileID,
                controller: controller,
                extensionContext: extensionContext,
                authority: authority
            ) else {
                completion(
                    nil,
                    ExtensionManagerCallbackError.newWindowUnavailable.nsError()
                )
                return
            }
        }
        guard let initialLoad = loads.first,
              targetResolver.targetSpace(
            for: nil,
            contextProfileId: profileID
              ) === space,
           requestIsCurrent(
               profileID: profileID,
               controller: controller,
               extensionContext: extensionContext,
               loads: loads,
               space: space,
               authority: authority
           ),
           let creator = windowCreation(),
           let preparedWindow = creator.prepareExtensionRequestedWindow(
               ExtensionRequestedWindowSeed(
                   profileID: profileID,
                   space: space,
                   url: initialLoad.url,
                   webExtensionContext: initialLoad.extensionContext
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
        var stagedTabs: [Tab] = []
        var didAcceptWindow = false
        defer {
            if didAcceptWindow == false {
                for tab in stagedTabs.reversed() {
                    _ = tabOpening.discardStagedTab(
                        tab,
                        restoringSelectionTo: window.currentTabId
                    )
                }
                preparedWindow.cancel()
            }
        }
        guard requestIsCurrent(
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            loads: loads,
            space: space,
            authority: authority
        ), let adapter = publishedWindow(window, profileID),
           let nativeWindow = windowQuery()?.appKitWindow(for: window)
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }

        do {
            for load in loads.dropFirst() {
                let tab = try tabOpening.open(
                    url: load.url,
                    shouldBeActive: false,
                    shouldBePinned: false,
                    requestedWindow: adapter,
                    controller: controller,
                    extensionContext: extensionContext,
                    evidence: authority?.evidence,
                    callbackAdmission: authority?.admission,
                    recordsRecentRequest: false,
                    reason: "ExtensionWindowRequestRouter.additionalInitialTab"
                )
                stagedTabs.append(tab)
            }
        } catch {
            completion(
                nil,
                SumiWebExtensionCallbackErrorMapper
                    .webExtensionCallbackError(from: error)
            )
            return
        }

        applyRequestedFrame(request.frame, to: nativeWindow)
        guard preparedWindow.present(activate: request.shouldBeFocused),
              requestIsCurrent(
                  profileID: profileID,
                  controller: controller,
                  extensionContext: extensionContext,
                  loads: loads,
                  space: space,
                  authority: authority
              ),
              publishedWindow(window, profileID) === adapter
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }
        if let stateError = await applyRequestedState(
            request.windowState,
            to: adapter,
            extensionContext: extensionContext
        ) {
            completion(
                nil,
                SumiWebExtensionCallbackErrorMapper
                    .webExtensionCallbackError(from: stateError)
            )
            return
        }
        guard requestIsCurrent(
            profileID: profileID,
            controller: controller,
            extensionContext: extensionContext,
            loads: loads,
            space: space,
            authority: authority
        ), publishedWindow(window, profileID) === adapter,
           preparedWindow.accept()
        else {
            completion(
                nil,
                ExtensionManagerCallbackError.newWindowUnavailable.nsError()
            )
            return
        }
        request.tabURLs.forEach { tabOpening.recentRequests.record($0) }
        didAcceptWindow = true
        completion(adapter, nil)
    }

    private func applyRequestedFrame(_ requested: CGRect, to window: NSWindow) {
        let current = window.frame
        let resolved = CGRect(
            x: requested.origin.x.isFinite
                ? requested.origin.x : current.origin.x,
            y: requested.origin.y.isFinite
                ? requested.origin.y : current.origin.y,
            width: requested.size.width.isFinite
                ? requested.size.width : current.size.width,
            height: requested.size.height.isFinite
                ? requested.size.height : current.size.height
        )
        guard resolved.width > 0, resolved.height > 0 else { return }
        window.setFrame(resolved, display: false)
    }

    private func applyRequestedState(
        _ state: WKWebExtension.WindowState,
        to adapter: ExtensionWindowAdapter,
        extensionContext: WKWebExtensionContext?
    ) async -> Error? {
        guard state != .normal else { return nil }
        guard let extensionContext else {
            return ExtensionManagerCallbackError.newWindowUnavailable.nsError()
        }
        return await withCheckedContinuation { continuation in
            adapter.setWindowState(state, for: extensionContext) {
                continuation.resume(returning: $0)
            }
        }
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
        guard load.hasUnresolvedExtensionOwnership == false,
              authority?.isCurrent() ?? true,
              space.profileId == profileID,
              profileRuntime.controller(for: profileID) === controller
        else {
            return false
        }

        if let extensionContext {
            guard profileRuntime.owns(extensionContext, in: profileID)
            else {
                return false
            }
        }

        if let loadContext = load.extensionContext {
            guard let loadURL = load.url,
                  profileRuntime.owns(loadContext, in: profileID),
                  extensionContext.map({ $0 === loadContext }) ?? true,
                  controller.extensionContext(for: loadURL) === loadContext
            else {
                return false
            }
        }
        return true
    }

    private func requestIsCurrent(
        profileID: UUID,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        loads: [ExtensionRequestedTabLoad],
        space: Space,
        authority: CallbackAuthority?
    ) -> Bool {
        loads.allSatisfy {
            requestIsCurrent(
                profileID: profileID,
                controller: controller,
                extensionContext: extensionContext,
                load: $0,
                space: space,
                authority: authority
            )
        }
    }
}
