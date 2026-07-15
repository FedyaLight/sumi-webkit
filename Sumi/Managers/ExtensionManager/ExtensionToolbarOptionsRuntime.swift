import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionToolbarOptionsRuntime {
    private let contexts: ExtensionContextResidencyOwner
    private let currentProfileID: @MainActor () -> UUID?
    private let controller: @MainActor (UUID) -> WKWebExtensionController?
    private let callbacks: ExtensionBrowserAttachmentAuthority.ControllerCallbacks
    private let windows: ExtensionOptionsWindowService

    init(
        contexts: ExtensionContextResidencyOwner,
        currentProfileID: @escaping @MainActor () -> UUID?,
        controller: @escaping @MainActor (UUID) -> WKWebExtensionController?,
        callbacks: ExtensionBrowserAttachmentAuthority.ControllerCallbacks,
        windows: ExtensionOptionsWindowService
    ) {
        self.contexts = contexts
        self.currentProfileID = currentProfileID
        self.controller = controller
        self.callbacks = callbacks
        self.windows = windows
    }

    func context(extensionID: String) -> WKWebExtensionContext? {
        guard let profileID = currentProfileID() else { return nil }
        return contexts.loading.loadedContext(
            extensionID: extensionID,
            profileID: profileID
        )
    }

    func request(
        extensionID: String,
        profileID: UUID?,
        fallbackProfileID: UUID?
    ) async throws -> (
        service: ExtensionOptionsWindowService,
        invocation: ExtensionOptionsWindowCallbackComposition.Invocation
    )? {
        guard let profileID = profileID ?? currentProfileID() ?? fallbackProfileID
        else { return nil }
        guard let context = try await contexts.ensureExtensionLoaded(
            extensionId: extensionID,
            profileId: profileID
        ), let controller = controller(profileID),
        let invocation = callbacks.optionsInvocation(
            context: context,
            controller: controller
        ) else { return nil }
        return (windows, invocation)
    }

    func closeAllWindows() { windows.closeAllWindows() }
}
