//
//  SafariExtensionAutofillFillDiagnostics.swift
//  Sumi
//
//  DEBUG-only autofill fill-path diagnostic buckets for generic extension runtime.
//  Never logs usernames, passwords, credentials, tokens, cookies, or message bodies.
//

import Foundation
import WebKit

/// Precise fill-path observation buckets for controlled local autofill debugging.
enum SafariExtensionAutofillFillDiagnosticBucket: String, Codable, CaseIterable, Sendable {
    case popupSeesCurrentTab
    case credentialSuggested
    case fillActionStarted
    case contentScriptInjected
    case contentScriptMissing
    case frameResolved
    case frameMissing
    case scriptingExecuteRequested
    case scriptingExecuteSucceeded
    case scriptingExecuteFailed
    case activeTabGranted
    case activeTabDenied
    case hostPermissionGranted
    case hostPermissionDenied
    case webNavigationFramesAvailable
    case webNavigationFramesMissing
    case nativeMessagingDuringFill
    case nativeMessagingRelayCancelled
    case popupClosedBeforeFillComplete
    case popoverCloseAPIWrong
    case fillMessageDelivered
    case fillMessageNotDelivered
    case domInputEventMissing
    case domChangeEventMissing
    case pageWorldBridgeMissing
}

struct SafariExtensionAutofillFillDiagnosticSnapshot: Codable, Equatable, Sendable {
    let recordedAt: Date
    let bucketCounts: [String: Int]
    let lastBuckets: [String]
    let fillSessionActive: Bool
    let popupActive: Bool
}

@MainActor
enum SafariExtensionAutofillFillDiagnostics {
    static let deferredFillTeardownTimeout: Duration = .seconds(30)

    private static var bucketCounts: [SafariExtensionAutofillFillDiagnosticBucket: Int] = [:]
    private static var recentBuckets: [SafariExtensionAutofillFillDiagnosticBucket] = []
    private static let recentBucketLimit = 48
    private static var fillSessionActive = false
    private static var popupActive = false
    private static var nativeMessagingObservedDuringFill = false
    private static var popupClosedDuringFill = false
    private static var intentionalDeferredTeardownInProgress = false
    static var deferredFillCompletionHandler: (@MainActor (String?) -> Void)?

    static var isFillSessionActive: Bool { fillSessionActive }

    static func resetForTesting() {
        bucketCounts = [:]
        recentBuckets = []
        fillSessionActive = false
        popupActive = false
        nativeMessagingObservedDuringFill = false
        popupClosedDuringFill = false
        intentionalDeferredTeardownInProgress = false
        deferredFillCompletionHandler = nil
    }

    static func shouldDeferNativeMessagingTeardownOnPopupClose() -> Bool {
        fillSessionActive && nativeMessagingObservedDuringFill
    }

    static func beginIntentionalDeferredTeardown() {
        intentionalDeferredTeardownInProgress = true
    }

    static func endIntentionalDeferredTeardown() {
        intentionalDeferredTeardownInProgress = false
    }

    static func shouldRecordRelayCancellation() -> Bool {
        guard intentionalDeferredTeardownInProgress == false else { return false }
        return fillSessionActive
    }

    static func beginFillSession(extensionId: String?) {
        fillSessionActive = true
        nativeMessagingObservedDuringFill = false
        popupClosedDuringFill = false
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        record(.fillActionStarted, extensionId: extensionId)
    }

    static func endFillSession(extensionId: String?) {
        guard fillSessionActive else { return }
        fillSessionActive = false
        nativeMessagingObservedDuringFill = false
        popupClosedDuringFill = false
    }

    static func setPopupActive(_ isActive: Bool, extensionId: String? = nil) {
        popupActive = isActive
        if isActive {
            beginFillSession(extensionId: extensionId)
            return
        }

        guard fillSessionActive else { return }
        if nativeMessagingObservedDuringFill {
            popupClosedDuringFill = true
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            record(.popupClosedBeforeFillComplete, extensionId: extensionId)
            return
        }
        endFillSession(extensionId: extensionId)
    }

    static func noteNativeMessagingRelaySucceeded(extensionId: String?) {
        guard fillSessionActive, popupClosedDuringFill else { return }
        deferredFillCompletionHandler?(extensionId)
    }

    static func recordNativeMessagingActivity(extensionId: String?) {
        if fillSessionActive || popupActive {
            nativeMessagingObservedDuringFill = true
        }
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        if fillSessionActive || popupActive {
            record(.nativeMessagingDuringFill, extensionId: extensionId)
        }
    }

    static func recordNativeMessagingRelayCancelled(extensionId: String?) {
        guard shouldRecordRelayCancellation() else { return }
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        record(.nativeMessagingRelayCancelled, extensionId: extensionId)
        if fillSessionActive || popupActive {
            record(.popupClosedBeforeFillComplete, extensionId: extensionId)
        }
    }

