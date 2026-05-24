//
//  ChromeMV3LiveNormalTabAttachmentObservability.swift
//  Sumi
//
//  DEBUG/internal diagnostics for empty-controller normal-tab attachment.
//  This file records decisions only; it does not create extension objects,
//  contexts, scripts, bundles, native ports, or background work.
//

import Foundation

@available(macOS 15.5, *)
struct ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata:
    Codable,
    Equatable,
    Sendable
{
    var tabIdentifier: String?
    var tabDiagnosticIdentifier: String?
    var windowIdentifier: String?
    var profileIdentifier: String?
    var creationReason: String

    init(
        tabIdentifier: UUID? = nil,
        tabDiagnosticIdentifier: String? = nil,
        windowIdentifier: UUID? = nil,
        profileIdentifier: UUID? = nil,
        creationReason: String = "unspecified"
    ) {
        let resolvedTabIdentifier = tabIdentifier?.uuidString
        self.tabIdentifier = resolvedTabIdentifier
        self.tabDiagnosticIdentifier =
            tabDiagnosticIdentifier ?? resolvedTabIdentifier
        self.windowIdentifier = windowIdentifier?.uuidString
        self.profileIdentifier = profileIdentifier?.uuidString
        self.creationReason = creationReason
    }
}

@available(macOS 15.5, *)
enum ChromeMV3DebugAttachedWebViewLifecycleState:
    String,
    Codable,
    Sendable
{
    case unaffected
    case attached
    case staleNeedsRecreation
    case pendingRecreation
}

@available(macOS 15.5, *)
struct ChromeMV3DebugAttachedWebViewRecreationPlan:
    Codable,
    Equatable,
    Sendable
{
    var recreationRequired: Bool
    var recreationReason: String?
    var safeFutureRecreationEntryPoint: String?
    var userVisibleReloadOrRecreatePolicy: String

    static let unaffected = ChromeMV3DebugAttachedWebViewRecreationPlan(
        recreationRequired: false,
        recreationReason: nil,
        safeFutureRecreationEntryPoint: nil,
        userVisibleReloadOrRecreatePolicy: "deferred"
    )

    static func deferred(
        trigger: ChromeMV3EmptyControllerTeardownTrigger
    ) -> ChromeMV3DebugAttachedWebViewRecreationPlan {
        ChromeMV3DebugAttachedWebViewRecreationPlan(
            recreationRequired: true,
            recreationReason:
                "DEBUG Chrome MV3 empty-controller gate closed via \(trigger.rawValue); already-created WKWebViews require recreation before they can be considered unattached.",
            safeFutureRecreationEntryPoint:
                "Tab.makeNormalTabWebView(reason:) via Tab.setupWebView() or WebViewCoordinator recreation paths",
            userVisibleReloadOrRecreatePolicy: "deferred"
        )
    }
}

@available(macOS 15.5, *)
struct ChromeMV3LiveNormalTabAttachmentDecisionRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequenceNumber: Int
    var tabIdentifier: String?
    var tabDiagnosticIdentifier: String?
    var windowIdentifier: String?
    var profileIdentifier: String?
    var creationReason: String
    var surface: ChromeMV3WebViewSurface
    var extensionsModuleEnabled: Bool
    var profileHostEnabled: Bool
    var emptyControllerState: ChromeMV3EmptyControllerOwnerState
    var emptyControllerOwnerPresent: Bool
    var emptyControllerExists: Bool
    var explicitInternalNormalTabAttachmentAllowed: Bool
    var gateDecision: ChromeMV3NormalTabConfigurationAttachmentGateDecision
    var attachmentRequested: Bool
    var normalTabConfigurationAttached: Bool
    var auxiliaryConfigurationAttached: Bool
    var attachedControllerMatchesOwner: Bool
    var attachedControllerIdentity: String?
    var lifecycleState: ChromeMV3DebugAttachedWebViewLifecycleState
    var recreationPlan: ChromeMV3DebugAttachedWebViewRecreationPlan
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var contextLoadCalled: Bool
    var webExtensionCreated: Bool
    var webExtensionContextCreated: Bool
    var generatedExtensionBundleLoaded: Bool
    var nativeMessagingLaunched: Bool
    var nativeMessagingPortCount: Int
    var generatedArtifactsDeleted: Bool
    var websiteDataCleared: Bool
    var teardownTrigger: ChromeMV3EmptyControllerTeardownTrigger?
}

