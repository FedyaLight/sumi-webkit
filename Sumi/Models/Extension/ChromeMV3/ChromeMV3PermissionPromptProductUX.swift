//
//  ChromeMV3PermissionPromptProductUX.swift
//  Sumi
//
//  Developer-preview Chrome MV3 permission prompt model and presenter
//  abstraction. This file does not install public runtime support, silently
//  grant permissions, attach content scripts, wake service workers, launch
//  native hosts, poll, or schedule timers.
//

import CryptoKit
import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

enum ChromeMV3PermissionPromptBlockedReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case developerPreviewGateBlocked
    case disabledExtension
    case disabledModule
    case missingPresenter
    case missingUserGesture
    case productGateBlocked
    case requestAlreadySatisfied
    case requestBlockedByPolicy
    case requestInvalid
    case requestNotDeclaredOptional
    case unsupportedPermission

    static func < (
        lhs: ChromeMV3PermissionPromptBlockedReason,
        rhs: ChromeMV3PermissionPromptBlockedReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var diagnostic: String {
        switch self {
        case .developerPreviewGateBlocked:
            return "Developer-preview permission prompt gate is closed."
        case .disabledExtension:
            return "The extension is disabled; permission prompts are blocked."
        case .disabledModule:
            return "The extensions module is disabled; permission prompts are blocked."
        case .missingPresenter:
            return "No developer-preview permission prompt presenter is installed."
        case .missingUserGesture:
            return "chrome.permissions.request requires a real user gesture before prompting."
        case .productGateBlocked:
            return "Public product permission prompts remain unavailable."
        case .requestAlreadySatisfied:
            return "The requested permission set is already granted."
        case .requestBlockedByPolicy:
            return "The request is blocked by permission policy."
        case .requestInvalid:
            return "The request contains invalid permission input."
        case .requestNotDeclaredOptional:
            return "The requested permission or origin is not declared optional."
        case .unsupportedPermission:
            return "The requested permission is unsupported by this developer-preview runtime."
        }
    }
}

struct ChromeMV3PermissionPromptGateRecord:
    Codable,
    Equatable,
    Sendable
{
    var permissionPromptAvailableInDeveloperPreview: Bool
    var permissionPromptAvailableInPublicProduct: Bool
    var hostPermissionPromptAvailable: Bool
    var optionalPermissionPromptAvailable: Bool
    var activeTabUXAvailableInDeveloperPreview: Bool
    var activeTabUXAvailableInPublicProduct: Bool
    var silentGrantAllowed: Bool
    var permissionPromptBlockedReason: String?
    var blockers: [ChromeMV3PermissionPromptBlockedReason]
    var diagnostics: [String]

    var canPromptDeveloperPreview: Bool {
        permissionPromptAvailableInDeveloperPreview
            && permissionPromptAvailableInPublicProduct == false
            && silentGrantAllowed == false
            && blockers.isEmpty
    }

    static func evaluate(
        moduleEnabled: Bool,
        extensionEnabled: Bool,
        developerPreviewGate: Bool,
        publicProductGate: Bool = false
    ) -> ChromeMV3PermissionPromptGateRecord {
        var blockers: [ChromeMV3PermissionPromptBlockedReason] = []
        if moduleEnabled == false {
            blockers.append(.disabledModule)
        }
        if extensionEnabled == false {
            blockers.append(.disabledExtension)
        }
        if developerPreviewGate == false {
            blockers.append(.developerPreviewGateBlocked)
        }
        if publicProductGate {
            blockers.append(.productGateBlocked)
        }
        let available = moduleEnabled
            && extensionEnabled
            && developerPreviewGate
            && publicProductGate == false
        let uniqueBlockers = Array(Set(blockers)).sorted()
        return ChromeMV3PermissionPromptGateRecord(
            permissionPromptAvailableInDeveloperPreview: available,
            permissionPromptAvailableInPublicProduct: false,
            hostPermissionPromptAvailable: available,
            optionalPermissionPromptAvailable: available,
            activeTabUXAvailableInDeveloperPreview: available,
            activeTabUXAvailableInPublicProduct: false,
            silentGrantAllowed: false,
            permissionPromptBlockedReason:
                uniqueBlockers.first?.diagnostic,
            blockers: uniqueBlockers,
            diagnostics:
                uniqueSortedPermissionPrompt(
                    uniqueBlockers.map(\.diagnostic)
                        + [
                            available
                                ? "Developer-preview permission prompt UX is available for explicit requests."
                                : "Developer-preview permission prompt UX is blocked.",
                            "Public product permission prompt UX remains unavailable.",
                            "Public product activeTab UX remains unavailable.",
                            "silentGrantAllowed is false.",
                        ]
                )
        )
    }
}

