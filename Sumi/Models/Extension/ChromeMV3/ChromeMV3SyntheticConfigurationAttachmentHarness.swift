//
//  ChromeMV3SyntheticConfigurationAttachmentHarness.swift
//  Sumi
//
//  Test-only WebKit attachment mechanics harness. It creates a synthetic
//  WKWebViewConfiguration and never creates WKWebView, extension objects,
//  contexts, scripts, bundles, ports, or background work.
//

import Foundation
import WebKit

#if DEBUG
@available(macOS 15.5, *)
struct ChromeMV3SyntheticConfigurationAttachmentDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var gateDecision: ChromeMV3SyntheticConfigurationAttachmentGateDecision
    var syntheticConfigurationCreated: Bool
    var syntheticConfigurationAttached: Bool
    var realConfigurationAttached: Bool
    var attachedControllerMatchesOwner: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var attachedWebViewCount: Int
    var userScriptCount: Int
    var webExtensionCreated: Bool
    var webExtensionContextCreated: Bool
    var contextLoadCalled: Bool
    var generatedExtensionBundleLoaded: Bool
    var nativeMessagingLaunched: Bool
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var canAttachRealConfigurationNow: Bool
}

@available(macOS 15.5, *)
struct ChromeMV3SyntheticConfigurationAttachmentResult {
    var configuration: WKWebViewConfiguration?
    var diagnostics: ChromeMV3SyntheticConfigurationAttachmentDiagnostics
}

@available(macOS 15.5, *)
struct ChromeMV3SyntheticConfigurationDetachDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var hadSyntheticConfigurationAttachment: Bool
    var syntheticConfigurationAttachedAfterDetach: Bool
    var realConfigurationAttached: Bool
    var ownerTornDown: Bool
    var ownerControllerExistsAfterTeardown: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var attachedWebViewCount: Int
    var pendingContextLoads: Int
    var pendingAttachments: Int
    var generatedArtifactsDeleted: Bool
    var websiteDataCleared: Bool
    var nativeMessagingPortsCancelled: Bool
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var canAttachRealConfigurationNow: Bool
}

@available(macOS 15.5, *)
enum ChromeMV3SyntheticConfigurationAttachmentHarness {
    @MainActor
    static func attachSyntheticConfigurationIfAllowed(
        owner: ChromeMV3EmptyControllerOwner?,
        extensionsModuleEnabled: Bool,
        explicitSyntheticConfigurationAttachmentAllowed: Bool,
        surface: ChromeMV3WebViewSurface = .syntheticTestConfiguration,
        requestedContextLoading: Bool = false,
        runtimeLoadable: Bool = false,
        isRealNormalTabConfiguration: Bool = false
    ) -> ChromeMV3SyntheticConfigurationAttachmentResult {
        let controller = owner?.controller
        let ownerDiagnostics = owner?.diagnostics()
        let gateDecision = ChromeMV3SyntheticConfigurationAttachmentGate
            .evaluate(
                input: ChromeMV3SyntheticConfigurationAttachmentGateInput(
                    extensionsModuleEnabled: extensionsModuleEnabled,
                    emptyControllerExists:
                        controller != nil
                            && ownerDiagnostics?.controllerCreated == true,
                    explicitSyntheticConfigurationAttachmentAllowed:
                        explicitSyntheticConfigurationAttachmentAllowed,
                    surface: surface,
                    isRealNormalTabConfiguration:
                        isRealNormalTabConfiguration,
                    requestedContextLoading: requestedContextLoading,
                    runtimeLoadable: runtimeLoadable,
                    contextCount: controller?.extensionContexts.count
                        ?? ownerDiagnostics?.contextCount
                        ?? 0,
                    loadedExtensionCount: controller?.extensions.count
                        ?? ownerDiagnostics?.loadedExtensionCount
                        ?? 0
                )
            )

        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration =
            isRealNormalTabConfiguration

        if gateDecision.canAttachSyntheticConfigurationNow,
           let controller
        {
            configuration.webExtensionController = controller
        }

        return ChromeMV3SyntheticConfigurationAttachmentResult(
            configuration: configuration,
            diagnostics: attachmentDiagnostics(
                configuration: configuration,
                controller: controller,
                gateDecision: gateDecision
            )
        )
    }

