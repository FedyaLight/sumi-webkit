//
//  ChromeMV3ControllerCreationGate.swift
//  Sumi
//
//  Profile-scoped gate for the first empty WebKit controller allocation.
//  This file is policy-only and does not import WebKit.
//

import Foundation

enum ChromeMV3ControllerCreationGateBlocker: String, Codable, CaseIterable, Sendable {
    case extensionsModuleDisabled
    case profileHostDisabled
    case explicitControllerCreationNotAllowed
    case disabledRuntimeInvariantViolation
    case contextLoadingRequested
    case normalTabAttachmentRequested
    case profileIdentityUnavailable
    case websiteDataStoreIdentityUnavailable

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .profileHostDisabled:
            return "The Chrome MV3 profile host is disabled."
        case .explicitControllerCreationNotAllowed:
            return "Explicit Chrome MV3 controller creation is not allowed."
        case .disabledRuntimeInvariantViolation:
            return "Disabled-runtime invariants are not satisfied."
        case .contextLoadingRequested:
            return "Context loading was requested, but this gate only permits an empty controller."
        case .normalTabAttachmentRequested:
            return "Normal-tab WebView attachment was requested, but attachment remains blocked."
        case .profileIdentityUnavailable:
            return "A concrete profile identity is required before creating a controller."
        case .websiteDataStoreIdentityUnavailable:
            return "A profile website data store identity or safe placeholder is required before creating a controller."
        }
    }
}

struct ChromeMV3ControllerCreationGateInput: Codable, Equatable, Sendable {
    var extensionsModuleEnabled: Bool
    var profileHostModuleState: ChromeMV3ProfileHostModuleState
    var profileHostControllerState: ChromeMV3ProfileHostControllerState
    var explicitControllerCreationAllowed: Bool
    var requestedContextLoading: Bool
    var requestedNormalTabAttachment: Bool
    var profileIdentifier: String
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var disabledRuntimeInvariantStatus: ChromeMV3DisabledRuntimeInvariantStatus
}

struct ChromeMV3ControllerCreationGateDecision: Codable, Equatable, Sendable {
    var input: ChromeMV3ControllerCreationGateInput
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3ControllerCreationGateBlocker]
    var blockingReasons: [String]

    var passed: Bool {
        canCreateControllerNow
    }
}

enum ChromeMV3ControllerCreationGate {
    static func evaluate(
        input: ChromeMV3ControllerCreationGateInput
    ) -> ChromeMV3ControllerCreationGateDecision {
        var blockers: [ChromeMV3ControllerCreationGateBlocker] = []

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }

        if input.profileHostModuleState != .enabled {
            blockers.append(.profileHostDisabled)
        }

        if input.explicitControllerCreationAllowed == false {
            blockers.append(.explicitControllerCreationNotAllowed)
        }

        if input.disabledRuntimeInvariantStatus.isSatisfied == false {
            blockers.append(.disabledRuntimeInvariantViolation)
        }

        if input.requestedContextLoading {
            blockers.append(.contextLoadingRequested)
        }

        if input.requestedNormalTabAttachment {
            blockers.append(.normalTabAttachmentRequested)
        }

        if input.profileIdentifier.isResolvedChromeMV3ProfileIdentifier == false {
            blockers.append(.profileIdentityUnavailable)
        }

        if input.profileDataStoreIdentity.isResolvedForChromeMV3ControllerCreation == false {
            blockers.append(.websiteDataStoreIdentityUnavailable)
        }

        return ChromeMV3ControllerCreationGateDecision(
            input: input,
            canCreateControllerNow: blockers.isEmpty,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            runtimeLoadable: false,
            blockers: blockers,
            blockingReasons: blockers.map(\.reason)
        )
    }
}

extension ChromeMV3ProfileHost {
    func controllerCreationGateDecision(
        extensionsModuleEnabled: Bool,
        explicitControllerCreationAllowed: Bool,
        requestedContextLoading: Bool = false,
        requestedNormalTabAttachment: Bool = false,
        disabledRuntimeInvariantStatus: ChromeMV3DisabledRuntimeInvariantStatus = .satisfied
    ) -> ChromeMV3ControllerCreationGateDecision {
        ChromeMV3ControllerCreationGate.evaluate(
            input: ChromeMV3ControllerCreationGateInput(
                extensionsModuleEnabled: extensionsModuleEnabled,
                profileHostModuleState: moduleState,
                profileHostControllerState: controllerState,
                explicitControllerCreationAllowed: explicitControllerCreationAllowed,
                requestedContextLoading: requestedContextLoading,
                requestedNormalTabAttachment: requestedNormalTabAttachment,
                profileIdentifier: profileIdentifier,
                profileDataStoreIdentity: profileDataStoreIdentity,
                disabledRuntimeInvariantStatus: disabledRuntimeInvariantStatus
            )
        )
    }
}

extension ChromeMV3DisabledRuntimeInvariantStatus {
    static var satisfied: ChromeMV3DisabledRuntimeInvariantStatus {
        ChromeMV3DisabledRuntimeInvariantStatus(
            noWebKitExtensionObjectCreated: true,
            noControllerObjectCreated: true,
            noContextObjectCreated: true,
            noControllerAttachedToConfigurations: true,
            noExtensionJavaScriptRegistered: true,
            noServiceWorkerWakeups: true,
            noNativeMessagingRuntime: true,
            noHiddenRuntimeCost: true,
            accidentalAttachmentWhileDisabledDetected: false
        )
    }

    var isSatisfied: Bool {
        noWebKitExtensionObjectCreated
            && noControllerObjectCreated
            && noContextObjectCreated
            && noControllerAttachedToConfigurations
            && noExtensionJavaScriptRegistered
            && noServiceWorkerWakeups
            && noNativeMessagingRuntime
            && noHiddenRuntimeCost
            && accidentalAttachmentWhileDisabledDetected == false
    }
}

private extension ChromeMV3ProfileDataStoreIdentity {
    var isResolvedForChromeMV3ControllerCreation: Bool {
        switch self {
        case let .profileIdentifier(identifier),
             let .ephemeralProfileIdentifier(identifier),
             let .placeholder(identifier):
            return identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
        case .unresolved:
            return false
        }
    }
}

private extension String {
    var isResolvedChromeMV3ProfileIdentifier: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false
            && trimmed != ChromeMV3ProfileHost.unresolvedProfileIdentifier
    }
}