enum ChromeMV3PermissionPromptSourceSurface:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionClick
    case contentScriptRequest
    case extensionManager
    case options
    case popup
    case testFixture

    static func < (
        lhs: ChromeMV3PermissionPromptSourceSurface,
        rhs: ChromeMV3PermissionPromptSourceSurface
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionPromptItemKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case apiPermission
    case hostPermission
    case optionalOrigin

    static func < (
        lhs: ChromeMV3PermissionPromptItemKind,
        rhs: ChromeMV3PermissionPromptItemKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionPromptResultDisposition:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case accepted
    case blocked
    case denied
    case dismissed
    case unavailable

    static func < (
        lhs: ChromeMV3PermissionPromptResultDisposition,
        rhs: ChromeMV3PermissionPromptResultDisposition
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var grantsPermission: Bool {
        self == .accepted
    }
}

enum ChromeMV3PermissionPromptLifecycleStage:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case promptCreated
    case promptPresented
    case accepted
    case denied
    case dismissed
    case blocked
    case resultPersisted
    case downstreamInvalidated

    static func < (
        lhs: ChromeMV3PermissionPromptLifecycleStage,
        rhs: ChromeMV3PermissionPromptLifecycleStage
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionPromptLifecycleRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var requestID: String
    var sequence: Int
    var stage: ChromeMV3PermissionPromptLifecycleStage
    var sourceSurface: ChromeMV3PermissionPromptSourceSurface
    var resultDisposition: ChromeMV3PermissionPromptResultDisposition?
    var diagnostics: [String]

    init(
        request: ChromeMV3PermissionPromptRequest,
        stage: ChromeMV3PermissionPromptLifecycleStage,
        resultDisposition: ChromeMV3PermissionPromptResultDisposition? = nil,
        diagnostics: [String] = []
    ) {
        self.requestID = request.id
        self.sequence = request.sequence
        self.stage = stage
        self.sourceSurface = request.sourceSurface
        self.resultDisposition = resultDisposition
        self.diagnostics = uniqueSortedPermissionPrompt(
            diagnostics
                + [
                    "Permission prompt lifecycle stage: \(stage.rawValue).",
                    "No scheduled work was used for prompt lifecycle tracking.",
                ]
        )
        self.id = stableIDPermissionPrompt(
            prefix: "permission-prompt-lifecycle",
            parts: [
                request.profileID,
                request.extensionID,
                request.id,
                String(request.sequence),
                stage.rawValue,
                resultDisposition?.rawValue ?? "no-result",
            ]
        )
    }
}

struct ChromeMV3PermissionPromptItemRecord:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PermissionPromptItemKind
    var value: String
    var currentStatus: ChromeMV3PermissionBrokerDecisionStatus
    var declaredRequired: Bool
    var declaredOptional: Bool
    var granted: Bool
    var denied: Bool
    var revoked: Bool
    var unsupported: Bool
    var deferred: Bool
    var wouldGrantIfUserAccepted: Bool
    var diagnostics: [String]
}

struct ChromeMV3PermissionPromptEligibility:
    Codable,
    Equatable,
    Sendable
{
    var canPrompt: Bool
    var requiresUserGesture: Bool
    var userGesturePresent: Bool
    var blockedReasons: [ChromeMV3PermissionPromptBlockedReason]
    var diagnostics: [String]
}

struct ChromeMV3PermissionPromptRequest:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var sequence: Int
    var extensionID: String
    var profileID: String
    var extensionName: String
    var sourceSurface: ChromeMV3PermissionPromptSourceSurface
    var requestedAPIPermissions: [String]
    var requestedHostPermissions: [String]
    var requestedOptionalOrigins: [String]
    var currentGrantState:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var declaredStatus: [ChromeMV3PermissionPromptItemRecord]
    var promptEligibility: ChromeMV3PermissionPromptEligibility
    var gateRecord: ChromeMV3PermissionPromptGateRecord
    var diagnostics: [String]

    static func make(
        sequence: Int,
        extensionName: String,
        sourceSurface: ChromeMV3PermissionPromptSourceSurface,
        input: ChromeMV3PermissionsAPIRequestInput,
        requestResult: ChromeMV3PermissionsAPIRequestResult,
        permissionStore: ChromeMV3PermissionDecisionStore,
        gateRecord: ChromeMV3PermissionPromptGateRecord
    ) -> ChromeMV3PermissionPromptRequest {
        let snapshot = permissionStore.exportSnapshot()
        let itemRecords = requestResult.itemDecisions.map { decision in
            itemRecord(decision)
        }
        let blocked = blockedReasons(
            requestResult: requestResult,
            gateRecord: gateRecord
        )
        let canPrompt =
            gateRecord.canPromptDeveloperPreview
                && requestResult.wouldRequirePrompt
                && blocked.isEmpty
        let eligibility = ChromeMV3PermissionPromptEligibility(
            canPrompt: canPrompt,
            requiresUserGesture: requestResult.wouldRequirePrompt,
            userGesturePresent:
                requestResult.input.userGestureModeled,
            blockedReasons: blocked,
            diagnostics:
                uniqueSortedPermissionPrompt(
                    blocked.map(\.diagnostic)
                        + [
                            canPrompt
                                ? "Permission prompt can be presented."
                                : "Permission prompt cannot be presented.",
                        ]
                )
        )
        let id = stableIDPermissionPrompt(
            prefix: "permission-prompt-request",
            parts: [
                input.profileID,
                input.extensionID,
                sourceSurface.rawValue,
                String(sequence),
                requestResult.input.permissions.joined(separator: ","),
                requestResult.input.origins.joined(separator: ","),
                blocked.map(\.rawValue).joined(separator: ","),
            ]
        )
        return ChromeMV3PermissionPromptRequest(
            id: id,
            sequence: sequence,
            extensionID: input.extensionID,
            profileID: input.profileID,
            extensionName:
                extensionName.isEmpty ? input.extensionID : extensionName,
            sourceSurface: sourceSurface,
            requestedAPIPermissions: requestResult.input.permissions,
            requestedHostPermissions:
                requestResult.input.origins.filter {
                    $0 == "<all_urls>" || $0.contains("://")
                },
            requestedOptionalOrigins:
                requestResult.itemDecisions
                .filter {
                    $0.kind == .origin
                        && $0.classification == .requestableOptionalOrigin
                }
                .map(\.value)
                .sorted(),
            currentGrantState: snapshot.summary,
            declaredStatus: itemRecords,
            promptEligibility: eligibility,
            gateRecord: gateRecord,
            diagnostics:
                uniqueSortedPermissionPrompt(
                    gateRecord.diagnostics
                        + requestResult.diagnostics
                        + eligibility.diagnostics
                )
        )
    }

    func result(
        _ disposition: ChromeMV3PermissionPromptResultDisposition,
        diagnostics extraDiagnostics: [String] = []
    ) -> ChromeMV3PermissionPromptResultRecord {
        ChromeMV3PermissionPromptResultRecord(
            requestID: id,
            sequence: sequence,
            extensionID: extensionID,
            profileID: profileID,
            sourceSurface: sourceSurface,
            disposition: disposition,
            requestedAPIPermissions: requestedAPIPermissions,
            requestedHostPermissions: requestedHostPermissions,
            requestedOptionalOrigins: requestedOptionalOrigins,
            diagnostics:
                uniqueSortedPermissionPrompt(
                    diagnostics
                        + extraDiagnostics
                        + [
                            "Permission prompt result: \(disposition.rawValue).",
                            disposition.grantsPermission
                                ? "Grant may be applied only after explicit user acceptance."
                                : "No permission grant is applied for this prompt result.",
                        ]
                )
        )
    }

    private static func itemRecord(
        _ decision: ChromeMV3PermissionsAPIRequestItemDecision
    ) -> ChromeMV3PermissionPromptItemRecord {
        let status: ChromeMV3PermissionBrokerDecisionStatus
        switch decision.classification {
        case .alreadyGranted:
            status = .allowed
        case .requestableOptionalOrigin, .requestableOptionalPermission:
            status = .promptRequired
        case .deniedByPolicy:
            status = .denied
        case .deferredPermission:
            status = .deferred
        case .unsupportedPermission:
            status = .unsupported
        default:
            status = .blocked
        }
        let kind: ChromeMV3PermissionPromptItemKind
        switch decision.kind {
        case .apiPermission:
            kind = .apiPermission
        case .origin:
            kind = .optionalOrigin
        }
        return ChromeMV3PermissionPromptItemRecord(
            kind: kind,
            value: decision.value,
            currentStatus: status,
            declaredRequired: false,
            declaredOptional: decision.declaredOptional,
            granted: decision.alreadyGranted,
            denied: decision.deniedByPolicy,
            revoked: decision.revokedInStore,
            unsupported: decision.unsupported,
            deferred: decision.deferred,
            wouldGrantIfUserAccepted: decision.wouldGrantIfUserAccepted,
            diagnostics: decision.diagnostics
        )
    }

    private static func blockedReasons(
        requestResult: ChromeMV3PermissionsAPIRequestResult,
        gateRecord: ChromeMV3PermissionPromptGateRecord
    ) -> [ChromeMV3PermissionPromptBlockedReason] {
        var blockers = gateRecord.blockers
        let classifications = requestResult.itemDecisions.map(\.classification)
        if requestResult.input.inputIssues.isEmpty == false {
            blockers.append(.requestInvalid)
        }
        if classifications.contains(.missingUserGesture) {
            blockers.append(.missingUserGesture)
        }
        if classifications.contains(.notDeclaredOptional) {
            blockers.append(.requestNotDeclaredOptional)
        }
        if classifications.contains(.unsupportedPermission)
            || classifications.contains(.deferredPermission)
        {
            blockers.append(.unsupportedPermission)
        }
        if classifications.contains(.deniedByPolicy)
            || classifications.contains(.disabledModule)
            || requestResult.wouldBeDeniedByModel
        {
            blockers.append(.requestBlockedByPolicy)
        }
        if requestResult.wouldBeAllowedByModel {
            blockers.append(.requestAlreadySatisfied)
        }
        return Array(Set(blockers)).sorted()
    }
}

