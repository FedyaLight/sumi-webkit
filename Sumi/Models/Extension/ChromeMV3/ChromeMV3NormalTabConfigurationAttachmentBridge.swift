//
//  ChromeMV3NormalTabConfigurationAttachmentBridge.swift
//  Sumi
//
//  DEBUG/internal bridge for attaching the empty Chrome MV3 controller to
//  real normal-tab WKWebViewConfiguration objects only. This file performs
//  configuration assignment; it does not create WebViews, extension objects,
//  contexts, scripts, bundles, ports, or background work.
//

import Foundation
import ObjectiveC.runtime
import WebKit

@available(macOS 15.5, *)
struct ChromeMV3NormalTabConfigurationAttachmentRequest {
    var owner: ChromeMV3EmptyControllerOwner?
    var extensionsModuleEnabled: Bool
    var profileHostEnabled: Bool
    var explicitInternalNormalTabAttachmentAllowed: Bool
    var surface: ChromeMV3WebViewSurface
    var requestedContextLoading: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var attemptMetadata:
        ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata

    var emptyControllerOwnerPresent: Bool {
        owner != nil
    }

    var targetSurface: ChromeMV3WebViewSurface {
        surface
    }

    var targetIsLiveNormalTab: Bool {
        surface == .normalTab
    }

    var targetIsPinnedEssentialsLiveNormalBrowsing: Bool {
        surface == .pinnedEssentialsLiveNormalBrowsing
    }

    var targetIsLauncherMetadata: Bool {
        surface == .pinnedEssentialsLauncherMetadata
    }

    var targetIsPreviewHelperMiniFaviconDownloadAuxiliary: Bool {
        surface.isAuxiliaryOrHelperSurfaceForChromeMV3Attachment
            || surface.isExtensionOwnedProductionSurfaceForChromeMV3Attachment
    }

    init(
        owner: ChromeMV3EmptyControllerOwner?,
        extensionsModuleEnabled: Bool,
        profileHostEnabled: Bool,
        explicitInternalNormalTabAttachmentAllowed: Bool,
        surface: ChromeMV3WebViewSurface = .normalTab,
        requestedContextLoading: Bool = false,
        canLoadContextNow: Bool = false,
        runtimeLoadable: Bool = false,
        attemptMetadata:
            ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata =
                ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata()
    ) {
        self.owner = owner
        self.extensionsModuleEnabled = extensionsModuleEnabled
        self.profileHostEnabled = profileHostEnabled
        self.explicitInternalNormalTabAttachmentAllowed =
            explicitInternalNormalTabAttachmentAllowed
        self.surface = surface
        self.requestedContextLoading = requestedContextLoading
        self.canLoadContextNow = canLoadContextNow
        self.runtimeLoadable = runtimeLoadable
        self.attemptMetadata = attemptMetadata
    }
}

@available(macOS 15.5, *)
struct ChromeMV3NormalTabConfigurationAttachmentDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var gateDecision: ChromeMV3NormalTabConfigurationAttachmentGateDecision
    var attachmentRequested: Bool
    var tabIdentifier: String?
    var tabDiagnosticIdentifier: String?
    var windowIdentifier: String?
    var profileIdentifier: String?
    var creationReason: String
    var targetSurface: ChromeMV3WebViewSurface
    var emptyControllerOwnerPresent: Bool
    var explicitInternalNormalTabAttachmentAllowed: Bool
    var normalTabConfigurationCreated: Bool
    var normalTabConfigurationAttached: Bool
    var auxiliaryConfigurationAttached: Bool
    var attachedControllerMatchesOwner: Bool
    var attachedControllerIdentity: String?
    var contextCount: Int
    var loadedExtensionCount: Int
    var attachedWebViewCount: Int
    var userScriptCount: Int
    var userScriptRegistrationCount: Int
    var webExtensionCreated: Bool
    var webExtensionContextCreated: Bool
    var contextLoadCalled: Bool
    var generatedExtensionBundleLoaded: Bool
    var nativeMessagingLaunched: Bool
    var nativeMessagingPortCount: Int
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var canAttachNormalTabConfigurationNow: Bool
    var canAttachAuxiliaryConfigurationNow: Bool
}

@available(macOS 15.5, *)
struct ChromeMV3NormalTabConfigurationAttachmentResult {
    var configuration: WKWebViewConfiguration
    var diagnostics: ChromeMV3NormalTabConfigurationAttachmentDiagnostics
}

@available(macOS 15.5, *)
final class ChromeMV3NormalTabConfigurationAttachmentRecord {
    weak var configuration: WKWebViewConfiguration?
    let sequenceNumber: Int

    init(
        configuration: WKWebViewConfiguration,
        sequenceNumber: Int
    ) {
        self.configuration = configuration
        self.sequenceNumber = sequenceNumber
    }
}

