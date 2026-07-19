//
//  ExtensionActionSurfacePublisher.swift
//  Sumi
//
//  Owns publication of extension action surface state (URL-hub badges and
//  labels) and post-enable runtime finalization for loaded contexts.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionSurfacePublisher {
    typealias BackgroundWake = @MainActor (
        WKWebExtension,
        WKWebExtensionContext,
        ExtensionManager.ExtensionBackgroundWakeReason,
        @escaping @MainActor () -> Bool
    ) async throws -> Void

    private let authority: ExtensionLoadedContextAuthority
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
    private let setActionSurfaceState: @MainActor (String, BrowserExtensionActionSurfaceState) -> Void
    private let removeActionSurfaceState: @MainActor (String) -> Void
    private let publishActionPresentationChange:
        @MainActor (ExtensionActionPresentationChange) -> Void
    private let exactContextIdentity:
        @MainActor (WKWebExtensionContext) -> (extensionID: String, profileID: UUID)?
    private let actionForLoadedContext: @MainActor (
        WKWebExtensionContext,
        Tab?
    ) -> WKWebExtension.Action?
    private let ensureBackgroundAvailableIfRequired:
        @MainActor (
            WKWebExtension,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            @escaping @MainActor () -> Bool
        ) async throws -> Void
    private let prepareBrowserProjectionForBackgroundWake:
        @MainActor (String, UUID) -> Void
    #if DEBUG
        private var debugBackgroundWake: BackgroundWake?
        private var debugPrepareBrowserProjection:
            (@MainActor (String, UUID) -> Void)?
    #endif

    init(
        authority: ExtensionLoadedContextAuthority,
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?,
        setActionSurfaceState: @escaping @MainActor (String, BrowserExtensionActionSurfaceState) -> Void,
        removeActionSurfaceState: @escaping @MainActor (String) -> Void,
        publishActionPresentationChange: @escaping @MainActor (
            ExtensionActionPresentationChange
        ) -> Void,
        exactContextIdentity: @escaping @MainActor (
            WKWebExtensionContext
        ) -> (extensionID: String, profileID: UUID)?,
        actionForLoadedContext: @escaping @MainActor (
            WKWebExtensionContext,
            Tab?
        ) -> WKWebExtension.Action?,
        ensureBackgroundAvailableIfRequired:
        @escaping @MainActor (
            WKWebExtension,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            @escaping @MainActor () -> Bool
        ) async throws -> Void,
        prepareBrowserProjectionForBackgroundWake:
            @escaping @MainActor (String, UUID) -> Void
    ) {
        self.authority = authority
        self.extensionIDForContext = extensionIDForContext
        self.setActionSurfaceState = setActionSurfaceState
        self.removeActionSurfaceState = removeActionSurfaceState
        self.publishActionPresentationChange = publishActionPresentationChange
        self.exactContextIdentity = exactContextIdentity
        self.actionForLoadedContext = actionForLoadedContext
        self.ensureBackgroundAvailableIfRequired = ensureBackgroundAvailableIfRequired
        self.prepareBrowserProjectionForBackgroundWake =
            prepareBrowserProjectionForBackgroundWake
    }

    #if DEBUG
        func installDebugFinalization(
            backgroundWake: BackgroundWake?,
            prepareBrowserProjection:
                (@MainActor (String, UUID) -> Void)?
        ) {
            debugBackgroundWake = backgroundWake
            debugPrepareBrowserProjection = prepareBrowserProjection
        }
    #endif

    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        guard let update = ExtensionActionSurfaceStatePresenter.makeUpdate(
            for: action,
            extensionID: extensionIDForContext(extensionContext)
        ) else { return }

        setActionSurfaceState(update.extensionID, update.state)
        guard let identity = exactContextIdentity(extensionContext),
              identity.extensionID == update.extensionID
        else { return }
        publishActionPresentationChange(
            ExtensionActionPresentationChange(
                extensionID: identity.extensionID,
                profileID: identity.profileID
            )
        )
    }

    func clearActionSurfaceState(for extensionId: String) {
        removeActionSurfaceState(extensionId)
        publishActionPresentationChange(
            ExtensionActionPresentationChange(
                extensionID: extensionId,
                profileID: nil
            )
        )
    }

    /// Publishes URL-hub action metadata when WebKit has not yet delivered `didUpdate action`.
    func publishActionSurfaceStateForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab? = nil
    ) {
        guard let action = actionForLoadedContext(
            extensionContext,
            preferredTab
        ) else { return }

        updateActionSurfaceState(for: action, extensionContext: extensionContext)
    }

    /// After context load, seed action state and optionally wake background for explicit
    /// lifecycle events such as user-enabled extension activation.
    func finalizeEnabledExtensionRuntime(
        _ loadedContext: ExtensionLoadedContext,
        backgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason? = nil
    ) async throws {
        try validate(loadedContext)
        let extensionId = loadedContext.bindingReceipt.key.extensionId
        let extensionContext = loadedContext.context

        publishActionSurfaceStateForLoadedContext(extensionContext)
        try validate(loadedContext)

        if let backgroundWakeReason {
            guard let identity = exactContextIdentity(extensionContext),
                  identity.extensionID == extensionId
            else {
                throw CancellationError()
            }
            prepareBrowserProjection(
                "ExtensionActionSurfacePublisher.beforeBackgroundWake",
                profileID: identity.profileID
            )
            try validate(loadedContext)
            let webExtension = extensionContext.webExtension
            do {
                try await wakeBackground(
                    webExtension,
                    extensionContext,
                    backgroundWakeReason,
                    { [weak self] in
                        self?.isCurrent(loadedContext) == true
                    }
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                ExtensionManager.logger.error(
                    "Failed to wake background for \(extensionId, privacy: .public) after \(backgroundWakeReason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        try validate(loadedContext)

    }

    private func validate(
        _ loadedContext: ExtensionLoadedContext
    ) throws {
        try authority.validate(loadedContext)
    }

    private func isCurrent(
        _ loadedContext: ExtensionLoadedContext
    ) -> Bool {
        do {
            try authority.validate(loadedContext)
            return true
        } catch {
            return false
        }
    }

    private func wakeBackground(
        _ webExtension: WKWebExtension,
        _ context: WKWebExtensionContext,
        _ reason: ExtensionManager.ExtensionBackgroundWakeReason,
        _ isCurrent: @escaping @MainActor () -> Bool
    ) async throws {
        #if DEBUG
            if let debugBackgroundWake {
                try await debugBackgroundWake(
                    webExtension,
                    context,
                    reason,
                    isCurrent
                )
                return
            }
        #endif
        try await ensureBackgroundAvailableIfRequired(
            webExtension,
            context,
            reason,
            isCurrent
        )
    }

    private func prepareBrowserProjection(
        _ reason: String,
        profileID: UUID
    ) {
        #if DEBUG
            if let debugPrepareBrowserProjection {
                debugPrepareBrowserProjection(reason, profileID)
                return
            }
        #endif
        prepareBrowserProjectionForBackgroundWake(reason, profileID)
    }
}