struct ChromeMV3PermissionPromptResultRecord:
    Codable,
    Equatable,
    Sendable
{
    var requestID: String
    var sequence: Int
    var extensionID: String
    var profileID: String
    var sourceSurface: ChromeMV3PermissionPromptSourceSurface
    var disposition: ChromeMV3PermissionPromptResultDisposition
    var requestedAPIPermissions: [String]
    var requestedHostPermissions: [String]
    var requestedOptionalOrigins: [String]
    var diagnostics: [String]
}

struct ChromeMV3DeveloperPreviewPermissionPromptViewModel:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String { request.id }
    var request: ChromeMV3PermissionPromptRequest
    var title: String
    var permissionSummary: [String]
    var hostSummary: [String]
    var riskExplanation: String
    var sourceDescription: String
    var acceptTitle: String
    var denyTitle: String
    var dismissTitle: String
    var rememberAvailable: Bool
    var diagnostics: [String]

    static func make(
        request: ChromeMV3PermissionPromptRequest
    ) -> ChromeMV3DeveloperPreviewPermissionPromptViewModel {
        let permissions = request.requestedAPIPermissions
        let hosts = request.requestedHostPermissions
            + request.requestedOptionalOrigins
        return ChromeMV3DeveloperPreviewPermissionPromptViewModel(
            request: request,
            title: "\(request.extensionName) requests additional access",
            permissionSummary:
                permissions.isEmpty
                    ? ["No API permissions requested."]
                    : permissions,
            hostSummary:
                hosts.isEmpty
                    ? ["No host origins requested."]
                    : Array(Set(hosts)).sorted(),
            riskExplanation:
                hosts.isEmpty
                    ? "This may enable additional extension API capability in the developer preview."
                    : "This may allow the extension to read or interact with matching page data while the developer-preview runtime is enabled.",
            sourceDescription:
                "Requested from \(request.sourceSurface.rawValue).",
            acceptTitle: "Allow",
            denyTitle: "Deny",
            dismissTitle: "Dismiss",
            rememberAvailable: false,
            diagnostics:
                uniqueSortedPermissionPrompt(
                    request.diagnostics
                        + [
                            "Remember is unavailable because this developer-preview policy persists only explicit grant/revoke records.",
                        ]
                )
        )
    }
}