    @MainActor
    static func detachSyntheticConfiguration(
        _ result: ChromeMV3SyntheticConfigurationAttachmentResult,
        owner: ChromeMV3EmptyControllerOwner?,
        tearDownOwner: Bool,
        trigger: ChromeMV3EmptyControllerTeardownTrigger = .explicitReset
    ) -> ChromeMV3SyntheticConfigurationDetachDiagnostics {
        let controllerBeforeDetach = owner?.controller
        let hadAttachment = configurationControllerMatches(
            result.configuration,
            controller: controllerBeforeDetach
        )

        if hadAttachment {
            result.configuration?.webExtensionController = nil
        }

        let ownerDiagnostics: ChromeMV3EmptyControllerDiagnostics?
        if tearDownOwner {
            ownerDiagnostics = owner?.tearDown(trigger: trigger)
        } else {
            ownerDiagnostics = owner?.diagnostics()
        }

        return ChromeMV3SyntheticConfigurationDetachDiagnostics(
            hadSyntheticConfigurationAttachment: hadAttachment,
            syntheticConfigurationAttachedAfterDetach:
                result.configuration?.webExtensionController != nil,
            realConfigurationAttached: false,
            ownerTornDown: tearDownOwner,
            ownerControllerExistsAfterTeardown: owner?.controller != nil,
            contextCount: ownerDiagnostics?.contextCount ?? 0,
            loadedExtensionCount: ownerDiagnostics?.loadedExtensionCount ?? 0,
            attachedWebViewCount: ownerDiagnostics?.attachedWebViewCount ?? 0,
            pendingContextLoads: ownerDiagnostics?.pendingContextLoads ?? 0,
            pendingAttachments: ownerDiagnostics?.pendingAttachments ?? 0,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false,
            nativeMessagingPortsCancelled: false,
            runtimeLoadable: false,
            canLoadContextNow: false,
            canAttachRealConfigurationNow: false
        )
    }

    @MainActor
    private static func attachmentDiagnostics(
        configuration: WKWebViewConfiguration?,
        controller: WKWebExtensionController?,
        gateDecision: ChromeMV3SyntheticConfigurationAttachmentGateDecision
    ) -> ChromeMV3SyntheticConfigurationAttachmentDiagnostics {
        ChromeMV3SyntheticConfigurationAttachmentDiagnostics(
            gateDecision: gateDecision,
            syntheticConfigurationCreated: configuration != nil,
            syntheticConfigurationAttached:
                configuration?.webExtensionController != nil,
            realConfigurationAttached: false,
            attachedControllerMatchesOwner: configurationControllerMatches(
                configuration,
                controller: controller
            ),
            contextCount: controller?.extensionContexts.count ?? 0,
            loadedExtensionCount: controller?.extensions.count ?? 0,
            attachedWebViewCount: 0,
            userScriptCount:
                configuration?.userContentController.userScripts.count ?? 0,
            webExtensionCreated: false,
            webExtensionContextCreated: false,
            contextLoadCalled: false,
            generatedExtensionBundleLoaded: false,
            nativeMessagingLaunched: false,
            runtimeLoadable: false,
            canLoadContextNow: false,
            canAttachRealConfigurationNow: false
        )
    }

    @MainActor
    private static func configurationControllerMatches(
        _ configuration: WKWebViewConfiguration?,
        controller: WKWebExtensionController?
    ) -> Bool {
        guard let attachedController = configuration?.webExtensionController,
              let controller else {
            return false
        }
        return ObjectIdentifier(attachedController) == ObjectIdentifier(controller)
    }
}
#endif
