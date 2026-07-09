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
        let profileRuntimeOwner: ExtensionProfileRuntimeOwner
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
        let runtimeInitializationTask: @MainActor () -> Task<Void, Never>?
        let cancelRuntimeInitializationTask: @MainActor () -> Void
        let ensureExtensionController: @MainActor (UUID) -> WKWebExtensionController
        let updateWebViewsForProfile: @MainActor (UUID) -> Void
        let unloadExtensionContextsForInactiveProfiles: @MainActor (UUID) -> Void
        let clearActionPopupAnchors: @MainActor (UUID) -> Void
        let reloadPinnedToolbarExtensionsForCurrentProfile: @MainActor () -> Void
        let refreshActionSurfaceStateForCurrentProfile: @MainActor () -> Void
        let extensionRuntimeReadinessContext: @MainActor (UUID) -> ExtensionRuntimeReadinessContext
        let markExtensionRuntimeReadyIfProfileContextsLoaded: @MainActor (UUID) -> Void
        let resetLoadedExtensionRuntimeStateForReload: @MainActor () -> Void
        let clearCachedWebExtensions: @MainActor () -> Void
        let clearLoadErrorsAndResidency: @MainActor () -> Void
        let countLoadedExtensionContexts: @MainActor () -> Int
        let extensionLoadGeneration: @MainActor () -> UInt64
        let installCapabilityOwner: SafariExtensionInstallCapabilityOwner
        let loadedExtensionManifests: @MainActor () -> [String: [String: Any]]
        let controllersByProfile: @MainActor () -> [UUID: WKWebExtensionController]
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
        let runtimeInitialized = dependencies.profileRuntimeOwner.activateProfile(
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
            self.dependencies.updateWebViewsForProfile(profileId)
            self.dependencies.refreshActionSurfaceStateForCurrentProfile()
        }
    }

    func prepareExtensionContextForRuntime(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        manifest: [String: Any]? = nil
    ) {
        let resolvedManifest =
            manifest
            ?? dependencies.loadedExtensionManifests()[extensionId]
            ?? extensionContext.webExtension.manifest
        dependencies.installCapabilityOwner.prepareExtensionContextForRuntime(
            extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            manifest: resolvedManifest
        )

        if dependencies.controllersByProfile()[profileId] == nil {
            _ = dependencies.ensureExtensionController(profileId)
        }
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionManager.ExtensionRuntimeRequestReason,
        forceReload: Bool = false,
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

        if dependencies.runtimeState() == .loading, forceReload == false {
            return controller
        }

        if dependencies.runtimeState() == .ready, forceReload == false {
            if let profileId = resolvedProfileId ?? dependencies.currentProfileId() {
                dependencies.updateWebViewsForProfile(profileId)
            }
            return controller
        }

        startExtensionRuntimeLoad(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: resolvedProfileId
        )
        return controller
    }

    @discardableResult
    func requestExtensionRuntimeAndWait(
        reason: ExtensionManager.ExtensionRuntimeRequestReason,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil,
        extensionId: String? = nil
    ) async -> Bool {
        let resolvedProfileId = dependencies.resolvedProfileId(profileId)

        if forceReload == false,
           let resolvedProfileId,
           dependencies.extensionRuntimeReadinessContext(resolvedProfileId)
           .canUseExistingRuntime(extensionID: extensionId) {
            dependencies.markExtensionRuntimeReadyIfProfileContextsLoaded(resolvedProfileId)
            return true
        }

        guard requestExtensionRuntime(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: resolvedProfileId
        ) != nil else {
            return false
        }

        if let runtimeInitializationTask = dependencies.runtimeInitializationTask() {
            await runtimeInitializationTask.value
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
            ?? dependencies.profileRuntimeOwner.currentProfile(in: dependencies.runtime())?.id
            ?? UUID()
        let controller = dependencies.ensureExtensionController(profileId)
        dependencies.trace(
            "runtime controller initialized reason=\(reason.rawValue) profile=\(profileId.uuidString) controller=\(dependencies.extensionControllerDescription(controller))"
        )
        return controller
    }

    private func startExtensionRuntimeLoad(
        reason: ExtensionManager.ExtensionRuntimeRequestReason,
        forceReload: Bool,
        allowWithoutEnabledExtensions: Bool,
        profileId: UUID?
    ) {
        dependencies.cancelRuntimeInitializationTask()

        let resolvedProfileId = dependencies.resolvedProfileId(profileId)

        if forceReload {
            dependencies.resetLoadedExtensionRuntimeStateForReload()
            dependencies.clearCachedWebExtensions()
            dependencies.clearLoadErrorsAndResidency()
        }

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
            "lazyRuntime controller-only reason=\(reason.rawValue) profileId=\(resolvedProfileId.uuidString) loadedContexts=\(dependencies.countLoadedExtensionContexts()) forceReload=\(forceReload)"
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

    func validateExpectedExtensionLoadGeneration(_ expectedGeneration: UInt64?) throws {
        guard let expectedGeneration else { return }
        guard dependencies.extensionLoadGeneration() == expectedGeneration else {
            throw CancellationError()
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionRuntimeLifecycleOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            modelContext: manager.context,
            profileRuntimeOwner: manager.profileRuntimeOwner,
            browserConfiguration: manager.browserConfiguration,
            runtime: { [weak manager] in manager?.runtime ?? .inactive },
            isExtensionSupportAvailable: { [weak manager] in
                manager?.isExtensionSupportAvailable ?? false
            },
            hasEnabledInstalledExtensions: { [weak manager] in
                manager?.hasEnabledInstalledExtensions ?? false
            },
            currentProfileId: { [weak manager] in manager?.currentProfileId },
            resolvedProfileId: { [weak manager] explicitProfileId in
                manager?.resolvedProfileId(explicitProfileId: explicitProfileId)
            },
            runtimeState: { [weak manager] in manager?.runtimeState ?? .idle },
            setRuntimeState: { [weak manager] state in manager?.runtimeState = state },
            setExtensionsLoaded: { [weak manager] loaded in
                manager?.extensionsLoaded = loaded
            },
            setAllowsRuntimeWithoutEnabledExtensions: { [weak manager] allows in
                manager?.allowsRuntimeWithoutEnabledExtensions = allows
            },
            runtimeInitializationTask: { [weak manager] in
                manager?.runtimeInitializationTask
            },
            cancelRuntimeInitializationTask: { [weak manager] in
                manager?.runtimeInitializationTask?.cancel()
                manager?.runtimeInitializationTask = nil
            },
            ensureExtensionController: { [weak manager] profileId in
                guard let manager else {
                    preconditionFailure("ExtensionManager dependency used after deallocation")
                }
                return manager.ensureExtensionController(for: profileId)
            },
            updateWebViewsForProfile: { [weak manager] profileId in
                manager?.updateWebViewsForProfile(profileId)
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
            resetLoadedExtensionRuntimeStateForReload: { [weak manager] in
                manager?.resetLoadedExtensionRuntimeStateForReload()
            },
            clearCachedWebExtensions: { [weak manager] in
                manager?.cachedWebExtensionsByID.removeAll()
                manager?.cachedWebExtensionRuntimeSourceKeysByID.removeAll()
            },
            clearLoadErrorsAndResidency: { [weak manager] in
                manager?.lastExtensionLoadErrors.removeAll()
                manager?.extensionRuntimeResidencyState.removeAll()
            },
            countLoadedExtensionContexts: { [weak manager] in
                manager?.countLoadedExtensionContexts() ?? 0
            },
            extensionLoadGeneration: { [weak manager] in
                manager?.extensionLoadGeneration ?? 0
            },
            installCapabilityOwner: manager.installCapabilityOwner,
            loadedExtensionManifests: { [weak manager] in
                manager?.loadedExtensionManifests ?? [:]
            },
            controllersByProfile: { [weak manager] in
                manager?.extensionControllersByProfile ?? [:]
            },
            extensionControllerDescription: { [weak manager] controller in
                manager?.extensionRuntimeControllerDescription(controller) ?? "nil"
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message)
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func attach(browserManager: BrowserManager) {
        browserBridgeContext = browserManager.extensionBridgeBundle.adapter
        runtime = BrowserExtensionManagerRuntimeFactory.runtime(for: browserManager)

        if runtime.activeWindowState() == nil,
           let currentProfile = runtime.currentProfile() {
            switchProfile(profileId: currentProfile.id)
        }

        if let controller = extensionController {
            extensionRuntimeTrace(
                "attach browserManager controller=\(extensionRuntimeControllerDescription(controller)) windows=\(runtime.allWindowStates().count) tabs=\(runtime.allTabs().count)"
            )
            if let profileId = currentProfileId {
                updateWebViewsForProfile(profileId)
            }
            registerExistingWindowStateIfAttached()
        }
    }

    var hasEnabledInstalledExtensions: Bool {
        installedExtensions.contains { $0.isEnabled }
    }

    func switchProfile(_ profile: Profile) {
        switchProfile(profileId: profile.id)
    }

    func switchProfile(profileId: UUID) {
        runtimeLifecycleOwner.switchProfile(profileId: profileId)
    }

    func prepareExtensionContextForRuntime(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        manifest: [String: Any]? = nil
    ) {
        runtimeLifecycleOwner.prepareExtensionContextForRuntime(
            extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            manifest: manifest
        )
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionRuntimeRequestReason,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil
    ) -> WKWebExtensionController? {
        runtimeLifecycleOwner.requestExtensionRuntime(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: profileId
        )
    }

    @discardableResult
    func requestExtensionRuntimeAndWait(
        reason: ExtensionRuntimeRequestReason,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil,
        extensionId: String? = nil
    ) async -> Bool {
        await runtimeLifecycleOwner.requestExtensionRuntimeAndWait(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: profileId,
            extensionId: extensionId
        )
    }

    func enabledPersistedExtensionEntities() -> [ExtensionEntity] {
        runtimeLifecycleOwner.enabledPersistedExtensionEntities()
    }

    func validateExpectedExtensionLoadGeneration(_ expectedGeneration: UInt64?) throws {
        try runtimeLifecycleOwner.validateExpectedExtensionLoadGeneration(expectedGeneration)
    }
}
