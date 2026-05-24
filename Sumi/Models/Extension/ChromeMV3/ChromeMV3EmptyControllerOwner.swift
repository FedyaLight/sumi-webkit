//
//  ChromeMV3EmptyControllerOwner.swift
//  Sumi
//
//  Owns a gated, empty WKWebExtensionController for an enabled Chrome MV3
//  profile host. It does not load resources, contexts, scripts, ports, or
//  attach the controller to browsing WebViews.
//

import Foundation
import WebKit

enum ChromeMV3EmptyControllerOwnerState: String, Codable, Sendable {
    case notCreated
    case createdEmpty
    case tornDown
}

struct ChromeMV3EmptyControllerDiagnostics: Codable, Equatable, Sendable {
    var profileIdentifier: String
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var dataStoreIdentityPolicy:
        ChromeMV3ControllerDataStoreIdentityDiagnostics
    var controllerState: ChromeMV3EmptyControllerOwnerState
    var controllerCreated: Bool
    var gateDecision: ChromeMV3ControllerCreationGateDecision
    var teardownPolicy: ChromeMV3EmptyControllerTeardownPolicy?
    var contextCount: Int
    var loadedExtensionCount: Int
    var attachedWebViewCount: Int
    var nativeMessagingPortCount: Int
    var pendingContextLoads: Int
    var pendingAttachments: Int
    var configurationWebViewHasControllerAttachment: Bool
    var configurationWebViewUserScriptCount: Int
    var registersUserScriptsNow: Bool
    var launchesNativeMessagingNow: Bool
    var startsBackgroundWorkNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
    var runtimeLoadable: Bool
    var blockingReasons: [String]

    static func notCreated(
        gateDecision: ChromeMV3ControllerCreationGateDecision
    ) -> ChromeMV3EmptyControllerDiagnostics {
        ChromeMV3EmptyControllerDiagnostics(
            profileIdentifier: gateDecision.input.profileIdentifier,
            profileDataStoreIdentity: gateDecision.input.profileDataStoreIdentity,
            dataStoreIdentityPolicy:
                ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
                    profileIdentifier: gateDecision.input.profileIdentifier,
                    dataStoreIdentity: gateDecision.input.profileDataStoreIdentity,
                    controllerCreated: false
                ),
            controllerState: .notCreated,
            controllerCreated: false,
            gateDecision: gateDecision,
            teardownPolicy: nil,
            contextCount: 0,
            loadedExtensionCount: 0,
            attachedWebViewCount: 0,
            nativeMessagingPortCount: 0,
            pendingContextLoads: 0,
            pendingAttachments: 0,
            configurationWebViewHasControllerAttachment: false,
            configurationWebViewUserScriptCount: 0,
            registersUserScriptsNow: false,
            launchesNativeMessagingNow: false,
            startsBackgroundWorkNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            runtimeLoadable: false,
            blockingReasons: gateDecision.blockingReasons
        )
    }
}

@available(macOS 15.5, *)
final class ChromeMV3EmptyControllerOwner {
    private let gateDecision: ChromeMV3ControllerCreationGateDecision
    private let defaultWebsiteDataStore: WKWebsiteDataStore
    private let controllerIdentifier: UUID
    private var controllerStorage: WKWebExtensionController?
    private var normalTabConfigurationAttachmentRecords:
        [ChromeMV3NormalTabConfigurationAttachmentRecord] = []
    private var lastTeardownPolicy: ChromeMV3EmptyControllerTeardownPolicy?
    private(set) var state: ChromeMV3EmptyControllerOwnerState = .notCreated

    @MainActor
    init(
        gateDecision: ChromeMV3ControllerCreationGateDecision,
        defaultWebsiteDataStore: WKWebsiteDataStore,
        controllerIdentifier: UUID
    ) {
        self.gateDecision = gateDecision
        self.defaultWebsiteDataStore = defaultWebsiteDataStore
        self.controllerIdentifier = controllerIdentifier
    }

    @MainActor
    var controller: WKWebExtensionController? {
        controllerStorage
    }

    @discardableResult
    @MainActor
    func createControllerIfAllowed() -> WKWebExtensionController? {
        guard gateDecision.canCreateControllerNow else {
            state = .notCreated
            return nil
        }

        if let controllerStorage {
            return controllerStorage
        }

        let configuration = makeConfiguration()
        let controller = WKWebExtensionController(configuration: configuration)
        controllerStorage = controller
        state = .createdEmpty
        lastTeardownPolicy = nil
        return controller
    }

    @MainActor
    @discardableResult
    func tearDown(
        trigger: ChromeMV3EmptyControllerTeardownTrigger = .explicitReset
    ) -> ChromeMV3EmptyControllerDiagnostics {
        lastTeardownPolicy =
            ChromeMV3EmptyControllerTeardownPolicyEvaluator.evaluate(
                trigger: trigger,
                controllerCreated: controllerStorage != nil
            )
        ChromeMV3NormalTabConfigurationAttachmentBridge
            .detachTrackedConfigurations(
                records: &normalTabConfigurationAttachmentRecords,
                controller: controllerStorage
            )
        controllerStorage?.delegate = nil
        controllerStorage = nil
        state = .tornDown
        return diagnostics()
    }

