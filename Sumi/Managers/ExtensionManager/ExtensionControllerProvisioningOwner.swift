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
final class ExtensionControllerProvisioningOwner {
    struct Dependencies {
        let browserConfiguration: BrowserConfiguration
        let profileRuntimeOwner: ExtensionProfileRuntimeOwner
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let currentProfileId: @MainActor () -> UUID?
        let assignControllerDelegate: @MainActor (WKWebExtensionController) -> Void
        let isControllerRegistered: @MainActor (WKWebExtensionController) -> Bool
        let profileIdForController: @MainActor (WKWebExtensionController) -> UUID?
        let updateWebViewsForProfile: @MainActor (UUID) -> Void
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
        var uuid = profileId.uuid
        uuid.15 ^= 0xA5
        return UUID(uuid: uuid)
    }

    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        if let existing = dependencies.profileRuntimeOwner.controller(for: profileId) {
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
        dependencies.profileRuntimeOwner.setController(controller, for: profileId)
        scheduleControllerDelegateRebind(for: controller)

        if dependencies.currentProfileId() == profileId {
            dependencies.browserConfiguration.webViewConfiguration.webExtensionController =
                controller
        }

        dependencies.trace {
            "ensureExtensionController profile=\(profileId.uuidString) controller=\(self.dependencies.controllerDescription(controller))"
        }
        dependencies.updateWebViewsForProfile(profileId)
        verifyExtensionStorage(profileId: profileId)
        return controller
    }

    func websiteDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        dependencies.profileRuntimeOwner.websiteDataStore(
            for: profileId,
            runtime: dependencies.runtime()
        )
    }

    func canLateBindExtensionController(to webView: WKWebView) -> Bool {
        webView.configuration.webExtensionController == nil
            && ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                currentURL: webView.url
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
        guard let dataStore = dependencies.profileRuntimeOwner.controller(for: profileId)?
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
            profileRuntimeOwner: manager.profileRuntimeOwner,
            runtime: { [weak manager] in
                manager?.runtime ?? .inactive
            },
            currentProfileId: { [weak manager] in
                manager?.currentProfileId
            },
            assignControllerDelegate: { [weak manager] controller in
                controller.delegate = manager
            },
            isControllerRegistered: { [weak manager] controller in
                manager?.extensionControllersByProfile.values.contains {
                    $0 === controller
                } ?? false
            },
            profileIdForController: { [weak manager] controller in
                manager?.profileId(for: controller)
            },
            updateWebViewsForProfile: { [weak manager] profileId in
                manager?.updateWebViewsForProfile(profileId)
            },
            traceControllerBinding: { [weak manager] phase, profileId, controller, configuration in
                manager?.traceNativeMessagingContextBinding(
                    phase: phase,
                    extensionId: nil,
                    profileId: profileId,
                    controller: controller,
                    configuration: configuration
                )
            },
            controllerDescription: { [weak manager] controller in
                manager?.extensionRuntimeControllerDescription(controller) ?? "nil"
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
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

    func canLateBindExtensionController(to webView: WKWebView) -> Bool {
        controllerProvisioningOwner.canLateBindExtensionController(to: webView)
    }

    func extensionControllerIdentifier(for profileId: UUID) -> UUID {
        ExtensionControllerProvisioningOwner.extensionControllerIdentifier(for: profileId)
    }
}
