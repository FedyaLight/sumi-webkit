import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabContextPreloader {
    let loadResolver: ExtensionRequestedTabLoadResolver
    let placement: ExtensionRequestedTabTargetResolver
    private let profileRuntime: ExtensionProfileRuntime
    private let windowProfileID: @MainActor (BrowserWindowState) -> UUID?
    private let currentProfileID: @MainActor () -> UUID?
    private let contextLoading: any ExtensionContentScriptContextLoading

    init(
        loadResolver: ExtensionRequestedTabLoadResolver,
        placement: ExtensionRequestedTabTargetResolver,
        profileRuntime: ExtensionProfileRuntime,
        windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
        currentProfileID: @escaping @MainActor () -> UUID?,
        contextLoading: any ExtensionContentScriptContextLoading
    ) {
        self.loadResolver = loadResolver
        self.placement = placement
        self.profileRuntime = profileRuntime
        self.windowProfileID = windowProfileID
        self.currentProfileID = currentProfileID
        self.contextLoading = contextLoading
    }

    @discardableResult
    func prepare(
        url: URL?,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil
    ) async throws -> UUID? {
        let load = loadResolver.resolve(url, controller: controller)
        return try await prepare(
            load: load,
            requestedWindow: requestedWindow,
            controller: controller,
            extensionContext: extensionContext
        )
    }

    @discardableResult
    func prepare(
        load: ExtensionRequestedTabLoad,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?
    ) async throws -> UUID? {
        guard load.requiresContentScriptPreload else { return nil }
        let target = try placement.resolve(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext
        )
        return await prepare(
            load: load,
            targetWindow: target.window,
            targetSpace: target.space,
            controller: controller
        )
    }

    @discardableResult
    func prepare(
        load: ExtensionRequestedTabLoad,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?,
        controller: WKWebExtensionController
    ) async -> UUID? {
        guard load.requiresContentScriptPreload else { return nil }
        let profileId = targetSpace?.profileId
            ?? targetWindow.flatMap(windowProfileID)
            ?? profileRuntime.profileId(for: controller)
            ?? currentProfileID()
        guard let profileId else {
            return nil
        }

        await contextLoading
            .ensureContentScriptContextsLoaded(for: profileId)
        return profileId
    }
}