    @MainActor
    func recordNormalTabConfigurationAttachment(
        _ configuration: WKWebViewConfiguration
    ) {
        ChromeMV3NormalTabConfigurationAttachmentBridge.record(
            configuration: configuration,
            records: &normalTabConfigurationAttachmentRecords
        )
    }

    @MainActor
    func diagnostics() -> ChromeMV3EmptyControllerDiagnostics {
        guard let controllerStorage else {
            return ChromeMV3EmptyControllerDiagnostics(
                profileIdentifier: gateDecision.input.profileIdentifier,
                profileDataStoreIdentity: gateDecision.input.profileDataStoreIdentity,
                dataStoreIdentityPolicy: dataStoreIdentityPolicy(
                    controllerCreated: false
                ),
                controllerState: state,
                controllerCreated: false,
                gateDecision: gateDecision,
                teardownPolicy: lastTeardownPolicy,
                contextCount: 0,
                loadedExtensionCount: 0,
                attachedWebViewCount: 0,
                nativeMessagingPortCount: 0,
                pendingContextLoads: 0,
                pendingAttachments: 0,
                configurationWebViewHasControllerAttachment: false,
                configurationWebViewUserScriptCount: 0,
                registersUserScriptsNow: false,
                launchesNativeMessagingNow: false,
                startsBackgroundWorkNow: false,
                canLoadContextNow: false,
                canAttachToNormalTabsNow: false,
                runtimeLoadable: false,
                blockingReasons: gateDecision.blockingReasons
            )
        }

        let configurationWebView = controllerStorage.configuration
            .webViewConfiguration

        return ChromeMV3EmptyControllerDiagnostics(
            profileIdentifier: gateDecision.input.profileIdentifier,
            profileDataStoreIdentity: gateDecision.input.profileDataStoreIdentity,
            dataStoreIdentityPolicy: dataStoreIdentityPolicy(
                controllerCreated: true
            ),
            controllerState: state,
            controllerCreated: true,
            gateDecision: gateDecision,
            teardownPolicy: lastTeardownPolicy,
            contextCount: controllerStorage.extensionContexts.count,
            loadedExtensionCount: controllerStorage.extensions.count,
            attachedWebViewCount: 0,
            nativeMessagingPortCount: 0,
            pendingContextLoads: 0,
            pendingAttachments: 0,
            configurationWebViewHasControllerAttachment: configurationWebView?
                .webExtensionController != nil,
            configurationWebViewUserScriptCount: configurationWebView?
                .userContentController.userScripts.count ?? 0,
            registersUserScriptsNow: false,
            launchesNativeMessagingNow: false,
            startsBackgroundWorkNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            runtimeLoadable: false,
            blockingReasons: gateDecision.blockingReasons
        )
    }

    private func dataStoreIdentityPolicy(
        controllerCreated: Bool
    ) -> ChromeMV3ControllerDataStoreIdentityDiagnostics {
        ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
            profileIdentifier: gateDecision.input.profileIdentifier,
            dataStoreIdentity: gateDecision.input.profileDataStoreIdentity,
            controllerConfigurationIdentifier: controllerIdentifier.uuidString,
            controllerCreated: controllerCreated
        )
    }

    @MainActor
    private func makeConfiguration() -> WKWebExtensionController.Configuration {
        let configuration: WKWebExtensionController.Configuration
        switch gateDecision.input.profileDataStoreIdentity {
        case .ephemeralProfileIdentifier:
            configuration = WKWebExtensionController.Configuration.nonPersistent()
        case .profileIdentifier, .placeholder, .unresolved:
            configuration = WKWebExtensionController.Configuration(
                identifier: controllerIdentifier
            )
        }

        let webViewConfiguration = WKWebViewConfiguration()
        configuration.webViewConfiguration = webViewConfiguration
        configuration.defaultWebsiteDataStore = defaultWebsiteDataStore
        return configuration
    }
}

@available(macOS 15.5, *)
enum ChromeMV3EmptyControllerFactory {
    @MainActor
    static func makeOwner(
        gateDecision: ChromeMV3ControllerCreationGateDecision,
        defaultWebsiteDataStore: WKWebsiteDataStore,
        controllerIdentifier: UUID
    ) -> ChromeMV3EmptyControllerOwner? {
        guard gateDecision.canCreateControllerNow else {
            return nil
        }

        let owner = ChromeMV3EmptyControllerOwner(
            gateDecision: gateDecision,
            defaultWebsiteDataStore: defaultWebsiteDataStore,
            controllerIdentifier: controllerIdentifier
        )
        owner.createControllerIfAllowed()
        return owner
    }
}
