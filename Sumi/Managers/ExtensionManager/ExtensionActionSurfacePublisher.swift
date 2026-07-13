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
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
    private let setActionSurfaceState: @MainActor (String, BrowserExtensionActionSurfaceState) -> Void
    private let removeActionSurfaceState: @MainActor (String) -> Void
    private let currentExtensionTab: @MainActor () -> Tab?
    private let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
    private let resolvedProfileId: @MainActor (UUID?) -> UUID?
    private let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
    private let ensureBackgroundAvailableIfRequired:
        @MainActor (WKWebExtension, WKWebExtensionContext, ExtensionManager.ExtensionBackgroundWakeReason) async throws -> Void
    private let reconcileOpenTabsAfterExtensionContextLoad: @MainActor (String) -> Void

    init(
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?,
        setActionSurfaceState: @escaping @MainActor (String, BrowserExtensionActionSurfaceState) -> Void,
        removeActionSurfaceState: @escaping @MainActor (String) -> Void,
        currentExtensionTab: @escaping @MainActor () -> Tab?,
        stableAdapter: @escaping @MainActor (Tab) -> ExtensionTabAdapter?,
        resolvedProfileId: @escaping @MainActor (UUID?) -> UUID?,
        getExtensionContext: @escaping @MainActor (String, UUID) -> WKWebExtensionContext?,
        ensureBackgroundAvailableIfRequired:
            @escaping @MainActor (WKWebExtension, WKWebExtensionContext, ExtensionManager.ExtensionBackgroundWakeReason) async throws -> Void,
        reconcileOpenTabsAfterExtensionContextLoad: @escaping @MainActor (String) -> Void
    ) {
        self.extensionIDForContext = extensionIDForContext
        self.setActionSurfaceState = setActionSurfaceState
        self.removeActionSurfaceState = removeActionSurfaceState
        self.currentExtensionTab = currentExtensionTab
        self.stableAdapter = stableAdapter
        self.resolvedProfileId = resolvedProfileId
        self.getExtensionContext = getExtensionContext
        self.ensureBackgroundAvailableIfRequired = ensureBackgroundAvailableIfRequired
        self.reconcileOpenTabsAfterExtensionContextLoad = reconcileOpenTabsAfterExtensionContextLoad
    }

    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        guard let update = ExtensionActionSurfaceStatePresenter.makeUpdate(
            for: action,
            extensionID: extensionIDForContext(extensionContext)
        ) else { return }

        setActionSurfaceState(update.extensionID, update.state)
    }

    func clearActionSurfaceState(for extensionId: String) {
        removeActionSurfaceState(extensionId)
    }

    /// Publishes URL-hub action metadata when WebKit has not yet delivered `didUpdate action`.
    func publishActionSurfaceStateForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab? = nil
    ) {
        guard let action = ExtensionActionSurfaceStatePresenter.actionForLoadedContext(
            extensionContext,
            preferredTab: preferredTab,
            currentTab: { currentExtensionTab() },
            stableAdapter: { stableAdapter($0) }
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
        guard let resolvedProfileId = self.resolvedProfileId(profileId),
              let extensionContext = getExtensionContext(
                  extensionId,
                  resolvedProfileId
              ) else { return }

        publishActionSurfaceStateForLoadedContext(extensionContext)

        if let backgroundWakeReason {
            let webExtension = extensionContext.webExtension
            do {
                try await ensureBackgroundAvailableIfRequired(
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

        reconcileOpenTabsAfterExtensionContextLoad(
            "ExtensionActionSurfacePublisher.finalizeEnabledExtensionRuntime"
        )
    }
}

@available(macOS 15.5, *)
extension ExtensionActionSurfacePublisher {
    convenience init(manager: ExtensionManager) {
        self.init(
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
                manager?.extensionWindowQuery?
                    .currentExtensionTabForActiveWindow()
            },
            stableAdapter: { [weak manager] tab in
                manager?.adapterCatalog.stableAdapter(for: tab)
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
                guard manager?.attachedBrowserManager != nil,
                      manager?.controllerRuntimeComposition != nil
                else {
                    return
                }
                manager?.reloadRuntimePublications(reason: reason)
            }
        )
    }
}
