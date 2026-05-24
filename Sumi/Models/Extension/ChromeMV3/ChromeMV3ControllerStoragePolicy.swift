//
//  ChromeMV3ControllerStoragePolicy.swift
//  Sumi
//
//  Storage and teardown policy for the gated empty Chrome MV3 controller.
//  This file is diagnostics-only and does not create, clear, or migrate
//  website data.
//

import Foundation

enum ChromeMV3ControllerDataStoreStorageKind: String, Codable, Sendable {
    case persistentProfile
    case ephemeralPrivateProfile
    case placeholder
    case unresolved
}

struct ChromeMV3ControllerDataStoreIdentityDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var profileIdentifier: String
    var dataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var dataStoreIdentityString: String
    var dataStoreIdentityValue: String?
    var storageKind: ChromeMV3ControllerDataStoreStorageKind
    var identityResolved: Bool
    var allowedForFuturePersistentProfileUse: Bool
    var allowedForFutureEphemeralPrivateProfileUse: Bool
    var cleanupRequiredOnDisableOrTeardown: Bool
    var generatedArtifactsTiedToDataStoreIdentity: Bool
    var controllerConfigurationIdentityString: String?
    var usesNonPersistentControllerConfiguration: Bool
    var clearsWebsiteDataOnCleanup: Bool
    var deletesGeneratedArtifactsOnCleanup: Bool
    var notes: [String]
}

enum ChromeMV3ControllerDataStoreIdentityPolicy {
    static func evaluate(
        profileIdentifier: String,
        dataStoreIdentity: ChromeMV3ProfileDataStoreIdentity,
        controllerConfigurationIdentifier: String? = nil,
        controllerCreated: Bool,
        generatedArtifactsTiedToDataStoreIdentity: Bool = false
    ) -> ChromeMV3ControllerDataStoreIdentityDiagnostics {
        let description = describe(dataStoreIdentity)
        let usesNonPersistentControllerConfiguration =
            description.storageKind == .ephemeralPrivateProfile

        return ChromeMV3ControllerDataStoreIdentityDiagnostics(
            profileIdentifier: profileIdentifier,
            dataStoreIdentity: dataStoreIdentity,
            dataStoreIdentityString: description.identityString,
            dataStoreIdentityValue: description.identityValue,
            storageKind: description.storageKind,
            identityResolved: description.identityResolved,
            allowedForFuturePersistentProfileUse:
                description.storageKind == .persistentProfile
                    && description.identityResolved,
            allowedForFutureEphemeralPrivateProfileUse:
                description.storageKind == .ephemeralPrivateProfile
                    && description.identityResolved,
            cleanupRequiredOnDisableOrTeardown: controllerCreated,
            generatedArtifactsTiedToDataStoreIdentity:
                generatedArtifactsTiedToDataStoreIdentity,
            controllerConfigurationIdentityString:
                controllerConfigurationIdentifier,
            usesNonPersistentControllerConfiguration:
                usesNonPersistentControllerConfiguration,
            clearsWebsiteDataOnCleanup: false,
            deletesGeneratedArtifactsOnCleanup: false,
            notes: notes(
                storageKind: description.storageKind,
                identityResolved: description.identityResolved,
                controllerCreated: controllerCreated,
                generatedArtifactsTiedToDataStoreIdentity:
                    generatedArtifactsTiedToDataStoreIdentity
            )
        )
    }

    private static func describe(
        _ identity: ChromeMV3ProfileDataStoreIdentity
    ) -> (
        identityString: String,
        identityValue: String?,
        storageKind: ChromeMV3ControllerDataStoreStorageKind,
        identityResolved: Bool
    ) {
        switch identity {
        case let .profileIdentifier(value):
            return (
                "profileIdentifier:\(value)",
                value,
                .persistentProfile,
                value.isNonEmptyChromeMV3StorageIdentity
            )
        case let .ephemeralProfileIdentifier(value):
            return (
                "ephemeralProfileIdentifier:\(value)",
                value,
                .ephemeralPrivateProfile,
                value.isNonEmptyChromeMV3StorageIdentity
            )
        case let .placeholder(value):
            return (
                "placeholder:\(value)",
                value,
                .placeholder,
                value.isNonEmptyChromeMV3StorageIdentity
            )
        case .unresolved:
            return ("unresolved", nil, .unresolved, false)
        }
    }