@available(macOS 15.5, *)
struct ChromeMV3LiveNormalTabAttachmentRecorderSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var recentDecisions: [ChromeMV3LiveNormalTabAttachmentDecisionRecord]
    var attachedConfigurationCount: Int
    var createdAttachedWebViewCount: Int
    var staleOrNeedsRecreationCount: Int
    var attachedTabDiagnosticIdentifiers: [String]
    var staleOrNeedsRecreationTabDiagnosticIdentifiers: [String]
    var accidentallyAttachedAuxiliarySurface: Bool
    var auxiliaryAttachmentSequenceNumbers: [Int]
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var contextCount: Int
    var contextLoadCalled: Bool
    var webExtensionCreated: Bool
    var webExtensionContextCreated: Bool
    var generatedExtensionBundleLoaded: Bool
    var nativeMessagingLaunched: Bool
    var generatedArtifactsDeleted: Bool
    var websiteDataCleared: Bool

    static let empty = ChromeMV3LiveNormalTabAttachmentRecorderSnapshot(
        recentDecisions: [],
        attachedConfigurationCount: 0,
        createdAttachedWebViewCount: 0,
        staleOrNeedsRecreationCount: 0,
        attachedTabDiagnosticIdentifiers: [],
        staleOrNeedsRecreationTabDiagnosticIdentifiers: [],
        accidentallyAttachedAuxiliarySurface: false,
        auxiliaryAttachmentSequenceNumbers: [],
        runtimeLoadable: false,
        canLoadContextNow: false,
        contextCount: 0,
        contextLoadCalled: false,
        webExtensionCreated: false,
        webExtensionContextCreated: false,
        generatedExtensionBundleLoaded: false,
        nativeMessagingLaunched: false,
        generatedArtifactsDeleted: false,
        websiteDataCleared: false
    )
}

@available(macOS 15.5, *)
struct ChromeMV3LiveNormalTabAttachmentRecorder {
    private let recordLimit: Int
    private var nextSequenceNumber = 1
    private(set) var recentDecisions:
        [ChromeMV3LiveNormalTabAttachmentDecisionRecord] = []

    init(recordLimit: Int = 50) {
        self.recordLimit = max(1, recordLimit)
    }

    @discardableResult
    mutating func recordDecision(
        diagnostics: ChromeMV3NormalTabConfigurationAttachmentDiagnostics,
        emptyControllerState: ChromeMV3EmptyControllerOwnerState
    ) -> Int {
        let sequenceNumber = nextSequenceNumber
        nextSequenceNumber += 1

        var record = ChromeMV3LiveNormalTabAttachmentDecisionRecord(
            sequenceNumber: sequenceNumber,
            tabIdentifier: diagnostics.tabIdentifier,
            tabDiagnosticIdentifier: diagnostics.tabDiagnosticIdentifier,
            windowIdentifier: diagnostics.windowIdentifier,
            profileIdentifier: diagnostics.profileIdentifier,
            creationReason: diagnostics.creationReason,
            surface: diagnostics.targetSurface,
            extensionsModuleEnabled:
                diagnostics.gateDecision.input.extensionsModuleEnabled,
            profileHostEnabled:
                diagnostics.gateDecision.input.profileHostEnabled,
            emptyControllerState: emptyControllerState,
            emptyControllerOwnerPresent:
                diagnostics.emptyControllerOwnerPresent,
            emptyControllerExists:
                diagnostics.gateDecision.input.emptyControllerExists,
            explicitInternalNormalTabAttachmentAllowed:
                diagnostics.explicitInternalNormalTabAttachmentAllowed,
            gateDecision: diagnostics.gateDecision,
            attachmentRequested: diagnostics.attachmentRequested,
            normalTabConfigurationAttached:
                diagnostics.normalTabConfigurationAttached,
            auxiliaryConfigurationAttached:
                diagnostics.auxiliaryConfigurationAttached,
            attachedControllerMatchesOwner:
                diagnostics.attachedControllerMatchesOwner,
            attachedControllerIdentity:
                diagnostics.attachedControllerIdentity,
            lifecycleState: .unaffected,
            recreationPlan: .unaffected,
            runtimeLoadable: diagnostics.runtimeLoadable,
            canLoadContextNow: diagnostics.canLoadContextNow,
            contextCount: diagnostics.contextCount,
            loadedExtensionCount: diagnostics.loadedExtensionCount,
            contextLoadCalled: diagnostics.contextLoadCalled,
            webExtensionCreated: diagnostics.webExtensionCreated,
            webExtensionContextCreated:
                diagnostics.webExtensionContextCreated,
            generatedExtensionBundleLoaded:
                diagnostics.generatedExtensionBundleLoaded,
            nativeMessagingLaunched: diagnostics.nativeMessagingLaunched,
            nativeMessagingPortCount:
                diagnostics.nativeMessagingPortCount,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false,
            teardownTrigger: nil
        )

        if diagnostics.normalTabConfigurationAttached {
            record.lifecycleState = .unaffected
        }

        recentDecisions.append(record)
        trimToLimit()
        return sequenceNumber
    }

