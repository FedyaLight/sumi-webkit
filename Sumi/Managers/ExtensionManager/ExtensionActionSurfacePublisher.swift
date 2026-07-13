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
    private let authority: ExtensionLoadedContextAuthority
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
    private let setActionSurfaceState: @MainActor (String, BrowserExtensionActionSurfaceState) -> Void
    private let removeActionSurfaceState: @MainActor (String) -> Void
    private let currentExtensionTab: @MainActor () -> Tab?
    private let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
    private let ensureBackgroundAvailableIfRequired:
        @MainActor (
            WKWebExtension,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            @escaping @MainActor () -> Bool
        ) async throws -> Void
    private let reconcileOpenTabsAfterExtensionContextLoad: @MainActor (String) -> Void

    init(
        authority: ExtensionLoadedContextAuthority,
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?,
        setActionSurfaceState: @escaping @MainActor (String, BrowserExtensionActionSurfaceState) -> Void,
        removeActionSurfaceState: @escaping @MainActor (String) -> Void,
        currentExtensionTab: @escaping @MainActor () -> Tab?,
        stableAdapter: @escaping @MainActor (Tab) -> ExtensionTabAdapter?,
        ensureBackgroundAvailableIfRequired:
            @escaping @MainActor (
                WKWebExtension,
                WKWebExtensionContext,
                ExtensionManager.ExtensionBackgroundWakeReason,
                @escaping @MainActor () -> Bool
            ) async throws -> Void,
        reconcileOpenTabsAfterExtensionContextLoad: @escaping @MainActor (String) -> Void
    ) {
        self.authority = authority
        self.extensionIDForContext = extensionIDForContext
        self.setActionSurfaceState = setActionSurfaceState
        self.removeActionSurfaceState = removeActionSurfaceState
        self.currentExtensionTab = currentExtensionTab
        self.stableAdapter = stableAdapter
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
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext,
        backgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason? = nil
    ) async throws {
        try validate(loadedContext)
        let extensionId = loadedContext.bindingReceipt.key.extensionId
        let extensionContext = loadedContext.context

        publishActionSurfaceStateForLoadedContext(extensionContext)
        try validate(loadedContext)

        if let backgroundWakeReason {
            let webExtension = extensionContext.webExtension
            do {
                try await ensureBackgroundAvailableIfRequired(
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

        reconcileOpenTabsAfterExtensionContextLoad(
            "ExtensionActionSurfacePublisher.finalizeEnabledExtensionRuntime"
        )
    }

    private func validate(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) throws {
        try authority.validate(loadedContext)
    }

    private func isCurrent(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) -> Bool {
        do {
            try authority.validate(loadedContext)
            return true
        } catch {
            return false
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionActionSurfacePublisher {
    convenience init(manager: ExtensionManager) {
        self.init(
            authority: manager.loadedContextAuthority,
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
            ensureBackgroundAvailableIfRequired: { [weak manager] webExtension, context, reason, isCurrent in
                _ = try await manager?.ensureBackgroundAvailableIfRequired(
                    for: webExtension,
                    context: context,
                    reason: reason,
                    isCurrent: isCurrent
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