@available(macOS 15.5, *)
enum ChromeMV3NormalTabConfigurationAttachmentBridge {
    @MainActor
    static func attachIfAllowed(
        configuration: WKWebViewConfiguration,
        request: ChromeMV3NormalTabConfigurationAttachmentRequest?
    ) -> ChromeMV3NormalTabConfigurationAttachmentDiagnostics {
        let controller = request?.owner?.controller
        let gateDecision = evaluateGate(
            configuration: configuration,
            request: request,
            controller: controller
        )

        if gateDecision.canAttachNormalTabConfigurationNow,
           let controller
        {
            configuration.webExtensionController = controller
            configuration.sumiHasChromeMV3NormalTabConfigurationAttachment = true
        }

        let diagnostics = diagnostics(
            configuration: configuration,
            request: request,
            controller: controller,
            gateDecision: gateDecision
        )
        request?.owner?.recordNormalTabConfigurationAttachmentDecision(
            configuration,
            diagnostics: diagnostics
        )
        return diagnostics
    }

    @MainActor
    static func inspect(
        configuration: WKWebViewConfiguration,
        request: ChromeMV3NormalTabConfigurationAttachmentRequest?
    ) -> ChromeMV3NormalTabConfigurationAttachmentDiagnostics {
        let controller = request?.owner?.controller
        let gateDecision = evaluateGate(
            configuration: configuration,
            request: request,
            controller: controller
        )
        return diagnostics(
            configuration: configuration,
            request: request,
            controller: controller,
            gateDecision: gateDecision
        )
    }

    @MainActor
    static func record(
        configuration: WKWebViewConfiguration,
        sequenceNumber: Int,
        records: inout [ChromeMV3NormalTabConfigurationAttachmentRecord]
    ) {
        prune(records: &records)
        guard records.contains(where: { $0.configuration === configuration }) == false else {
            return
        }
        records.append(
            ChromeMV3NormalTabConfigurationAttachmentRecord(
                configuration: configuration,
                sequenceNumber: sequenceNumber
            )
        )
    }

    @MainActor
    static func resetTrackedConfigurationsForFutureUse(
        records: inout [ChromeMV3NormalTabConfigurationAttachmentRecord],
        controller: WKWebExtensionController?
    ) {
        for record in records {
            guard let configuration = record.configuration else { continue }
            if let controller,
               configurationControllerMatches(configuration, controller: controller)
            {
                configuration.webExtensionController = nil
            }
            configuration.sumiHasChromeMV3NormalTabConfigurationAttachment =
                false
        }
    }

    @MainActor
    static func markTrackedWebViewCreated(
        configuration: WKWebViewConfiguration,
        records: inout [ChromeMV3NormalTabConfigurationAttachmentRecord],
        recorder: inout ChromeMV3LiveNormalTabAttachmentRecorder
    ) {
        prune(records: &records)
        guard let record = records.first(where: {
            $0.configuration === configuration
        }) else { return }
        recorder.markCreatedWebView(sequenceNumber: record.sequenceNumber)
    }

    @MainActor
    static func detach(
        configuration: WKWebViewConfiguration,
        owner: ChromeMV3EmptyControllerOwner?
    ) -> ChromeMV3NormalTabConfigurationAttachmentDiagnostics {
        let controller = owner?.controller
        if configurationControllerMatches(configuration, controller: controller) {
            configuration.webExtensionController = nil
        }
        configuration.sumiHasChromeMV3NormalTabConfigurationAttachment = false

        let request = ChromeMV3NormalTabConfigurationAttachmentRequest(
            owner: owner,
            extensionsModuleEnabled: owner?.diagnostics().controllerCreated == true,
            profileHostEnabled: owner?.diagnostics().controllerCreated == true,
            explicitInternalNormalTabAttachmentAllowed: false
        )
        return inspect(configuration: configuration, request: request)
    }

    @MainActor
    private static func evaluateGate(
        configuration: WKWebViewConfiguration,
        request: ChromeMV3NormalTabConfigurationAttachmentRequest?,
        controller: WKWebExtensionController?
    ) -> ChromeMV3NormalTabConfigurationAttachmentGateDecision {
        let ownerDiagnostics = request?.owner?.diagnostics()
        return ChromeMV3NormalTabConfigurationAttachmentGate.evaluate(
            input: ChromeMV3NormalTabConfigurationAttachmentGateInput(
                extensionsModuleEnabled:
                    request?.extensionsModuleEnabled ?? false,
                profileHostEnabled:
                    request?.profileHostEnabled ?? false,
                emptyControllerExists:
                    controller != nil
                        && ownerDiagnostics?.controllerCreated == true,
                explicitInternalNormalTabAttachmentAllowed:
                    request?.explicitInternalNormalTabAttachmentAllowed
                        ?? false,
                surface: request?.surface ?? .normalTab,
                isRealNormalTabConfiguration:
                    configuration.sumiIsNormalTabWebViewConfiguration,
                configurationHasControllerAttachment:
                    configuration.webExtensionController != nil,
                requestedContextLoading:
                    request?.requestedContextLoading ?? false,
                canLoadContextNow: request?.canLoadContextNow ?? false,
                runtimeLoadable: request?.runtimeLoadable ?? false,
                contextCount: controller?.extensionContexts.count
                    ?? ownerDiagnostics?.contextCount
                    ?? 0,
                loadedExtensionCount: controller?.extensions.count
                    ?? ownerDiagnostics?.loadedExtensionCount
                    ?? 0,
                nativeMessagingPortCount:
                    ownerDiagnostics?.nativeMessagingPortCount ?? 0
            )
        )
    }

