//
//  ExtensionActionSurfacePublicationOwner.swift
//  Sumi
//
//  Owns publication of extension action surface state (URL-hub badges and
//  labels) and post-enable runtime finalization for loaded contexts.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionSurfacePublicationOwner {
    struct Dependencies {
        let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
        let setActionSurfaceState: @MainActor (String, BrowserExtensionActionSurfaceState) -> Void
        let removeActionSurfaceState: @MainActor (String) -> Void
        let currentExtensionTab: @MainActor () -> Tab?
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let resolvedProfileId: @MainActor (UUID?) -> UUID?
        let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
        let ensureBackgroundAvailableIfRequired:
            @MainActor (WKWebExtension, WKWebExtensionContext, ExtensionManager.ExtensionBackgroundWakeReason) async throws -> Void
        let reconcileOpenTabsAfterExtensionContextLoad: @MainActor (String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        guard let update = ExtensionActionSurfaceStatePresenter.makeUpdate(
            for: action,
            extensionID: dependencies.extensionIDForContext(extensionContext)
        ) else { return }

        dependencies.setActionSurfaceState(update.extensionID, update.state)
    }

    func clearActionSurfaceState(for extensionId: String) {
        dependencies.removeActionSurfaceState(extensionId)
    }

    /// Publishes URL-hub action metadata when WebKit has not yet delivered `didUpdate action`.
    func publishActionSurfaceStateForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab? = nil
    ) {
        guard let action = ExtensionActionSurfaceStatePresenter.actionForLoadedContext(
            extensionContext,
            preferredTab: preferredTab,
            currentTab: { dependencies.currentExtensionTab() },
            stableAdapter: { dependencies.stableAdapter($0) }
        ) else { return }

        updateActionSurfaceState(for: action, extensionContext: extensionContext)
    }

    /// After context load, seed action state and optionally wake background for explicit
    /// lifecycle events such as user-enabled extension activation.
    func finalizeEnabledExtensionRuntime(
        for extensionId: String,
        profileId: UUID? = nil,
        backgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason? = nil
    ) async {
        let resolvedProfileId = dependencies.resolvedProfileId(profileId)
        guard let resolvedProfileId,
              let extensionContext = dependencies.getExtensionContext(
                  extensionId,
                  resolvedProfileId
              ) else { return }

        publishActionSurfaceStateForLoadedContext(extensionContext)

        if let backgroundWakeReason {
            let webExtension = extensionContext.webExtension
            do {
                try await dependencies.ensureBackgroundAvailableIfRequired(
                    webExtension,
                    extensionContext,
                    backgroundWakeReason
                )
            } catch {
                ExtensionManager.logger.error(
                    "Failed to wake background for \(extensionId, privacy: .public) after \(backgroundWakeReason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        dependencies.reconcileOpenTabsAfterExtensionContextLoad(
            "ExtensionManager.finalizeEnabledExtensionRuntime"
        )
    }
}

@available(macOS 15.5, *)
extension ExtensionActionSurfacePublicationOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            extensionIDForContext: { [weak manager] context in
                manager?.extensionID(for: context)
            },
            setActionSurfaceState: { [weak manager] extensionId, state in
                manager?.actionStatesByExtensionID[extensionId] = state
            },
            removeActionSurfaceState: { [weak manager] extensionId in
                manager?.actionStatesByExtensionID.removeValue(forKey: extensionId)
            },
            currentExtensionTab: { [weak manager] in
                manager?.browserBridgeContext?.currentExtensionTabForActiveWindow()
            },
            stableAdapter: { [weak manager] tab in
                manager?.adapterResolutionOwner.stableAdapter(for: tab)
            },
            resolvedProfileId: { [weak manager] profileId in
                manager?.resolvedProfileId(explicitProfileId: profileId)
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            ensureBackgroundAvailableIfRequired: { [weak manager] webExtension, context, reason in
                _ = try await manager?.ensureBackgroundAvailableIfRequired(
                    for: webExtension,
                    context: context,
                    reason: reason
                )
            },
            reconcileOpenTabsAfterExtensionContextLoad: { [weak manager] reason in
                manager?.reconcileOpenTabsAfterExtensionContextLoad(reason: reason)
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        actionSurfacePublicationOwner.updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )
    }

    func clearActionSurfaceState(for extensionId: String) {
        actionSurfacePublicationOwner.clearActionSurfaceState(for: extensionId)
    }

    func publishActionSurfaceStateForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab? = nil
    ) {
        actionSurfacePublicationOwner.publishActionSurfaceStateForLoadedContext(
            extensionContext,
            preferredTab: preferredTab
        )
    }

    func finalizeEnabledExtensionRuntime(
        for extensionId: String,
        profileId: UUID? = nil,
        backgroundWakeReason: ExtensionBackgroundWakeReason? = nil
    ) async {
        await actionSurfacePublicationOwner.finalizeEnabledExtensionRuntime(
            for: extensionId,
            profileId: profileId,
            backgroundWakeReason: backgroundWakeReason
        )
    }
}
