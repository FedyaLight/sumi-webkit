//
//  ChromeMV3NormalTabConfigurationAttachmentGate.swift
//  Sumi
//
//  Policy-only gate for attaching the empty Chrome MV3 controller to real
//  normal-tab WKWebViewConfiguration objects. It never creates or loads
//  extension contexts and never makes runtime loadability true.
//

import Foundation

enum ChromeMV3NormalTabConfigurationAttachmentBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case debugBuildRequired
    case extensionsModuleDisabled
    case profileHostDisabled
    case emptyControllerMissing
    case explicitInternalNormalTabAttachmentNotAllowed
    case configurationIsNotRealNormalTab
    case configurationAlreadyHasController
    case surfaceIsNotNormalBrowsing
    case launcherMetadataSurface
    case peekGlancePreviewSurface
    case miniWindowSurface
    case faviconDownloadSurface
    case downloadOrHelperSurface
    case extensionOwnedAuxiliarySurface
    case contextLoadingRequested
    case contextLoadingCapabilityEnabled
    case contextsAlreadyPresent
    case loadedExtensionsAlreadyPresent
    case nativeMessagingPortsPresent
    case runtimeLoadableRequested

    var reason: String {
        switch self {
        case .debugBuildRequired:
            return "Normal-tab configuration attachment is DEBUG/internal only."
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .profileHostDisabled:
            return "The Chrome MV3 profile host is disabled."
        case .emptyControllerMissing:
            return "A gated empty WKWebExtensionController must exist before normal-tab configuration attachment."
        case .explicitInternalNormalTabAttachmentNotAllowed:
            return "Explicit internal normal-tab configuration attachment permission is missing."
        case .configurationIsNotRealNormalTab:
            return "The WKWebViewConfiguration is not marked as a real normal-tab configuration."
        case .configurationAlreadyHasController:
            return "The WKWebViewConfiguration already has a webExtensionController."
        case .surfaceIsNotNormalBrowsing:
            return "Only real normal tabs and pinned/Essentials live normal browsing runtimes may attach."
        case .launcherMetadataSurface:
            return "Pinned or Essentials launcher metadata is not a browsing WebView."
        case .peekGlancePreviewSurface:
            return "Peek and Glance preview surfaces remain unattached."
        case .miniWindowSurface:
            return "Mini-window surfaces remain unattached."
        case .faviconDownloadSurface:
            return "Favicon download helper configurations remain unattached."
        case .downloadOrHelperSurface:
            return "Download and helper WebView configurations remain unattached."
        case .extensionOwnedAuxiliarySurface:
            return "Extension popup and options auxiliary surfaces require a future extension UI host."
        case .contextLoadingRequested:
            return "Context loading was requested, but this path is configuration attachment only."
        case .contextLoadingCapabilityEnabled:
            return "canLoadContextNow must remain false for normal-tab configuration attachment."
        case .contextsAlreadyPresent:
            return "The controller is no longer empty because extension contexts are present."
        case .loadedExtensionsAlreadyPresent:
            return "The controller is no longer empty because loaded extensions are present."
        case .nativeMessagingPortsPresent:
            return "Native messaging ports are present, but this path must not launch native messaging."
        case .runtimeLoadableRequested:
            return "runtimeLoadable must remain false for normal-tab configuration attachment."
        }
    }
}

struct ChromeMV3NormalTabConfigurationAttachmentGateInput:
    Codable,
    Equatable,
    Sendable
{
    var extensionsModuleEnabled: Bool
    var profileHostEnabled: Bool
    var emptyControllerExists: Bool
    var explicitInternalNormalTabAttachmentAllowed: Bool
    var surface: ChromeMV3WebViewSurface
    var isRealNormalTabConfiguration: Bool
    var configurationHasControllerAttachment: Bool
    var requestedContextLoading: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var nativeMessagingPortCount: Int
}

struct ChromeMV3NormalTabConfigurationAttachmentGateDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var debugBuild: Bool
    var extensionsModuleEnabled: Bool
    var profileHostEnabled: Bool
    var emptyControllerExists: Bool
    var explicitInternalNormalTabAttachmentAllowed: Bool
    var surface: ChromeMV3WebViewSurface
    var surfaceIsRealNormalBrowsing: Bool
    var surfaceIsLauncherMetadata: Bool
    var surfaceIsPeekGlancePreview: Bool
    var surfaceIsMiniWindow: Bool
    var surfaceIsFaviconDownload: Bool
    var surfaceIsDownloadOrHelper: Bool
    var surfaceIsExtensionOwnedAuxiliary: Bool
    var isRealNormalTabConfiguration: Bool
    var configurationHasControllerAttachment: Bool
    var requestedContextLoading: Bool
    var canLoadContextNowInput: Bool
    var requestedRuntimeLoadable: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var nativeMessagingPortCount: Int
    var canAttachNormalTabConfigurationNow: Bool
    var canAttachAuxiliaryConfigurationNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3NormalTabConfigurationAttachmentGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3NormalTabConfigurationAttachmentGateInput
    var canAttachNormalTabConfigurationNow: Bool
    var canAttachAuxiliaryConfigurationNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3NormalTabConfigurationAttachmentBlocker]
    var blockingReasons: [String]
    var diagnostics: ChromeMV3NormalTabConfigurationAttachmentGateDiagnostics
}