struct ChromeMV3DeveloperPreviewPermissionPromptView: View {
    let viewModel: ChromeMV3DeveloperPreviewPermissionPromptViewModel
    var onAccept: (() -> Void)?
    var onDeny: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.title)
                        .font(.headline)
                    Text(viewModel.sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(viewModel.riskExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            promptGroup(title: "Permissions", rows: viewModel.permissionSummary)
            promptGroup(title: "Hosts", rows: viewModel.hostSummary)
            HStack {
                Button(viewModel.dismissTitle) {
                    onDismiss?()
                }
                Spacer()
                Button(viewModel.denyTitle) {
                    onDeny?()
                }
                Button(viewModel.acceptTitle) {
                    onAccept?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(minWidth: 360, maxWidth: 520, alignment: .leading)
    }

    private func promptGroup(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(row)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

protocol ChromeMV3PermissionPromptPresenting: AnyObject {
    func presentChromeMV3PermissionPrompt(
        _ request: ChromeMV3PermissionPromptRequest
    ) -> ChromeMV3PermissionPromptResultRecord
}

final class ChromeMV3UnavailablePermissionPromptPresenter:
    ChromeMV3PermissionPromptPresenting
{
    func presentChromeMV3PermissionPrompt(
        _ request: ChromeMV3PermissionPromptRequest
    ) -> ChromeMV3PermissionPromptResultRecord {
        request.result(
            .unavailable,
            diagnostics: [
                "No developer-preview permission prompt presenter is installed.",
            ]
        )
    }
}

final class ChromeMV3TestPermissionPromptPresenter:
    ChromeMV3PermissionPromptPresenting
{
    private let disposition: ChromeMV3PermissionPromptResultDisposition
    private(set) var presentedRequests:
        [ChromeMV3PermissionPromptRequest] = []
    private(set) var resultRecords:
        [ChromeMV3PermissionPromptResultRecord] = []

    init(disposition: ChromeMV3PermissionPromptResultDisposition) {
        self.disposition = disposition
    }

    func presentChromeMV3PermissionPrompt(
        _ request: ChromeMV3PermissionPromptRequest
    ) -> ChromeMV3PermissionPromptResultRecord {
        presentedRequests.append(request)
        let result = request.result(
            disposition,
            diagnostics: [
                "Explicit test presenter returned \(disposition.rawValue).",
            ]
        )
        resultRecords.append(result)
        return result
    }
}

enum ChromeMV3PermissionEventDispatchOutcome:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case delivered
    case skipped
    case blocked

    static func < (
        lhs: ChromeMV3PermissionEventDispatchOutcome,
        rhs: ChromeMV3PermissionEventDispatchOutcome
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionEventDispatchTargetState:
    Codable,
    Equatable,
    Sendable
{
    var surfaceID: String
    var profileID: String
    var extensionID: String
    var surface: ChromeMV3ProductPopupOptionsSurface
    var open: Bool
    var onAddedListenerCount: Int
    var onRemovedListenerCount: Int
    var diagnostics: [String]

    func listenerCount(
        for eventKind: ChromeMV3PermissionsAPIEventKind
    ) -> Int {
        switch eventKind {
        case .onAdded:
            return onAddedListenerCount
        case .onRemoved:
            return onRemovedListenerCount
        }
    }
}

struct ChromeMV3PermissionEventDispatchRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var sequence: Int
    var eventPayload: ChromeMV3PermissionsAPIEventPayload
    var sourceSurfaceID: String?
    var openTargetCount: Int
    var listenerCount: Int
    var deliveredSurfaceIDs: [String]
    var skippedSurfaceIDs: [String]
    var blockedSurfaceIDs: [String]
    var outcome: ChromeMV3PermissionEventDispatchOutcome
    var reason: String
    var serviceWorkerWakeAttempted: Bool
    var hiddenExtensionPageCreated: Bool
    var diagnostics: [String]
}

protocol ChromeMV3PermissionEventDispatching: AnyObject {
    var permissionEventDispatchRecords:
        [ChromeMV3PermissionEventDispatchRecord] { get }
    var permissionEventDispatchTargets:
        [ChromeMV3PermissionEventDispatchTargetState] { get }

    func registerChromeMV3PermissionEventPage(
        surfaceID: String,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        dispatchHandler:
            ((ChromeMV3PermissionsAPIEventPayload) -> Bool)?
    )

    func updateChromeMV3PermissionEventListenerCount(
        surfaceID: String,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        eventKind: ChromeMV3PermissionsAPIEventKind,
        listenerCount: Int
    )

    func unregisterChromeMV3PermissionEventPage(surfaceID: String)

    @discardableResult
    func dispatchChromeMV3PermissionEvent(
        _ payload: ChromeMV3PermissionsAPIEventPayload,
        sourceSurfaceID: String?
    ) -> ChromeMV3PermissionEventDispatchRecord
}

final class ChromeMV3PermissionEventDispatchRegistry:
    ChromeMV3PermissionEventDispatching
{
    private struct Target {
        var state: ChromeMV3PermissionEventDispatchTargetState
        var dispatchHandler:
            ((ChromeMV3PermissionsAPIEventPayload) -> Bool)?
    }

    private var targets: [String: Target] = [:]
    private(set) var permissionEventDispatchRecords:
        [ChromeMV3PermissionEventDispatchRecord] = []
    private var nextSequence = 1

    var permissionEventDispatchTargets:
        [ChromeMV3PermissionEventDispatchTargetState]
    {
        targets.values.map(\.state).sorted {
            if $0.profileID != $1.profileID {
                return $0.profileID < $1.profileID
            }
            if $0.extensionID != $1.extensionID {
                return $0.extensionID < $1.extensionID
            }
            return $0.surfaceID < $1.surfaceID
        }
    }

    init() {}

    func registerChromeMV3PermissionEventPage(
        surfaceID: String,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        dispatchHandler:
            ((ChromeMV3PermissionsAPIEventPayload) -> Bool)? = nil
    ) {
        let normalizedID = surfaceID.isEmpty
            ? "\(profileID):\(extensionID):\(surface.rawValue)"
            : surfaceID
        var state = targets[normalizedID]?.state
            ?? ChromeMV3PermissionEventDispatchTargetState(
                surfaceID: normalizedID,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface,
                open: true,
                onAddedListenerCount: 0,
                onRemovedListenerCount: 0,
                diagnostics: []
            )
        state.open = true
        state.diagnostics = uniqueSortedPermissionPrompt(
            state.diagnostics
                + [
                    "Already-open popup/options page registered for safe permissions event dispatch.",
                ]
        )
        targets[normalizedID] = Target(
            state: state,
            dispatchHandler:
                dispatchHandler ?? targets[normalizedID]?.dispatchHandler
        )
    }

    func updateChromeMV3PermissionEventListenerCount(
        surfaceID: String,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        eventKind: ChromeMV3PermissionsAPIEventKind,
        listenerCount: Int
    ) {
        let normalizedID = surfaceID.isEmpty
            ? "\(profileID):\(extensionID):\(surface.rawValue)"
            : surfaceID
        registerChromeMV3PermissionEventPage(
            surfaceID: normalizedID,
            profileID: profileID,
            extensionID: extensionID,
            surface: surface,
            dispatchHandler: nil
        )
        guard var target = targets[normalizedID] else { return }
        switch eventKind {
        case .onAdded:
            target.state.onAddedListenerCount = max(0, listenerCount)
        case .onRemoved:
            target.state.onRemovedListenerCount = max(0, listenerCount)
        }
        target.state.diagnostics = uniqueSortedPermissionPrompt(
            target.state.diagnostics
                + [
                    "permissions.\(eventKind.rawValue) listener count updated for an already-open extension page.",
                ]
        )
        targets[normalizedID] = target
    }

    func unregisterChromeMV3PermissionEventPage(surfaceID: String) {
        guard var target = targets[surfaceID] else { return }
        target.state.open = false
        target.state.diagnostics = uniqueSortedPermissionPrompt(
            target.state.diagnostics
                + ["Popup/options page unregistered from permissions event dispatch."]
        )
        targets[surfaceID] = target
    }

    @discardableResult
    func dispatchChromeMV3PermissionEvent(
        _ payload: ChromeMV3PermissionsAPIEventPayload,
        sourceSurfaceID: String? = nil
    ) -> ChromeMV3PermissionEventDispatchRecord {
        let sequence = nextSequence
        nextSequence += 1
        let openTargets = targets.values.filter {
            $0.state.open
                && $0.state.profileID == payload.profileID
                && $0.state.extensionID == payload.extensionID
        }
        var delivered: [String] = []
        var skipped: [String] = []
        var blocked: [String] = []
        var listenerCount = 0
        var diagnostics: [String] = [
            "Permission event dispatch inspected already-open popup/options pages only.",
            "No service-worker wake was attempted for permissions.onAdded/onRemoved.",
            "No hidden extension page was created for permission event delivery.",
        ]

        for target in openTargets {
            let id = target.state.surfaceID
            if id == sourceSurfaceID {
                skipped.append(id)
                diagnostics.append(
                    "Source page \(id) receives the permission event through the API response payload."
                )
                continue
            }
            let count = target.state.listenerCount(for: payload.eventKind)
            listenerCount += count
            guard count > 0 else {
                skipped.append(id)
                diagnostics.append(
                    "Skipped \(id) because no permissions.\(payload.eventKind.rawValue) listener is registered."
                )
                continue
            }
            if target.dispatchHandler?(payload) ?? true {
                delivered.append(id)
                diagnostics.append(
                    "Delivered permissions.\(payload.eventKind.rawValue) to \(id)."
                )
            } else {
                blocked.append(id)
                diagnostics.append(
                    "Blocked permissions.\(payload.eventKind.rawValue) delivery to \(id)."
                )
            }
        }

        if openTargets.isEmpty {
            diagnostics.append(
                "No already-open popup/options page matched the permission event namespace."
            )
        }

        let outcome: ChromeMV3PermissionEventDispatchOutcome
        if blocked.isEmpty == false {
            outcome = .blocked
        } else if delivered.isEmpty == false {
            outcome = .delivered
        } else {
            outcome = .skipped
        }
        let reason: String
        switch outcome {
        case .delivered:
            reason = "Delivered to already-open extension page listener(s)."
        case .skipped:
            reason = "No eligible already-open listener required delivery."
        case .blocked:
            reason = "At least one already-open listener target blocked delivery."
        }
        let record = ChromeMV3PermissionEventDispatchRecord(
            id:
                stableIDPermissionPrompt(
                    prefix: "permission-event-dispatch",
                    parts: [
                        payload.profileID,
                        payload.extensionID,
                        payload.eventKind.rawValue,
                        String(sequence),
                        delivered.joined(separator: ","),
                        skipped.joined(separator: ","),
                        blocked.joined(separator: ","),
                    ]
                ),
            sequence: sequence,
            eventPayload: payload,
            sourceSurfaceID: sourceSurfaceID,
            openTargetCount: openTargets.count,
            listenerCount: listenerCount,
            deliveredSurfaceIDs: delivered.sorted(),
            skippedSurfaceIDs: skipped.sorted(),
            blockedSurfaceIDs: blocked.sorted(),
            outcome: outcome,
            reason: reason,
            serviceWorkerWakeAttempted: false,
            hiddenExtensionPageCreated: false,
            diagnostics: uniqueSortedPermissionPrompt(diagnostics)
        )
        permissionEventDispatchRecords.append(record)
        return record
    }
}

#if canImport(AppKit)
@MainActor
final class ChromeMV3AppHostedPermissionPromptPresenter:
    ChromeMV3PermissionPromptPresenting
{
    private let parentWindowProvider: () -> NSWindow?

    init(parentWindowProvider: @escaping () -> NSWindow? = { NSApp.keyWindow }) {
        self.parentWindowProvider = parentWindowProvider
    }

    nonisolated func presentChromeMV3PermissionPrompt(
        _ request: ChromeMV3PermissionPromptRequest
    ) -> ChromeMV3PermissionPromptResultRecord {
        guard Thread.isMainThread else {
            return request.result(
                .blocked,
                diagnostics: [
                    "App-hosted permission presenter requires the main thread and blocked presentation instead of guessing.",
                ]
            )
        }
        return MainActor.assumeIsolated {
            presentOnMainActor(request)
        }
    }

    private func presentOnMainActor(
        _ request: ChromeMV3PermissionPromptRequest
    ) -> ChromeMV3PermissionPromptResultRecord {
        guard request.gateRecord.canPromptDeveloperPreview,
              request.promptEligibility.canPrompt
        else {
            return request.result(
                .blocked,
                diagnostics: [
                    "App-hosted permission presenter refused to present because prompt gates are blocked.",
                ]
            )
        }

        var disposition = ChromeMV3PermissionPromptResultDisposition.dismissed
        var completed = false
        let complete: (ChromeMV3PermissionPromptResultDisposition) -> Void = {
            result in
            guard completed == false else { return }
            completed = true
            disposition = result
            NSApp.stopModal()
        }
        let viewModel =
            ChromeMV3DeveloperPreviewPermissionPromptViewModel.make(
                request: request
            )
        let view = ChromeMV3DeveloperPreviewPermissionPromptView(
            viewModel: viewModel,
            onAccept: { complete(.accepted) },
            onDeny: { complete(.denied) },
            onDismiss: { complete(.dismissed) }
        )
        let hostingController = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let delegate = ChromeMV3PermissionPromptPanelDelegate {
            complete(.dismissed)
        }
        panel.delegate = delegate
        panel.title = "Extension Permission Request"
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.center()
        let parentWindow = parentWindowProvider()
        parentWindow?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(parentWindow)
        NSApp.runModal(for: panel)
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        _ = delegate
        return request.result(
            disposition,
            diagnostics: [
                "App-hosted developer-preview permission prompt window returned \(disposition.rawValue).",
            ]
        )
    }
}

@MainActor
private final class ChromeMV3PermissionPromptPanelDelegate:
    NSObject,
    NSWindowDelegate
{
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose()
    }
}
#endif

struct ChromeMV3DeveloperPreviewPermissionStateRecord:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var updatedAt: Date
    var extensionID: String
    var profileID: String
    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    var promptGateRecord: ChromeMV3PermissionPromptGateRecord
    var promptRequests: [ChromeMV3PermissionPromptRequest]
    var promptResults: [ChromeMV3PermissionPromptResultRecord]
    var promptLifecycleRecords:
        [ChromeMV3PermissionPromptLifecycleRecord]
    var diagnostics: [String]

    init(
        schemaVersion: Int,
        updatedAt: Date,
        extensionID: String,
        profileID: String,
        permissionRuntimeSnapshot:
            ChromeMV3PermissionRuntimeStateOwnerSnapshot,
        promptGateRecord: ChromeMV3PermissionPromptGateRecord,
        promptRequests: [ChromeMV3PermissionPromptRequest],
        promptResults: [ChromeMV3PermissionPromptResultRecord],
        promptLifecycleRecords:
            [ChromeMV3PermissionPromptLifecycleRecord] = [],
        diagnostics: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.extensionID = extensionID
        self.profileID = profileID
        self.permissionRuntimeSnapshot = permissionRuntimeSnapshot
        self.promptGateRecord = promptGateRecord
        self.promptRequests = promptRequests
        self.promptResults = promptResults
        self.promptLifecycleRecords = promptLifecycleRecords
        self.diagnostics = diagnostics
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case extensionID
        case profileID
        case permissionRuntimeSnapshot
        case promptGateRecord
        case promptRequests
        case promptResults
        case promptLifecycleRecords
        case diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.extensionID = try container.decode(String.self, forKey: .extensionID)
        self.profileID = try container.decode(String.self, forKey: .profileID)
        self.permissionRuntimeSnapshot = try container.decode(
            ChromeMV3PermissionRuntimeStateOwnerSnapshot.self,
            forKey: .permissionRuntimeSnapshot
        )
        self.promptGateRecord = try container.decode(
            ChromeMV3PermissionPromptGateRecord.self,
            forKey: .promptGateRecord
        )
        self.promptRequests = try container.decode(
            [ChromeMV3PermissionPromptRequest].self,
            forKey: .promptRequests
        )
        self.promptResults = try container.decode(
            [ChromeMV3PermissionPromptResultRecord].self,
            forKey: .promptResults
        )
        self.promptLifecycleRecords =
            try container.decodeIfPresent(
                [ChromeMV3PermissionPromptLifecycleRecord].self,
                forKey: .promptLifecycleRecords
            ) ?? []
        self.diagnostics = try container.decode(
            [String].self,
            forKey: .diagnostics
        )
    }
}

struct ChromeMV3DeveloperPreviewPermissionStateStore {
    var rootURL: URL
    var now: () -> Date
    var fileManager: FileManager

    init(
        rootURL: URL,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.now = now
        self.fileManager = fileManager
    }

    func loadRecord(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3DeveloperPreviewPermissionStateRecord? {
        let url = stateURL(profileID: profileID, extensionID: extensionID)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ChromeMV3DeveloperPreviewPermissionStateRecord.self,
            from: data
        )
    }

    func loadRuntimeOwner(
        profileID: String,
        extensionID: String,
        manifestSummary:
            ChromeMV3ExtensionManagerManifestSummaryViewState? = nil
    ) -> ChromeMV3PermissionRuntimeStateOwner {
        if let record = loadRecord(profileID: profileID, extensionID: extensionID) {
            return ChromeMV3PermissionRuntimeStateOwner(
                snapshot: record.permissionRuntimeSnapshot
            )
        }
        let permissions = manifestSummary?.permissions ?? []
        let optionalPermissions = manifestSummary?.optionalPermissions ?? []
        let hostPermissions = manifestSummary?.hostPermissions ?? []
        let optionalHostPermissions =
            manifestSummary?.optionalHostPermissions ?? []
        return ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: extensionID,
                            profileID: profileID,
                            declaredAPIPermissions: permissions,
                            declaredHostPermissions: hostPermissions,
                            optionalAPIPermissions: optionalPermissions,
                            optionalHostPermissions:
                                optionalHostPermissions
                        )
                )
        )
    }

    @discardableResult
    func save(
        owner: ChromeMV3PermissionRuntimeStateOwner,
        gateRecord: ChromeMV3PermissionPromptGateRecord,
        promptRequests: [ChromeMV3PermissionPromptRequest] = [],
        promptResults: [ChromeMV3PermissionPromptResultRecord] = [],
        promptLifecycleRecords:
            [ChromeMV3PermissionPromptLifecycleRecord] = [],
        diagnostics: [String] = []
    ) throws -> ChromeMV3DeveloperPreviewPermissionStateRecord {
        let snapshot = owner.snapshot
        let record = ChromeMV3DeveloperPreviewPermissionStateRecord(
            schemaVersion: 1,
            updatedAt: now(),
            extensionID: snapshot.namespace.extensionID,
            profileID: snapshot.namespace.profileID,
            permissionRuntimeSnapshot: snapshot,
            promptGateRecord: gateRecord,
            promptRequests: promptRequests.sorted {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                return $0.id < $1.id
            },
            promptResults: promptResults.sorted {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                return $0.requestID < $1.requestID
            },
            promptLifecycleRecords: promptLifecycleRecords.sorted {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                if $0.requestID != $1.requestID {
                    return $0.requestID < $1.requestID
                }
                return $0.stage < $1.stage
            },
            diagnostics:
                uniqueSortedPermissionPrompt(
                    diagnostics
                        + [
                            "Developer-preview permission state persisted as an internal sidecar record.",
                            "No public product runtime state was enabled.",
                        ]
                )
        )
        let url = stateURL(
            profileID: snapshot.namespace.profileID,
            extensionID: snapshot.namespace.extensionID
        )
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(record, to: url)
        return record
    }

    func stateURL(profileID: String, extensionID: String) -> URL {
        rootURL
            .appendingPathComponent("lifecycle", isDirectory: true)
            .appendingPathComponent("permission-state", isDirectory: true)
            .appendingPathComponent(safePermissionPromptPath(profileID), isDirectory: true)
            .appendingPathComponent(safePermissionPromptPath(extensionID), isDirectory: true)
            .appendingPathComponent("permission-state.json")
    }
}

