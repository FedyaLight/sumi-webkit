import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabContextPreloader {
    let loadResolver: ExtensionRequestedTabLoadResolver
    let targetResolver: ExtensionRequestedTabTargetResolver
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let contextLoading: any ExtensionContentScriptContextLoading

    init(
        loadResolver: ExtensionRequestedTabLoadResolver,
        targetResolver: ExtensionRequestedTabTargetResolver,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        contextLoading: any ExtensionContentScriptContextLoading
    ) {
        self.loadResolver = loadResolver
        self.targetResolver = targetResolver
        self.profileRuntime = profileRuntime
        self.runtime = runtime
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
        guard load.requiresContentScriptPreload else { return nil }
        let target = try targetResolver.resolve(
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
        let currentRuntime = runtime()
        let profileId = targetSpace?.profileId
            ?? targetWindow.flatMap {
                profileRuntime.resolvedProfileId(
                    for: $0,
                    runtime: currentRuntime
                )
            }
            ?? profileRuntime.profileId(for: controller)
            ?? profileRuntime.resolvedProfileId(
                explicitProfileId: nil,
                runtime: currentRuntime
            )
        guard let profileId else {
            return nil
        }

        await contextLoading
            .ensureContentScriptContextsLoaded(for: profileId)
        return profileId
    }
}
