//
//  ChromeMV3SyntheticConfigurationAttachmentGate.swift
//  Sumi
//
//  Explicit policy for the synthetic-only WebKit controller assignment test.
//  This file is policy-only and does not import WebKit.
//

import Foundation

enum ChromeMV3SyntheticConfigurationAttachmentBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case emptyControllerMissing
    case explicitSyntheticAttachmentNotAllowed
    case surfaceIsNotSyntheticTestConfiguration
    case realNormalTabConfiguration
    case realNormalTabSurface
    case auxiliaryOrHelperSurface
    case extensionOwnedProductionSurface
    case contextLoadingRequested
    case contextsAlreadyPresent
    case loadedExtensionsAlreadyPresent
    case runtimeLoadableRequested

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .emptyControllerMissing:
            return "A gated empty WKWebExtensionController must exist before synthetic configuration attachment."
        case .explicitSyntheticAttachmentNotAllowed:
            return "Explicit synthetic configuration attachment permission is missing."
        case .surfaceIsNotSyntheticTestConfiguration:
            return "Only the syntheticTestConfiguration surface may use this attachment harness."
        case .realNormalTabConfiguration:
            return "Real normal-tab WebView configurations are not eligible for this synthetic attachment harness."
        case .realNormalTabSurface:
            return "Normal browsing surfaces remain unattached."
        case .auxiliaryOrHelperSurface:
            return "Auxiliary, helper, preview, mini, favicon, and download surfaces remain unattached."
        case .extensionOwnedProductionSurface:
            return "Extension popup and options production surfaces are not wired to the Chrome MV3 controller."
        case .contextLoadingRequested:
            return "Context loading was requested, but synthetic attachment is configuration-only."
        case .contextsAlreadyPresent:
            return "The controller is no longer empty because extension contexts are present."
        case .loadedExtensionsAlreadyPresent:
            return "The controller is no longer empty because loaded extensions are present."
        case .runtimeLoadableRequested:
            return "runtimeLoadable must remain false for synthetic configuration attachment."
        }
    }
}

struct ChromeMV3SyntheticConfigurationAttachmentGateInput:
    Codable,
    Equatable,
    Sendable
{
    var extensionsModuleEnabled: Bool
    var emptyControllerExists: Bool
    var explicitSyntheticConfigurationAttachmentAllowed: Bool
    var surface: ChromeMV3WebViewSurface
    var isRealNormalTabConfiguration: Bool
    var requestedContextLoading: Bool
    var runtimeLoadable: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
}

struct ChromeMV3SyntheticConfigurationAttachmentGateDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var extensionsModuleEnabled: Bool
    var emptyControllerExists: Bool
    var explicitSyntheticConfigurationAttachmentAllowed: Bool
    var surface: ChromeMV3WebViewSurface
    var surfaceIsSyntheticTestConfiguration: Bool
    var isRealNormalTabConfiguration: Bool
    var isRealNormalTabSurface: Bool
    var isAuxiliaryOrHelperSurface: Bool
    var isExtensionOwnedProductionSurface: Bool
    var requestedContextLoading: Bool
    var requestedRuntimeLoadable: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var canAttachSyntheticConfigurationNow: Bool
    var canAttachRealConfigurationNow: Bool
    var canLoadContextNow: Bool
}

struct ChromeMV3SyntheticConfigurationAttachmentGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3SyntheticConfigurationAttachmentGateInput
    var canAttachSyntheticConfigurationNow: Bool
    var canAttachRealConfigurationNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3SyntheticConfigurationAttachmentBlocker]
    var blockingReasons: [String]
    var diagnostics: ChromeMV3SyntheticConfigurationAttachmentGateDiagnostics
}

enum ChromeMV3SyntheticConfigurationAttachmentGate {
    static func evaluate(
        input: ChromeMV3SyntheticConfigurationAttachmentGateInput
    ) -> ChromeMV3SyntheticConfigurationAttachmentGateDecision {
        var blockers: [ChromeMV3SyntheticConfigurationAttachmentBlocker] = []

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }

