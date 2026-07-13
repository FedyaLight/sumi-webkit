import Foundation
import SwiftData
import WebKit

/// Owns extension runtime lifecycle transitions: profile switches, lazy
/// runtime requests, and runtime load bootstrapping.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLifecycleOwner {
    struct Dependencies {
        let modelContext: ModelContext
        let profileRuntime: ExtensionProfileRuntime
        let browserConfiguration: BrowserConfiguration
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let isExtensionSupportAvailable: @MainActor () -> Bool
        let hasEnabledInstalledExtensions: @MainActor () -> Bool
        let currentProfileId: @MainActor () -> UUID?
        let resolvedProfileId: @MainActor (UUID?) -> UUID?
        let runtimeState: @MainActor () -> ExtensionManager.ExtensionRuntimeState
        let setRuntimeState: @MainActor (ExtensionManager.ExtensionRuntimeState) -> Void
        let setExtensionsLoaded: @MainActor (Bool) -> Void
        let setAllowsRuntimeWithoutEnabledExtensions: @MainActor (Bool) -> Void
        let ensureExtensionController: @MainActor (UUID) -> WKWebExtensionController
        let reconcileProfileWebViewRuntime: @MainActor (UUID) -> Void
        let unloadExtensionContextsForInactiveProfiles: @MainActor (UUID) -> Void
        let clearActionPopupAnchors: @MainActor (UUID) -> Void
        let reloadPinnedToolbarExtensionsForCurrentProfile: @MainActor () -> Void
        let refreshActionSurfaceStateForCurrentProfile: @MainActor () -> Void
        let extensionRuntimeReadinessContext: @MainActor (UUID) -> ExtensionRuntimeReadinessContext
        let markExtensionRuntimeReadyIfProfileContextsLoaded: @MainActor (UUID) -> Void
        let countLoadedExtensionContexts: @MainActor () -> Int
        let extensionControllerDescription: @MainActor (WKWebExtensionController?) -> String
        let trace: @MainActor (String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func switchProfile(profileId: UUID) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.switchProfile")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.switchProfile", signpostState)
        }

        let runtimeState = dependencies.runtimeState()
        let runtimeInitialized = dependencies.profileRuntime.activateProfile(
            profileId,
            hasExtensionDemand: dependencies.hasEnabledInstalledExtensions(),
            runtimeIsReadyOrLoading: runtimeState == .ready || runtimeState == .loading
        )
        dependencies.clearActionPopupAnchors(profileId)
        dependencies.reloadPinnedToolbarExtensionsForCurrentProfile()

        guard dependencies.isExtensionSupportAvailable() else { return }

        guard runtimeInitialized else { return }

        let controller = dependencies.ensureExtensionController(profileId)
        dependencies.browserConfiguration.webViewConfiguration.webExtensionController = controller
        dependencies.unloadExtensionContextsForInactiveProfiles(profileId)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.dependencies.reconcileProfileWebViewRuntime(profileId)
            self.dependencies.refreshActionSurfaceStateForCurrentProfile()
        }
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionManager.ExtensionRuntimeRequestReason,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil
    ) -> WKWebExtensionController? {
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeRequested")

        guard dependencies.isExtensionSupportAvailable() else {
            dependencies.setRuntimeState(.unavailable)
            dependencies.setExtensionsLoaded(true)
            return nil
        }

        let hasDemand = dependencies.hasEnabledInstalledExtensions()
            || allowWithoutEnabledExtensions
        guard hasDemand else {
            dependencies.setExtensionsLoaded(true)
            return nil
        }

        if allowWithoutEnabledExtensions {
            dependencies.setAllowsRuntimeWithoutEnabledExtensions(true)
        }

        let resolvedProfileId = dependencies.resolvedProfileId(profileId)
        let controller: WKWebExtensionController
        if let resolvedProfileId {
            controller = dependencies.ensureExtensionController(resolvedProfileId)
        } else {
            controller = ensureExtensionController(reason: reason)
        }

        if dependencies.runtimeState() == .loading {
            return controller
        }

        if dependencies.runtimeState() == .ready {
            // Configuration demand can originate inside a WebView rebuild.
            // Re-entering reconciliation here would recursively submit the
            // same rebuild while its replacement is still being prepared.
            if reason != .webViewConfiguration,
               let profileId = resolvedProfileId ?? dependencies.currentProfileId() {
                dependencies.reconcileProfileWebViewRuntime(profileId)
            }
            return controller
        }

        startExtensionRuntimeLoad(
            reason: reason,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: resolvedProfileId
        )
        return controller
    }

    @discardableResult
    func requestExtensionRuntimeAndWait(
        reason: ExtensionManager.ExtensionRuntimeRequestReason,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil,
        extensionId: String? = nil
    ) async -> Bool {
        let resolvedProfileId = dependencies.resolvedProfileId(profileId)

        if let resolvedProfileId,
           dependencies.extensionRuntimeReadinessContext(resolvedProfileId)
           .canUseExistingRuntime(extensionID: extensionId) {
            dependencies.markExtensionRuntimeReadyIfProfileContextsLoaded(resolvedProfileId)
            return true
        }

        guard requestExtensionRuntime(
            reason: reason,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: resolvedProfileId
        ) != nil else {
            return false
        }

        if let resolvedProfileId,
           dependencies.extensionRuntimeReadinessContext(resolvedProfileId)
           .isReadyAfterRuntimeRequest(extensionID: extensionId) {
            dependencies.markExtensionRuntimeReadyIfProfileContextsLoaded(resolvedProfileId)
            return true
        }

        if let resolvedProfileId,
           dependencies.extensionRuntimeReadinessContext(resolvedProfileId)
           .allowsReadyControllerFallback(extensionID: extensionId) {
            return true
        }

        return false
    }

    private func ensureExtensionController(
        reason: ExtensionManager.ExtensionRuntimeRequestReason
    ) -> WKWebExtensionController {
        let profileId =
            dependencies.currentProfileId()
            ?? dependencies.profileRuntime.currentProfile(in: dependencies.runtime())?.id
            ?? UUID()
        let controller = dependencies.ensureExtensionController(profileId)
        dependencies.trace(
            "runtime controller initialized reason=\(reason.rawValue) profile=\(profileId.uuidString) controller=\(dependencies.extensionControllerDescription(controller))"
        )
        return controller
    }

    private func startExtensionRuntimeLoad(
        reason: ExtensionManager.ExtensionRuntimeRequestReason,
        allowWithoutEnabledExtensions: Bool,
        profileId: UUID?
    ) {
        let resolvedProfileId = dependencies.resolvedProfileId(profileId)

        let hasDemand =
            enabledPersistedExtensionEntities().isEmpty == false
            || allowWithoutEnabledExtensions
        guard hasDemand else {
            dependencies.setExtensionsLoaded(true)
            dependencies.setRuntimeState(.idle)
            return
        }

        guard let resolvedProfileId else {
            dependencies.setExtensionsLoaded(true)
            dependencies.setRuntimeState(.idle)
            return
        }

        dependencies.setRuntimeState(.loading)
        _ = dependencies.ensureExtensionController(resolvedProfileId)
        dependencies.setExtensionsLoaded(true)
        dependencies.markExtensionRuntimeReadyIfProfileContextsLoaded(resolvedProfileId)
        dependencies.trace(
            "lazyRuntime controller-only reason=\(reason.rawValue) profileId=\(resolvedProfileId.uuidString) loadedContexts=\(dependencies.countLoadedExtensionContexts())"
        )
    }

    func enabledPersistedExtensionEntities() -> [ExtensionEntity] {
        do {
            return try dependencies.modelContext.fetch(FetchDescriptor<ExtensionEntity>())
                .filter(\.isEnabled)
        } catch {
            ExtensionManager.logger.error("Failed to fetch enabled extensions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

}

@available(macOS 15.5, *)
extension ExtensionRuntimeLifecycleOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            modelContext: manager.context,
            profileRuntime: manager.profileRuntime,
            browserConfiguration: manager.browserConfiguration,
            runtime: { [weak manager] in manager?.runtime ?? .inactive },
            isExtensionSupportAvailable: { [weak manager] in
                manager?.isExtensionSupportAvailable ?? false
            },
            hasEnabledInstalledExtensions: { [weak manager] in
                manager?.hasEnabledInstalledExtensions ?? false
            },
            currentProfileId: { [weak manager] in manager?.profileRuntime.currentProfileId },
            resolvedProfileId: { [weak manager] explicitProfileId in
                manager?.resolvedProfileId(explicitProfileId: explicitProfileId)
            },
            runtimeState: { [weak manager] in manager?.runtimeSession.runtimeState ?? .idle },
            setRuntimeState: { [weak manager] state in manager?.runtimeSession.runtimeState = state },
            setExtensionsLoaded: { [weak manager] loaded in
                manager?.extensionsLoaded = loaded
            },
            setAllowsRuntimeWithoutEnabledExtensions: { [weak manager] allows in
                manager?.runtimeSession.allowsRuntimeWithoutEnabledExtensions = allows
            },
            ensureExtensionController: { [weak manager] profileId in
                guard let manager else {
                    preconditionFailure("ExtensionManager dependency used after deallocation")
                }
                return manager.ensureExtensionController(for: profileId)
            },
            reconcileProfileWebViewRuntime: { [weak manager] profileId in
                manager?.controllerRuntimeComposition?.reconciler.reconcile(
                    profileID: profileId,
                    reason: "ExtensionRuntimeLifecycle"
                )
            },
            unloadExtensionContextsForInactiveProfiles: { [weak manager] profileId in
                manager?.unloadExtensionContextsForInactiveProfiles(keepingProfileId: profileId)
            },
            clearActionPopupAnchors: { [weak manager] profileId in
                manager?.actionPopupAnchorStore.clearAnchors(notMatching: profileId)
            },
            reloadPinnedToolbarExtensionsForCurrentProfile: { [weak manager] in
                manager?.reloadPinnedToolbarExtensionsForCurrentProfile()
            },
            refreshActionSurfaceStateForCurrentProfile: { [weak manager] in
                manager?.refreshActionSurfaceStateForCurrentProfile()
            },
            extensionRuntimeReadinessContext: { [weak manager] profileId in
                guard let manager else {
                    preconditionFailure("ExtensionManager dependency used after deallocation")
                }
                return manager.extensionRuntimeReadinessContext(for: profileId)
            },
            markExtensionRuntimeReadyIfProfileContextsLoaded: { [weak manager] profileId in
                manager?.markExtensionRuntimeReadyIfProfileContextsLoaded(for: profileId)
            },
            countLoadedExtensionContexts: { [weak manager] in
                manager?.countLoadedExtensionContexts() ?? 0
            },
            extensionControllerDescription: { controller in
                ExtensionRuntimeDiagnostics.objectDescription(controller)
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message)
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func attach(browserManager: BrowserManager) {
        if let attachedBrowserManager {
            precondition(
                attachedBrowserManager === browserManager,
                "ExtensionManager cannot move between browser runtimes"
            )
            return
        }
        precondition(
            controllerRuntimeComposition == nil,
            "ExtensionManager supports one browser runtime attachment"
        )
        attachedBrowserManager = browserManager
        let bridge = browserManager.extensionBridgeComposition
        extensionWindowQuery = bridge.windows
        extensionTabQuery = bridge.tabs
        controllerRuntimeComposition = ExtensionControllerRuntimeAssembler
            .assemble(
                tabs: bridge.tabs,
                inventory: bridge.tabs,
                selectedWebViews: bridge.webViews,
                residences: bridge.webViews,
                rebuilder: bridge.webViews,
                windowProfiles: bridge.windows,
                runtimeSession: runtimeSession,
                profileRuntime: profileRuntime,
                contexts: contextPublications,
                preludeInstaller:
                    permissionsOriginsCompatibilityPreludeInstallationOwner,
                diagnostics: runtimeDiagnostics
            )
        requestedTabTargetQuery = bridge.requestedTabTargets
        extensionTabMutation = bridge.tabMutation
        extensionWindowActivation = bridge.windowActivation
        extensionWebViewHosting = bridge.webViews
        extensionAuxiliaryWindows = bridge.auxiliaryWindows
        extensionWindowPresentation = bridge.presentation
        extensionRequestedWindowCreation = bridge.requestedWindows
        runtime = BrowserExtensionManagerRuntimeFactory.runtime(for: browserManager)
        if runtime.activeWindowState() == nil,
           let currentProfile = runtime.currentProfile() {
            switchProfile(profileId: currentProfile.id)
        }

        if let controller = extensionController {
            runtimeDiagnostics.trace(
                "attach browserManager controller=\(ExtensionRuntimeDiagnostics.objectDescription(controller)) windows=\(runtime.allWindowStates().count) tabs=\(runtime.allTabs().count)"
            )
            if let profileId = profileRuntime.currentProfileId {
                profileWebViewRuntimeReconciler.reconcile(
                    profileID: profileId,
                    reason: "ExtensionManager.attach"
                )
            }
            publishExistingRuntimeWindowsIfAttached()
        }
    }

    var hasEnabledInstalledExtensions: Bool {
        installedExtensionCollection.records.contains { $0.isEnabled }
    }

    func switchProfile(_ profile: Profile) {
        switchProfile(profileId: profile.id)
    }

    func switchProfile(profileId: UUID) {
        runtimeLifecycleOwner.switchProfile(profileId: profileId)
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionRuntimeRequestReason,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil
    ) -> WKWebExtensionController? {
        runtimeLifecycleOwner.requestExtensionRuntime(
            reason: reason,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: profileId
        )
    }

    @discardableResult
    func requestExtensionRuntimeAndWait(
        reason: ExtensionRuntimeRequestReason,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil,
        extensionId: String? = nil
    ) async -> Bool {
        await runtimeLifecycleOwner.requestExtensionRuntimeAndWait(
            reason: reason,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: profileId,
            extensionId: extensionId
        )
    }

    func enabledPersistedExtensionEntities() -> [ExtensionEntity] {
        runtimeLifecycleOwner.enabledPersistedExtensionEntities()
    }

}