    mutating func markCreatedWebView(sequenceNumber: Int) {
        guard let index = recentDecisions.firstIndex(where: {
            $0.sequenceNumber == sequenceNumber
        }) else { return }
        guard recentDecisions[index].normalTabConfigurationAttached else {
            return
        }
        recentDecisions[index].lifecycleState = .attached
        recentDecisions[index].recreationPlan = .unaffected
    }

    mutating func markGateClosed(
        trigger: ChromeMV3EmptyControllerTeardownTrigger
    ) {
        for index in recentDecisions.indices {
            guard recentDecisions[index].lifecycleState == .attached else {
                continue
            }
            recentDecisions[index].lifecycleState = .staleNeedsRecreation
            recentDecisions[index].recreationPlan = .deferred(trigger: trigger)
            recentDecisions[index].teardownTrigger = trigger
        }
    }

    func snapshot() -> ChromeMV3LiveNormalTabAttachmentRecorderSnapshot {
        let attachedConfigurationRecords = recentDecisions.filter {
            $0.normalTabConfigurationAttached
        }
        let createdAttachedWebViewRecords = recentDecisions.filter {
            $0.lifecycleState == .attached
        }
        let staleRecords = recentDecisions.filter {
            $0.lifecycleState == .staleNeedsRecreation
                || $0.lifecycleState == .pendingRecreation
                || $0.recreationPlan.recreationRequired
        }
        let auxiliaryAttachmentRecords = recentDecisions.filter {
            $0.auxiliaryConfigurationAttached
        }

        return ChromeMV3LiveNormalTabAttachmentRecorderSnapshot(
            recentDecisions: recentDecisions,
            attachedConfigurationCount: attachedConfigurationRecords.count,
            createdAttachedWebViewCount: createdAttachedWebViewRecords.count,
            staleOrNeedsRecreationCount: staleRecords.count,
            attachedTabDiagnosticIdentifiers:
                uniqueSortedDiagnosticIdentifiers(
                    createdAttachedWebViewRecords
                ),
            staleOrNeedsRecreationTabDiagnosticIdentifiers:
                uniqueSortedDiagnosticIdentifiers(staleRecords),
            accidentallyAttachedAuxiliarySurface:
                auxiliaryAttachmentRecords.isEmpty == false,
            auxiliaryAttachmentSequenceNumbers:
                auxiliaryAttachmentRecords.map(\.sequenceNumber).sorted(),
            runtimeLoadable: recentDecisions.contains {
                $0.runtimeLoadable
            },
            canLoadContextNow: recentDecisions.contains {
                $0.canLoadContextNow
            },
            contextCount: recentDecisions.map(\.contextCount).max() ?? 0,
            contextLoadCalled: recentDecisions.contains {
                $0.contextLoadCalled
            },
            webExtensionCreated: recentDecisions.contains {
                $0.webExtensionCreated
            },
            webExtensionContextCreated: recentDecisions.contains {
                $0.webExtensionContextCreated
            },
            generatedExtensionBundleLoaded: recentDecisions.contains {
                $0.generatedExtensionBundleLoaded
            },
            nativeMessagingLaunched: recentDecisions.contains {
                $0.nativeMessagingLaunched
            },
            generatedArtifactsDeleted: recentDecisions.contains {
                $0.generatedArtifactsDeleted
            },
            websiteDataCleared: recentDecisions.contains {
                $0.websiteDataCleared
            }
        )
    }

    private mutating func trimToLimit() {
        guard recentDecisions.count > recordLimit else { return }
        recentDecisions.removeFirst(recentDecisions.count - recordLimit)
    }

    private func uniqueSortedDiagnosticIdentifiers(
        _ records: [ChromeMV3LiveNormalTabAttachmentDecisionRecord]
    ) -> [String] {
        Array(
            Set(
                records.compactMap(\.tabDiagnosticIdentifier)
                    .filter { $0.isEmpty == false }
            )
        )
        .sorted()
    }
}