    private static func notes(
        storageKind: ChromeMV3ControllerDataStoreStorageKind,
        identityResolved: Bool,
        controllerCreated: Bool,
        generatedArtifactsTiedToDataStoreIdentity: Bool
    ) -> [String] {
        var notes: [String] = [
            "Cleanup only releases the empty controller reference.",
            "Website data is not cleared by this Chrome MV3 policy.",
            "Generated artifacts are not deleted by this Chrome MV3 policy.",
        ]

        if identityResolved == false {
            notes.append("No resolved website data store identity is available.")
        }

        switch storageKind {
        case .persistentProfile:
            notes.append("The identity maps to Sumi's persistent profile data store architecture.")
        case .ephemeralPrivateProfile:
            notes.append("The identity maps to Sumi's private profile data store architecture.")
        case .placeholder:
            notes.append("The placeholder identity is diagnostic-only and is not approved for future profile storage.")
        case .unresolved:
            notes.append("No controller storage identity should be used for future attachment.")
        }

        if controllerCreated {
            notes.append("Disable, profile close, reset, or failed future preflight must release the empty controller.")
        }

        if generatedArtifactsTiedToDataStoreIdentity == false {
            notes.append("Generated bundle artifacts remain path-based and are not tied to this data store identity.")
        }

        return Array(Set(notes)).sorted()
    }
}

enum ChromeMV3EmptyControllerTeardownTrigger:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case moduleDisable
    case profileClose
    case explicitReset
    case failedFuturePreflight
    case normalTabAttachmentGateOff
}

struct ChromeMV3EmptyControllerTeardownPolicy:
    Codable,
    Equatable,
    Sendable
{
    var trigger: ChromeMV3EmptyControllerTeardownTrigger
    var shouldReleaseEmptyController: Bool
    var shouldClearWebsiteData: Bool
    var shouldDeleteGeneratedArtifacts: Bool
    var shouldCancelNativeMessagingPorts: Bool
    var futureConfigurationsBecomeUnattachedImmediately: Bool
    var marksExistingDebugAttachedWebViewsStale: Bool
    var claimsExistingWebViewsDetached: Bool
    var requiresWebViewRecreationForExistingDebugAttachedInstances: Bool
    var userVisibleReloadOrRecreatePolicy: String
    var pendingContextLoadsAfterTeardown: Int
    var pendingAttachmentsAfterTeardown: Int
    var notes: [String]
}

enum ChromeMV3EmptyControllerTeardownPolicyEvaluator {
    static func evaluate(
        trigger: ChromeMV3EmptyControllerTeardownTrigger,
        controllerCreated: Bool
    ) -> ChromeMV3EmptyControllerTeardownPolicy {
        ChromeMV3EmptyControllerTeardownPolicy(
            trigger: trigger,
            shouldReleaseEmptyController: controllerCreated,
            shouldClearWebsiteData: false,
            shouldDeleteGeneratedArtifacts: false,
            shouldCancelNativeMessagingPorts: false,
            futureConfigurationsBecomeUnattachedImmediately: true,
            marksExistingDebugAttachedWebViewsStale: controllerCreated,
            claimsExistingWebViewsDetached: false,
            requiresWebViewRecreationForExistingDebugAttachedInstances:
                controllerCreated,
            userVisibleReloadOrRecreatePolicy: "deferred",
            pendingContextLoadsAfterTeardown: 0,
            pendingAttachmentsAfterTeardown: 0,
            notes: notes(trigger: trigger, controllerCreated: controllerCreated)
        )
    }

    private static func notes(
        trigger: ChromeMV3EmptyControllerTeardownTrigger,
        controllerCreated: Bool
    ) -> [String] {
        var notes: [String] = [
            "Teardown leaves generated Chrome MV3 artifacts intact.",
            "Teardown does not clear website data or extension storage.",
            "No contexts, attachments, native message ports, or pending loads are created by this policy.",
            "Future normal-tab configurations must be created without the DEBUG empty controller after teardown.",
            "Already-created DEBUG-attached WKWebViews are marked stale and require deferred recreation before they can be considered unattached.",
            "Teardown does not claim an existing WKWebView is detached by mutating its original configuration object.",
        ]

        switch trigger {
        case .moduleDisable:
            notes.append("Module disable releases the empty controller if it exists.")
        case .profileClose:
            notes.append("Profile close releases the profile-scoped empty controller if it exists.")
        case .explicitReset:
            notes.append("Explicit reset releases the empty controller if it exists.")
        case .failedFuturePreflight:
            notes.append("A failed future attachment preflight releases the empty controller if it exists.")
        case .normalTabAttachmentGateOff:
            notes.append("Turning off the DEBUG normal-tab attachment flag keeps future configurations unattached and marks existing DEBUG-attached WKWebViews stale.")
        }

        if controllerCreated == false {
            notes.append("No controller object exists, so teardown reports a not-created state.")
        }

        return Array(Set(notes)).sorted()
    }
}

private extension String {
    var isNonEmptyChromeMV3StorageIdentity: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