enum ChromeMV3NormalTabConfigurationAttachmentGate {
    static func evaluate(
        input: ChromeMV3NormalTabConfigurationAttachmentGateInput
    ) -> ChromeMV3NormalTabConfigurationAttachmentGateDecision {
        var blockers: [ChromeMV3NormalTabConfigurationAttachmentBlocker] = []

        #if DEBUG
            let debugBuild = true
        #else
            let debugBuild = false
            blockers.append(.debugBuildRequired)
        #endif

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }

        if input.profileHostEnabled == false {
            blockers.append(.profileHostDisabled)
        }

        if input.emptyControllerExists == false {
            blockers.append(.emptyControllerMissing)
        }

        if input.explicitInternalNormalTabAttachmentAllowed == false {
            blockers.append(.explicitInternalNormalTabAttachmentNotAllowed)
        }

        if input.isRealNormalTabConfiguration == false {
            blockers.append(.configurationIsNotRealNormalTab)
        }

        if input.configurationHasControllerAttachment {
            blockers.append(.configurationAlreadyHasController)
        }

        if input.surface.isRealNormalBrowsingSurfaceForChromeMV3Attachment == false {
            blockers.append(.surfaceIsNotNormalBrowsing)
        }

        switch input.surface {
        case .pinnedEssentialsLauncherMetadata:
            blockers.append(.launcherMetadataSurface)
        case .peekGlancePreview:
            blockers.append(.peekGlancePreviewSurface)
        case .miniWindow:
            blockers.append(.miniWindowSurface)
        case .faviconDownload:
            blockers.append(.faviconDownloadSurface)
        case .downloadHelper, .helperWebView, .webKitCreatedPopupOrNewWindow:
            blockers.append(.downloadOrHelperSurface)
        case .extensionOwnedPopup, .extensionOwnedOptionsPage:
            blockers.append(.extensionOwnedAuxiliarySurface)
        case .syntheticTestConfiguration, .normalTab, .pinnedEssentialsLiveNormalBrowsing:
            break
        }

        if input.requestedContextLoading {
            blockers.append(.contextLoadingRequested)
        }

        if input.canLoadContextNow {
            blockers.append(.contextLoadingCapabilityEnabled)
        }

        if input.contextCount > 0 {
            blockers.append(.contextsAlreadyPresent)
        }

        if input.loadedExtensionCount > 0 {
            blockers.append(.loadedExtensionsAlreadyPresent)
        }

        if input.nativeMessagingPortCount > 0 {
            blockers.append(.nativeMessagingPortsPresent)
        }

        if input.runtimeLoadable {
            blockers.append(.runtimeLoadableRequested)
        }

        let canAttachNormalTabConfigurationNow = blockers.isEmpty
        let diagnostics =
            ChromeMV3NormalTabConfigurationAttachmentGateDiagnostics(
                debugBuild: debugBuild,
                extensionsModuleEnabled: input.extensionsModuleEnabled,
                profileHostEnabled: input.profileHostEnabled,
                emptyControllerExists: input.emptyControllerExists,
                explicitInternalNormalTabAttachmentAllowed:
                    input.explicitInternalNormalTabAttachmentAllowed,
                surface: input.surface,
                surfaceIsRealNormalBrowsing:
                    input.surface.isRealNormalBrowsingSurfaceForChromeMV3Attachment,
                surfaceIsLauncherMetadata:
                    input.surface == .pinnedEssentialsLauncherMetadata,
                surfaceIsPeekGlancePreview:
                    input.surface == .peekGlancePreview,
                surfaceIsMiniWindow: input.surface == .miniWindow,
                surfaceIsFaviconDownload: input.surface == .faviconDownload,
                surfaceIsDownloadOrHelper:
                    input.surface == .downloadHelper
                        || input.surface == .helperWebView
                        || input.surface == .webKitCreatedPopupOrNewWindow,
                surfaceIsExtensionOwnedAuxiliary:
                    input.surface
                        .isExtensionOwnedProductionSurfaceForChromeMV3Attachment,
                isRealNormalTabConfiguration:
                    input.isRealNormalTabConfiguration,
                configurationHasControllerAttachment:
                    input.configurationHasControllerAttachment,
                requestedContextLoading: input.requestedContextLoading,
                canLoadContextNowInput: input.canLoadContextNow,
                requestedRuntimeLoadable: input.runtimeLoadable,
                contextCount: input.contextCount,
                loadedExtensionCount: input.loadedExtensionCount,
                nativeMessagingPortCount: input.nativeMessagingPortCount,
                canAttachNormalTabConfigurationNow:
                    canAttachNormalTabConfigurationNow,
                canAttachAuxiliaryConfigurationNow: false,
                canLoadContextNow: false,
                runtimeLoadable: false
            )

        return ChromeMV3NormalTabConfigurationAttachmentGateDecision(
            input: input,
            canAttachNormalTabConfigurationNow:
                canAttachNormalTabConfigurationNow,
            canAttachAuxiliaryConfigurationNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue },
            blockingReasons: Array(Set(blockers.map(\.reason))).sorted(),
            diagnostics: diagnostics
        )
    }
}
