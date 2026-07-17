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
protocol ExtensionControllerProvisioning: AnyObject {
    func controllerIfAdmitted(
        for profileID: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWebViewConfigurationProvisioning: AnyObject {
    func controllerIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController?
    func websiteDataStoreIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebsiteDataStore?
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionControllerProvisioningOwner {
    func controllerIfAdmitted(
        for profileID: UUID
    ) -> WKWebExtensionController? {
        controllerIfAdmitted(for: profileID, mutationLease: nil)
    }

    func websiteDataStoreIfAdmitted(
        for profileID: UUID
    ) -> WKWebsiteDataStore? {
        websiteDataStoreIfAdmitted(for: profileID, mutationLease: nil)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerProvisioningOwner:
    ExtensionWebViewConfigurationProvisioning,
    ExtensionControllerProvisioning {
    struct Dependencies {
        let browserConfiguration: BrowserConfiguration
        let profileRuntime: ExtensionProfileRuntime
        let currentProfileId: @MainActor () -> UUID?
        let assignControllerDelegate: @MainActor (WKWebExtensionController) -> Void
        let controllerDelegateReadiness:
            ExtensionControllerDelegateReadiness
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

    nonisolated static func persistentControllerIdentifier(
        for profileId: UUID
    ) -> UUID {
        var uuid = profileId.uuid
        uuid.15 ^= 0xA5
        return UUID(uuid: uuid)
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
        return persistentControllerIdentifier(for: profileId)
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
    func controllerIfAdmitted(
        for profileId: UUID,
        mutationLease suppliedLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController? {
        let mutationLease: ProfileReferenceMutationLease
        let ownsMutationLease: Bool
        if let suppliedLease {
            mutationLease = suppliedLease
            ownsMutationLease = false
        } else {
            guard let acquired = dependencies.profileRuntime
                .beginProfileReferenceMutation(to: profileId)
            else { return nil }
            mutationLease = acquired
            ownsMutationLease = true
        }
        defer {
            if ownsMutationLease {
                _ = dependencies.profileRuntime.endProfileReferenceMutation(
                    mutationLease
                )
            }
        }
        guard dependencies.profileRuntime.validateProfileReferenceMutation(
            mutationLease,
            profileID: profileId
        ) else { return nil }
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

        guard let defaultDataStore = websiteDataStoreIfAdmitted(
            for: profileId,
            mutationLease: mutationLease
        ) else { return nil }
        let controller = makeExtensionController(
            defaultDataStore: defaultDataStore,
            profileId: profileId
        )
        guard let controllerBinding = dependencies.profileRuntime
            .publishControllerIfAdmitted(
            controller,
            for: profileId,
            mutationLease: mutationLease
        ) else { return nil }
        dependencies.controllerDelegateReadiness.controllerInstalled(
            controllerBinding
        )

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

    func websiteDataStoreIfAdmitted(
        for profileId: UUID,
        mutationLease suppliedLease: ProfileReferenceMutationLease?
    ) -> WKWebsiteDataStore? {
        let mutationLease: ProfileReferenceMutationLease
        let ownsMutationLease: Bool
        if let suppliedLease {
            mutationLease = suppliedLease
            ownsMutationLease = false
        } else {
            guard let acquired = dependencies.profileRuntime
                .beginProfileReferenceMutation(to: profileId)
            else { return nil }
            mutationLease = acquired
            ownsMutationLease = true
        }
        defer {
            if ownsMutationLease {
                _ = dependencies.profileRuntime.endProfileReferenceMutation(
                    mutationLease
                )
            }
        }
        return dependencies.profileRuntime.websiteDataStoreIfAdmitted(
            for: profileId,
            mutationLease: mutationLease
        )
    }

    #if DEBUG
        func ensureExtensionController(
            for profileId: UUID
        ) -> WKWebExtensionController {
            guard let controller = controllerIfAdmitted(for: profileId) else {
                preconditionFailure("Test provisioned a blocked profile controller")
            }
            return controller
        }

        func websiteDataStore(for profileId: UUID) -> WKWebsiteDataStore {
            guard let store = websiteDataStoreIfAdmitted(for: profileId) else {
                preconditionFailure("Test requested a blocked profile data store")
            }
            return store
        }
    #endif

    func removeAllExtensionPageUserContentControllers() {
        extensionPageUserContentControllersByProfile.removeAll()
    }

    func retireProfileController(
        profileID: UUID,
        fallbackProfileID: UUID
    ) {
        let retiredController = dependencies.profileRuntime.controller(
            for: profileID
        )
        extensionPageUserContentControllersByProfile.removeValue(
            forKey: profileID
        )
        let runtimeConfiguration = dependencies.browserConfiguration
            .webViewConfiguration
        if runtimeConfiguration.webExtensionController === retiredController {
            runtimeConfiguration.webExtensionController = dependencies
                .profileRuntime.controller(for: fallbackProfileID)
        }
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        extensionPageUserContentControllersByProfile[profileID] != nil
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