    @MainActor
    private static func diagnostics(
        configuration: WKWebViewConfiguration,
        request: ChromeMV3NormalTabConfigurationAttachmentRequest?,
        controller: WKWebExtensionController?,
        gateDecision: ChromeMV3NormalTabConfigurationAttachmentGateDecision
    ) -> ChromeMV3NormalTabConfigurationAttachmentDiagnostics {
        let hasAttachment = configuration.webExtensionController != nil
        let ownerDiagnostics = request?.owner?.diagnostics()
        let attachmentMatchesOwner = configurationControllerMatches(
            configuration,
            controller: controller
        )
        return ChromeMV3NormalTabConfigurationAttachmentDiagnostics(
            gateDecision: gateDecision,
            attachmentRequested: request != nil,
            tabIdentifier: request?.attemptMetadata.tabIdentifier,
            tabDiagnosticIdentifier:
                request?.attemptMetadata.tabDiagnosticIdentifier,
            windowIdentifier: request?.attemptMetadata.windowIdentifier,
            profileIdentifier: request?.attemptMetadata.profileIdentifier,
            creationReason:
                request?.attemptMetadata.creationReason ?? "unspecified",
            targetSurface: request?.targetSurface ?? .normalTab,
            emptyControllerOwnerPresent:
                request?.emptyControllerOwnerPresent ?? false,
            explicitInternalNormalTabAttachmentAllowed:
                request?.explicitInternalNormalTabAttachmentAllowed ?? false,
            normalTabConfigurationCreated: true,
            normalTabConfigurationAttached:
                configuration.sumiIsNormalTabWebViewConfiguration
                    && hasAttachment,
            auxiliaryConfigurationAttached:
                configuration.sumiIsNormalTabWebViewConfiguration == false
                    && hasAttachment,
            attachedControllerMatchesOwner: attachmentMatchesOwner,
            attachedControllerIdentity: attachmentMatchesOwner
                ? ownerDiagnostics?.dataStoreIdentityPolicy
                    .controllerConfigurationIdentityString
                : nil,
            contextCount: controller?.extensionContexts.count ?? 0,
            loadedExtensionCount: controller?.extensions.count ?? 0,
            attachedWebViewCount: 0,
            userScriptCount:
                configuration.userContentController.userScripts.count,
            userScriptRegistrationCount: 0,
            webExtensionCreated: false,
            webExtensionContextCreated: false,
            contextLoadCalled: false,
            generatedExtensionBundleLoaded: false,
            nativeMessagingLaunched: false,
            nativeMessagingPortCount:
                ownerDiagnostics?.nativeMessagingPortCount ?? 0,
            runtimeLoadable: false,
            canLoadContextNow: false,
            canAttachNormalTabConfigurationNow:
                gateDecision.canAttachNormalTabConfigurationNow,
            canAttachAuxiliaryConfigurationNow: false
        )
    }

    @MainActor
    private static func prune(
        records: inout [ChromeMV3NormalTabConfigurationAttachmentRecord]
    ) {
        records.removeAll { $0.configuration == nil }
    }

    @MainActor
    private static func configurationControllerMatches(
        _ configuration: WKWebViewConfiguration,
        controller: WKWebExtensionController?
    ) -> Bool {
        guard let attachedController = configuration.webExtensionController,
              let controller
        else { return false }
        return ObjectIdentifier(attachedController) == ObjectIdentifier(controller)
    }
}

private enum ChromeMV3NormalTabConfigurationAssociatedKeys {
    private static let attachmentStorage =
        StaticString("Sumi.ChromeMV3.normalTabConfigurationAttachment")

    static var attachment: UnsafeRawPointer {
        UnsafeRawPointer(attachmentStorage.utf8Start)
    }
}

extension WKWebViewConfiguration {
    var sumiHasChromeMV3NormalTabConfigurationAttachment: Bool {
        get {
            (objc_getAssociatedObject(
                self,
                ChromeMV3NormalTabConfigurationAssociatedKeys.attachment
            ) as? Bool) == true
        }
        set {
            objc_setAssociatedObject(
                self,
                ChromeMV3NormalTabConfigurationAssociatedKeys.attachment,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