struct ChromeMV3ActiveTabUXRequest:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: Int
    var url: String
    var sourceSurface: ChromeMV3PermissionPromptSourceSurface
    var explicitUserGesture: Bool
    var sequence: Int
}

enum ChromeMV3DeveloperPreviewActiveTabUX {
    static func grant(
        request: ChromeMV3ActiveTabUXRequest,
        gateRecord: ChromeMV3PermissionPromptGateRecord,
        owner: inout ChromeMV3PermissionRuntimeStateOwner
    ) -> ChromeMV3ActiveTabRuntimeGrantResult {
        guard gateRecord.activeTabUXAvailableInDeveloperPreview,
              gateRecord.activeTabUXAvailableInPublicProduct == false,
              request.explicitUserGesture
        else {
            let event = ChromeMV3ActiveTabGestureEvent(
                extensionID: request.extensionID,
                profileID: request.profileID,
                tabID: request.tabID,
                url: request.url,
                reason: .futureUserGesture,
                userGestureModeled: false,
                sequence: request.sequence
            )
            return owner.grantActiveTabFromGesture(event)
        }
        let reason: ChromeMV3ActiveTabGrantReason =
            request.sourceSurface == .actionClick
                || request.sourceSurface == .popup
                ? .actionClick
                : .futureUserGesture
        let event = ChromeMV3ActiveTabGestureEvent(
            extensionID: request.extensionID,
            profileID: request.profileID,
            tabID: request.tabID,
            url: request.url,
            reason: reason,
            userGestureModeled: true,
            sequence: request.sequence
        )
        return owner.grantActiveTabFromGesture(event)
    }
}

extension ChromeMV3JSBridgeSourceContext {
    var permissionPromptSourceSurface:
        ChromeMV3PermissionPromptSourceSurface
    {
        switch self {
        case .actionPopup:
            return .popup
        case .optionsPage:
            return .options
        case .contentScript:
            return .contentScriptRequest
        case .extensionPage, .serviceWorker, .testFixture:
            return .testFixture
        }
    }
}

private func uniqueSortedPermissionPrompt(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func safePermissionPromptPath(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_."))
    let mapped = value.unicodeScalars.map { scalar -> Character in
        allowed.contains(scalar) ? Character(scalar) : "_"
    }
    let result = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
    return result.isEmpty ? "default" : result
}

private func stableIDPermissionPrompt(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1f}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}
