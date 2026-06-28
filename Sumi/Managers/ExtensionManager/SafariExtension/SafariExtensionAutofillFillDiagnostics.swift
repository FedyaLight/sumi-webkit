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
    // Inline autofill overlay lifecycle (structural buckets only; no DOM/credential payloads).
    case inlineUIRenderAttempted
    case inlineUINotAttempted
    case inlineCSSMissing
    case inlineCSSLoaded
    case webAccessibleResourceBlocked
    case extensionResourceURLFailed
    case inlineIframeFailed
    case inlineIframeLoaded
    case overlayHeightCollapsed
    case overlayWidthCollapsed
    case overlayClipped
    case overlayBehindPage
    case wrongFrameTarget
    case focusLostBeforeRender
    case nativeMessagingDuringInlineUI
    case contentScriptInlineError
    case appKitLayerClippingSuspected
    case webKitPlatformLimitation
    case unknownNeedsTrace
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
    private static let extensionResourceSchemes: Set<String> = [
        "webkit-extension",
        "safari-web-extension",
    ]

    private static var bucketCounts: [SafariExtensionAutofillFillDiagnosticBucket: Int] = [:]
    private static var recentBuckets: [SafariExtensionAutofillFillDiagnosticBucket] = []
    private static let recentBucketLimit = 48
    private static var fillSessionActive = false
    private static var popupActive = false
    private static var nativeMessagingObservedDuringFill = false
    private static var popupClosedDuringFill = false
    private static var intentionalDeferredTeardownInProgress = false
    private static var inlineUISessionActive = false
    private static var inlineUIRenderAttemptedInSession = false
    private static var inlineCSSObservedInSession = false
    private static var inlineIframeObservedInSession = false
    static var deferredFillCompletionHandler: (@MainActor (String?) -> Void)?

    static var isFillSessionActive: Bool { fillSessionActive }
    static var isInlineUISessionActive: Bool { inlineUISessionActive }

    /// Returns true when an extension popup close should return first responder to the tab web view.
    static func shouldRestoreInlineUIHostingFocusAfterPopupClose() -> Bool {
        inlineUISessionActive && inlineUIRenderAttemptedInSession
    }

    static func resetForTesting() {
        bucketCounts = [:]
        recentBuckets = []
        fillSessionActive = false
        popupActive = false
        nativeMessagingObservedDuringFill = false
        popupClosedDuringFill = false
        intentionalDeferredTeardownInProgress = false
        inlineUISessionActive = false
        inlineUIRenderAttemptedInSession = false
        inlineCSSObservedInSession = false
        inlineIframeObservedInSession = false
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
        if inlineUISessionActive, popupActive == false {
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            record(.nativeMessagingDuringInlineUI, extensionId: extensionId)
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
            || permissionStatus == .grantedImplicitly {
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
        if resolved == false {
            recordWrongFrameTarget(extensionId: extensionId, reason: reason)
        }
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

    // MARK: - Inline UI overlay lifecycle

    static func beginInlineUISession(extensionId: String?) {
        inlineUISessionActive = true
        inlineUIRenderAttemptedInSession = false
        inlineCSSObservedInSession = false
        inlineIframeObservedInSession = false
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        recordInfrastructureProbeIfNeeded()
    }

    static func endInlineUISession(extensionId: String?) {
        guard inlineUISessionActive else { return }
        guard RuntimeDiagnostics.isVerboseEnabled else {
            inlineUISessionActive = false
            return
        }

        if inlineUIRenderAttemptedInSession {
            if inlineCSSObservedInSession == false {
                record(.inlineCSSMissing, extensionId: extensionId, note: "sessionEndedWithoutCSS")
            }
            if inlineIframeObservedInSession == false {
                record(.unknownNeedsTrace, extensionId: extensionId, note: "sessionEndedWithoutIframe")
            }
            if inlineCSSObservedInSession, inlineIframeObservedInSession == false {
                record(.overlayHeightCollapsed, extensionId: extensionId, note: "cssWithoutIframe")
            }
        } else {
            record(.inlineUINotAttempted, extensionId: extensionId, note: "sessionEndedWithoutRenderAttempt")
        }

        inlineUISessionActive = false
        inlineUIRenderAttemptedInSession = false
        inlineCSSObservedInSession = false
        inlineIframeObservedInSession = false
    }

    static func recordInlineUIRenderAttempted(
        extensionId: String?,
        reason: String
    ) {
        inlineUISessionActive = true
        inlineUIRenderAttemptedInSession = true
        record(.inlineUIRenderAttempted, extensionId: extensionId, note: reason)
    }

    static func recordInlineUINotAttempted(
        extensionId: String?,
        reason: String
    ) {
        record(.inlineUINotAttempted, extensionId: extensionId, note: reason)
    }

    static func recordInlinePopupFocusSteal(
        extensionId: String?,
        reason: String
    ) {
        if inlineUISessionActive, inlineUIRenderAttemptedInSession {
            record(.focusLostBeforeRender, extensionId: extensionId, note: reason)
        }
    }

    static func recordContentScriptInlineError(
        extensionId: String?,
        reason: String
    ) {
        record(.contentScriptInlineError, extensionId: extensionId, note: reason)
    }

    static func recordExtensionResourceNavigation(
        url: URL,
        isMainFrame: Bool,
        mimeType: String?,
        phase: ExtensionResourceNavigationPhase,
        extensionId: String? = nil
    ) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        guard extensionResourceSchemes.contains(url.scheme?.lowercased() ?? "") else {
            return
        }

        let resourceKind = Self.extensionResourceKindBucket(for: url)
        let mimeBucket = Self.mimeTypeBucket(mimeType)
        let frameBucket = isMainFrame ? "mainFrame" : "subframe"
        let note = "phase=\(phase.rawValue) frame=\(frameBucket) kind=\(resourceKind) mime=\(mimeBucket)"

        switch phase {
        case .committed:
            switch resourceKind {
            case "stylesheet":
                inlineCSSObservedInSession = true
                record(.inlineCSSLoaded, extensionId: extensionId, note: note)
            case "document":
                inlineIframeObservedInSession = true
                record(.inlineIframeLoaded, extensionId: extensionId, note: note)
            default:
                record(.inlineUIRenderAttempted, extensionId: extensionId, note: note)
            }
        case .failed:
            record(.extensionResourceURLFailed, extensionId: extensionId, note: note)
            switch resourceKind {
            case "stylesheet":
                record(.inlineCSSMissing, extensionId: extensionId, note: note)
            case "document":
                record(.inlineIframeFailed, extensionId: extensionId, note: note)
            default:
                break
            }
        case .cancelled:
            record(.webAccessibleResourceBlocked, extensionId: extensionId, note: note)
        }
    }

    static func recordWrongFrameTarget(
        extensionId: String?,
        reason: String
    ) {
        record(.wrongFrameTarget, extensionId: extensionId, note: reason)
    }

    static func recordAppKitContainerClipping(
        clipsToBounds: Bool,
        masksToBounds: Bool,
        inRoundedViewportContainer: Bool
    ) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        guard clipsToBounds || masksToBounds else { return }
        let note =
            "clipsToBounds=\(clipsToBounds) masksToBounds=\(masksToBounds) roundedContainer=\(inRoundedViewportContainer) inPageOverlaysUnaffected=true"
        record(.appKitLayerClippingSuspected, note: note)
    }

    static func recordWebKitPlatformLimitation(
        extensionId: String?,
        reason: String
    ) {
        record(.webKitPlatformLimitation, extensionId: extensionId, note: reason)
    }

    static func recordInfrastructureProbeIfNeeded() {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        let probe = SafariExtensionInlineUIInfrastructureProbe.evaluate()
        if probe.clipsToBoundsOnTabContainer {
            recordAppKitContainerClipping(
                clipsToBounds: true,
                masksToBounds: probe.masksToBoundsOnRoundedViewport,
                inRoundedViewportContainer: true
            )
        }
        if probe.lateBindBlocksLoadedPages {
            record(
                .webKitPlatformLimitation,
                note: "lateBindBlocksLoadedPages"
            )
        }
    }

    static func recordContentScriptInjection(
        injected: Bool,
        extensionId: String?,
        reason: String,
        pageURL: URL? = nil
    ) {
        record(
            injected ? .contentScriptInjected : .contentScriptMissing,
            extensionId: extensionId,
            note: reason
        )

        guard injected else {
            if isLikelyAutofillPageURL(pageURL) {
                recordInlineUINotAttempted(
                    extensionId: extensionId,
                    reason: reason
                )
            }
            return
        }

        guard isLikelyAutofillPageURL(pageURL) else { return }
        beginInlineUISession(extensionId: extensionId)
        recordInlineUIRenderAttempted(
            extensionId: extensionId,
            reason: reason
        )
    }

    private static func isLikelyAutofillPageURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    private static func extensionResourceKindBucket(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "css":
            return "stylesheet"
        case "html", "htm":
            return "document"
        case "js", "mjs":
            return "script"
        default:
            return ext.isEmpty ? "unknown" : "other"
        }
    }

    private static func mimeTypeBucket(_ mimeType: String?) -> String {
        guard let mimeType else { return "unknown" }
        let lowered = mimeType.lowercased()
        if lowered.contains("css") { return "stylesheet" }
        if lowered.contains("html") { return "document" }
        if lowered.contains("javascript") { return "script" }
        return "other"
    }
}

enum ExtensionResourceNavigationPhase: String, Sendable {
    case committed
    case failed
    case cancelled
}