        if input.emptyControllerExists == false {
            blockers.append(.emptyControllerMissing)
        }

        if input.explicitSyntheticConfigurationAttachmentAllowed == false {
            blockers.append(.explicitSyntheticAttachmentNotAllowed)
        }

        if input.surface != .syntheticTestConfiguration {
            blockers.append(.surfaceIsNotSyntheticTestConfiguration)
        }

        if input.isRealNormalTabConfiguration {
            blockers.append(.realNormalTabConfiguration)
        }

        if input.surface.isRealNormalBrowsingSurfaceForChromeMV3Attachment {
            blockers.append(.realNormalTabSurface)
        }

        if input.surface.isAuxiliaryOrHelperSurfaceForChromeMV3Attachment {
            blockers.append(.auxiliaryOrHelperSurface)
        }

        if input.surface.isExtensionOwnedProductionSurfaceForChromeMV3Attachment {
            blockers.append(.extensionOwnedProductionSurface)
        }

        if input.requestedContextLoading {
            blockers.append(.contextLoadingRequested)
        }

        if input.contextCount > 0 {
            blockers.append(.contextsAlreadyPresent)
        }

        if input.loadedExtensionCount > 0 {
            blockers.append(.loadedExtensionsAlreadyPresent)
        }

        if input.runtimeLoadable {
            blockers.append(.runtimeLoadableRequested)
        }

        let canAttachSyntheticConfigurationNow = blockers.isEmpty
        let diagnostics = ChromeMV3SyntheticConfigurationAttachmentGateDiagnostics(
            extensionsModuleEnabled: input.extensionsModuleEnabled,
            emptyControllerExists: input.emptyControllerExists,
            explicitSyntheticConfigurationAttachmentAllowed:
                input.explicitSyntheticConfigurationAttachmentAllowed,
            surface: input.surface,
            surfaceIsSyntheticTestConfiguration:
                input.surface == .syntheticTestConfiguration,
            isRealNormalTabConfiguration: input.isRealNormalTabConfiguration,
            isRealNormalTabSurface:
                input.surface.isRealNormalBrowsingSurfaceForChromeMV3Attachment,
            isAuxiliaryOrHelperSurface:
                input.surface.isAuxiliaryOrHelperSurfaceForChromeMV3Attachment,
            isExtensionOwnedProductionSurface:
                input.surface.isExtensionOwnedProductionSurfaceForChromeMV3Attachment,
            requestedContextLoading: input.requestedContextLoading,
            requestedRuntimeLoadable: input.runtimeLoadable,
            contextCount: input.contextCount,
            loadedExtensionCount: input.loadedExtensionCount,
            canAttachSyntheticConfigurationNow:
                canAttachSyntheticConfigurationNow,
            canAttachRealConfigurationNow: false,
            canLoadContextNow: false
        )

        return ChromeMV3SyntheticConfigurationAttachmentGateDecision(
            input: input,
            canAttachSyntheticConfigurationNow:
                canAttachSyntheticConfigurationNow,
            canAttachRealConfigurationNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: blockers,
            blockingReasons: blockers.map(\.reason),
            diagnostics: diagnostics
        )
    }
}

extension ChromeMV3WebViewSurface {
    var isRealNormalBrowsingSurfaceForChromeMV3Attachment: Bool {
        switch self {
        case .normalTab, .pinnedEssentialsLiveNormalBrowsing:
            return true
        default:
            return false
        }
    }

    var isAuxiliaryOrHelperSurfaceForChromeMV3Attachment: Bool {
        switch self {
        case .peekGlancePreview,
             .miniWindow,
             .faviconDownload,
             .downloadHelper,
             .helperWebView,
             .webKitCreatedPopupOrNewWindow:
            return true
        default:
            return false
        }
    }

    var isExtensionOwnedProductionSurfaceForChromeMV3Attachment: Bool {
        switch self {
        case .extensionOwnedPopup, .extensionOwnedOptionsPage:
            return true
        default:
            return false
        }
    }
}
