//
//  SafariExtensionNativeMessagingProbeReport.swift
//  Sumi
//
//  DEBUG native-messaging probe report data models.
//

import Foundation

/// Static or runtime biometrics probe status for adapter routing reports (no credential data).
enum SumiNativeMessagingBiometricsStatusProbe: String, Codable, Sendable, Equatable {
    case notApplicable
    case notAttempted
    case available
    case unavailable
    case probeOnly
}

struct SafariExtensionNativeMessagingProbeEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { extensionId ?? targetKey }

    let targetKey: String
    let displayName: String
    let extensionId: String?
    let isImported: Bool
    let isEnabled: Bool
    let popupStatus: SafariExtensionPopupLoadStatus
    let delegateCallbackObserved: Bool
    let applicationIdentifier: String?
    let resolverBucket: SumiNativeMessagingResolverBucket?
    let connectionBucket: SafariExtensionNativeMessagingConnectionBucket
    let errorBucket: SafariExtensionNativeMessagingErrorBucket
    let classifications: [SafariExtensionNativeMessagingClassification]
    let launchSuppressionExpected: Bool
    let expectedSessionState: SumiNativeMessagingSessionState?
    let adapterSelected: Bool
    let adapterIdentifier: String?
    let appResolved: Bool
    let appLaunched: Bool
    let protocolStatus: SumiNativeMessagingProtocolStatus
    let handshakeStatus: SumiNativeMessagingHandshakeStatus
    let autofillPathStatus: SumiNativeMessagingAutofillPathStatus
    let failureBucket: SafariExtensionNativeMessagingErrorBucket
}

/// Per-target adapter boundary status for DEBUG compatibility reports (Raindrop / PM targets).
struct SafariExtensionNativeMessagingAdapterCompatibilityStatus: Codable, Equatable, Sendable,
    Identifiable
{
    var id: String { targetKey }

    let targetKey: String
    let displayName: String
    let applicationIdentifier: String?
    let hostBundleIdentifier: String?
    let adapterSelected: Bool
    let adapterIdentifier: String?
    let appResolved: Bool
    let appInstalled: Bool
    let launchSuppressionExpected: Bool
    let protocolStatus: SumiNativeMessagingProtocolStatus
    let handshakeStatus: SumiNativeMessagingHandshakeStatus
    let autofillPathStatus: SumiNativeMessagingAutofillPathStatus
    let failureBucket: SafariExtensionNativeMessagingErrorBucket
    let registeredAdapterIdentifiers: [String]
    let realTransportAttempted: Bool
    let desktopResolved: Bool
    let desktopRunning: Bool
    let desktopLaunchAttempted: Bool
    let desktopLaunchSuppressed: Bool
    let biometricsStatusProbe: SumiNativeMessagingBiometricsStatusProbe
    let repeatedCallCountBucket: SumiNativeMessagingRetryCountBucket
}

struct SafariExtensionNativeMessagingProbeReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let entries: [SafariExtensionNativeMessagingProbeEntry]
    let adapterCompatibility: [SafariExtensionNativeMessagingAdapterCompatibilityStatus]
    let globalClassifications: [SafariExtensionNativeMessagingClassification]
    let suppressionReport: SafariExtensionNativeMessagingSuppressionReport
    let sdkProbeNote: String
    let delegateMethodsRegistered: Bool
    let registeredAdapterIdentifiers: [String]
}