    static func record(
        _ bucket: SafariExtensionAutofillFillDiagnosticBucket,
        extensionId: String? = nil,
        note: String? = nil
    ) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }

        bucketCounts[bucket, default: 0] += 1
        recentBuckets.append(bucket)
        if recentBuckets.count > recentBucketLimit {
            recentBuckets.removeFirst(recentBuckets.count - recentBucketLimit)
        }

        RuntimeDiagnostics.debug(category: "SafariAutofillFill") {
            var line = "bucket=\(bucket.rawValue)"
            if let extensionId {
                line += " ext=\(extensionId)"
            }
            if let note, note.isEmpty == false {
                line += " note=\(note)"
            }
            return line
        }
    }

    static func snapshot(
        fillSessionActive: Bool? = nil,
        popupActive: Bool? = nil
    ) -> SafariExtensionAutofillFillDiagnosticSnapshot {
        SafariExtensionAutofillFillDiagnosticSnapshot(
            recordedAt: Date(),
            bucketCounts: Dictionary(
                uniqueKeysWithValues: bucketCounts.map { ($0.key.rawValue, $0.value) }
            ),
            lastBuckets: recentBuckets.map(\.rawValue),
            fillSessionActive: fillSessionActive ?? Self.fillSessionActive,
            popupActive: popupActive ?? Self.popupActive
        )
    }

    static func logSnapshotIfEnabled(context: String) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        let report = snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8)
        else {
            RuntimeDiagnostics.debug(category: "SafariAutofillFill") {
                "snapshot encode failed context=\(context)"
            }
            return
        }
        RuntimeDiagnostics.debug(category: "SafariAutofillFill") {
            "snapshot context=\(context) \(json)"
        }
    }

    static func recordScriptingAvailability(
        extensionContext: WKWebExtensionContext,
        manifest: [String: Any]
    ) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }

        let declaresScripting =
            (manifest["permissions"] as? [String] ?? []).contains("scripting")
            || (manifest["optional_permissions"] as? [String] ?? []).contains("scripting")
        guard declaresScripting else { return }

        record(.scriptingExecuteRequested)

        let permissionStatus = extensionContext.permissionStatus(
            for: WKWebExtension.Permission.scripting
        )
        if permissionStatus == .grantedExplicitly
            || permissionStatus == .grantedImplicitly
        {
            record(.scriptingExecuteSucceeded, note: "scriptingPermissionGranted")
        } else {
            record(.scriptingExecuteFailed, note: "scriptingPermissionDenied")
        }

        if extensionContext.unsupportedAPIs.contains("browser.scripting.executeScript") {
            record(.pageWorldBridgeMissing, note: "webkitUnsupportedAPI")
        }
    }

    static func recordHostPermission(
        granted: Bool,
        extensionId: String?,
        reason: String
    ) {
        record(
            granted ? .hostPermissionGranted : .hostPermissionDenied,
            extensionId: extensionId,
            note: reason
        )
    }

    static func recordActiveTabPermission(
        granted: Bool,
        extensionId: String?,
        reason: String
    ) {
        record(
            granted ? .activeTabGranted : .activeTabDenied,
            extensionId: extensionId,
            note: reason
        )
    }

    static func recordFrameResolution(
        resolved: Bool,
        extensionId: String?,
        reason: String
    ) {
        record(
            resolved ? .frameResolved : .frameMissing,
            extensionId: extensionId,
            note: reason
        )
        record(
            resolved ? .webNavigationFramesAvailable : .webNavigationFramesMissing,
            extensionId: extensionId,
            note: reason
        )
    }

    static func recordContentScriptInjection(
        injected: Bool,
        extensionId: String?,
        reason: String
    ) {
        record(
            injected ? .contentScriptInjected : .contentScriptMissing,
            extensionId: extensionId,
            note: reason
        )
    }

    static func recordPopupTabVisibility(
        seesCurrentTab: Bool,
        extensionId: String?,
        reason: String
    ) {
        record(
            seesCurrentTab ? .popupSeesCurrentTab : .fillMessageNotDelivered,
            extensionId: extensionId,
            note: reason
        )
        if seesCurrentTab {
            record(.credentialSuggested, extensionId: extensionId, note: reason)
            record(.fillMessageDelivered, extensionId: extensionId, note: "activeTabVisible")
        }
    }

    static func recordPopoverPresentation(
        anchorResolved: Bool,
        extensionId: String?
    ) {
        if anchorResolved == false {
            record(.popoverCloseAPIWrong, extensionId: extensionId, note: "anchorUnresolved")
        }
    }
}
