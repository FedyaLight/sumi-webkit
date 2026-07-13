//
//  ExtensionControllerProvisioningOwner.swift
//  Sumi
//
//  Owns per-profile WKWebExtensionController provisioning: controller and
//  extension-page configuration construction, delegate (re)binding, website
//  data store resolution, and storage verification.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWebViewConfigurationProvisioning: AnyObject {
    func ensureExtensionController(
        for profileId: UUID
    ) -> WKWebExtensionController
    func websiteDataStore(for profileId: UUID) -> WKWebsiteDataStore
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerProvisioningOwner:
    ExtensionWebViewConfigurationProvisioning {
    struct Dependencies {
        let browserConfiguration: BrowserConfiguration
        let profileRuntime: ExtensionProfileRuntime
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let currentProfileId: @MainActor () -> UUID?
        let assignControllerDelegate: @MainActor (WKWebExtensionController) -> Void
        let isControllerRegistered: @MainActor (WKWebExtensionController) -> Bool
        let profileIdForController: @MainActor (WKWebExtensionController) -> UUID?
        let traceControllerBinding:
            @MainActor (String, UUID?, WKWebExtensionController, WKWebViewConfiguration?) -> Void
        let controllerDescription: @MainActor (WKWebExtensionController?) -> String
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies
    private var extensionPageUserContentControllersByProfile:
        [UUID: WKUserContentController] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    static func extensionControllerIdentifier(for profileId: UUID) -> UUID {
        #if DEBUG
            // Test processes are hosted inside Sumi.app and share the real
            // WebKit storage root with the user's running browser. Never hand
            // a test the production (profile-derived) controller identifier —
            // a test that loads a real profile would otherwise operate on,
            // and clean up, the user's live extension storage.
            if RuntimeDiagnostics.isRunningTests {
                return testScopedControllerIdentifier(for: profileId)
            }
        #endif
        var uuid = profileId.uuid
        uuid.15 ^= 0xA5
        return UUID(uuid: uuid)
    }

    #if DEBUG
        @MainActor
        private static var testScopedControllerIdentifiersByProfile: [UUID: UUID] = [:]

        /// Process-stable random controller identifier per profile for test
        /// runs, registered for cross-process storage cleanup once the test
        /// process exits.
        @MainActor
        private static func testScopedControllerIdentifier(for profileId: UUID) -> UUID {
            if let existing = testScopedControllerIdentifiersByProfile[profileId] {
                return existing
            }
            let identifier = UUID()
            testScopedControllerIdentifiersByProfile[profileId] = identifier
            ExtensionControllerIdentifierOwner.registerTestControllerIdentifierIfRunningTests(
                identifier
            )
            return identifier
        }
    #endif

    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        if let existing = dependencies.profileRuntime.controller(for: profileId) {
            return existing
        }

        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.setupExtensionController"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.setupExtensionController",
                signpostState
            )
        }

        let defaultDataStore = websiteDataStore(for: profileId)
        let controller = makeExtensionController(
            defaultDataStore: defaultDataStore,
            profileId: profileId
        )
        dependencies.profileRuntime.setController(controller, for: profileId)
        scheduleControllerDelegateRebind(for: controller)

        if dependencies.currentProfileId() == profileId {
            dependencies.browserConfiguration.webViewConfiguration.webExtensionController =
                controller
        }

        dependencies.trace {
            "ensureExtensionController profile=\(profileId.uuidString) controller=\(self.dependencies.controllerDescription(controller))"
        }
        verifyExtensionStorage(profileId: profileId)
        return controller
    }

    func websiteDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        dependencies.profileRuntime.websiteDataStore(
            for: profileId,
            runtime: dependencies.runtime()
        )
    }

    func removeAllExtensionPageUserContentControllers() {
        extensionPageUserContentControllersByProfile.removeAll()
    }

    var hasExtensionPageUserContentControllers: Bool {
        extensionPageUserContentControllersByProfile.isEmpty == false
    }

    private func makeExtensionController(
        defaultDataStore: WKWebsiteDataStore,
        profileId: UUID
    ) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(
            identifier: Self.extensionControllerIdentifier(for: profileId)
        )
        let runtimeWebConfiguration = dependencies.browserConfiguration.webViewConfiguration
        let extensionPageConfiguration =
            makeExtensionPageBaseWebViewConfiguration(
                from: runtimeWebConfiguration,
                websiteDataStore: defaultDataStore
            )
        extensionPageUserContentControllersByProfile[profileId] =
            extensionPageConfiguration.userContentController
        configuration.webViewConfiguration = extensionPageConfiguration
        configuration.defaultWebsiteDataStore = defaultDataStore

        let controller = WKWebExtensionController(configuration: configuration)
        dependencies.assignControllerDelegate(controller)
        dependencies.traceControllerBinding(
            "controllerCreated",
            profileId,
            controller,
            extensionPageConfiguration
        )

        if dependencies.currentProfileId() == profileId {
            runtimeWebConfiguration.webExtensionController = controller
        }
        runtimeWebConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true

        return controller
    }

    private func makeExtensionPageBaseWebViewConfiguration(
        from source: WKWebViewConfiguration,
        websiteDataStore: WKWebsiteDataStore
    ) -> WKWebViewConfiguration {
        let configuration = dependencies.browserConfiguration.auxiliaryWebViewConfiguration(
            from: source,
            surface: .extensionOptions
        )
        configuration.websiteDataStore = websiteDataStore
        configuration.sumiIsNormalTabWebViewConfiguration = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        return configuration
    }

    private func scheduleControllerDelegateRebind(
        for controller: WKWebExtensionController
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak controller] in
            guard let self, let controller else { return }
            guard dependencies.isControllerRegistered(controller) else {
                return
            }
            dependencies.assignControllerDelegate(controller)
            dependencies.traceControllerBinding(
                "delegateRebound",
                dependencies.profileIdForController(controller),
                controller,
                nil
            )
        }
    }

    private func verifyExtensionStorage(profileId: UUID) {
        guard RuntimeDiagnostics.isVerboseEnabled else {
            return
        }
        guard let dataStore = dependencies.profileRuntime.controller(for: profileId)?
            .configuration.defaultWebsiteDataStore
        else {
            return
        }
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            ExtensionManager.logger.debug("Extension data store ready for profile \(profileId.uuidString, privacy: .public): \(records.count) records")
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionControllerProvisioningOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            browserConfiguration: manager.browserConfiguration,
            profileRuntime: manager.profileRuntime,
            runtime: { [weak manager] in
                manager?.runtime ?? .inactive
            },
            currentProfileId: { [weak manager] in
                manager?.profileRuntime.currentProfileId
            },
            assignControllerDelegate: { [weak manager] controller in
                controller.delegate = manager?.controllerDelegateBridge
            },
            isControllerRegistered: { [weak manager] controller in
                manager?.profileRuntime.controllersByProfile.values.contains {
                    $0 === controller
                } ?? false
            },
            profileIdForController: { [weak manager] controller in
                manager?.profileId(for: controller)
            },
            traceControllerBinding: { [weak manager] phase, profileId, controller, configuration in
                manager?.runtimeDiagnostics.traceNativeMessagingContextBinding(
                    phase: phase,
                    extensionId: nil,
                    profileId: profileId,
                    controller: controller,
                    configuration: configuration,
                    manager: manager
                )
            },
            controllerDescription: { controller in
                ExtensionRuntimeDiagnostics.objectDescription(controller)
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message())
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        controllerProvisioningOwner.ensureExtensionController(for: profileId)
    }

    func getExtensionDataStore(
        for profileId: UUID
    ) -> WKWebsiteDataStore {
        controllerProvisioningOwner.websiteDataStore(for: profileId)
    }

    func extensionControllerIdentifier(for profileId: UUID) -> UUID {
        ExtensionControllerProvisioningOwner.extensionControllerIdentifier(for: profileId)
    }
}
