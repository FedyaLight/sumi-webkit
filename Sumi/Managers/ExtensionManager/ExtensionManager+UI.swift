import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowDelegate: NSObject, NSWindowDelegate, WKUIDelegate {
    private let extensionId: String
    private weak var manager: ExtensionManager?
    private weak var webView: WKWebView?
    var isCleaningUp = false

    init(
        extensionId: String,
        manager: ExtensionManager,
        webView: WKWebView
    ) {
        self.extensionId = extensionId
        self.manager = manager
        self.webView = webView
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        guard isCleaningUp == false else { return }
        manager?.cleanupOptionsWindow(
            for: extensionId,
            window: notification.object as? NSWindow,
            webView: webView,
            shouldOrderOut: false
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard isCleaningUp == false else { return }
        manager?.cleanupOptionsWindow(
            for: extensionId,
            window: webView.window,
            webView: webView,
            shouldOrderOut: true
        )
    }
}

#if DEBUG
@available(macOS 15.5, *)
@MainActor
final class ChromeMV3NativeActionPopupBoundaryRecorder {
    private let startedAt = Date()
    private(set) var snapshot: ChromeMV3NativeActionPopupBoundarySnapshot
    private weak var popupWebView: WKWebView?
    private weak var popupPopover: NSPopover?
    private var observations: [NSKeyValueObservation] = []

    init(
        extensionID: String,
        extensionContext: WKWebExtensionContext,
        action: WKWebExtension.Action,
        preludeConfiguredBeforePopupCreation: Bool
    ) {
        snapshot = ChromeMV3NativeActionPopupBoundarySnapshot(
            extensionID: extensionID,
            contextUniqueIdentifier: extensionContext.uniqueIdentifier,
            contextLoaded: extensionContext.isLoaded,
            actionEnabled: action.isEnabled,
            actionPresentsPopup: action.presentsPopup,
            associatedTabKnown: action.associatedTab != nil,
            popupWebViewAccessedBeforePerformAction: false,
            popupWebViewAvailableAtPresentation: false,
            popupPopoverAvailableAtPresentation: false,
            nativePopupBridgeInstalled: false,
            nativePopupPreludeConfiguredBeforePopupCreation:
                preludeConfiguredBeforePopupCreation,
            nativePopupPreludeAttachedAtDocumentStart: false,
            nativePopupPreludeFirstMissingAPIOrError: nil,
            lifecycleEvents: [],
            routeObservations: [],
            observerLimitations: [
                "WKWebExtension.Action.popupWebView is not accessed before performAction, because first access may preload WebKit's popup page.",
                "The current SDK exposes native-application messaging delegate callbacks, but does not expose ordinary runtime.sendMessage/runtime.connect payload callbacks to the embedding app.",
                "Tab/window adapter callbacks can show WebKit querying Sumi's tab boundary, but they do not carry the originating Chrome API name or message body.",
                "No ChromeMV3PopupOptionsJSBridgeHandler is installed on WebKit's native action popup web view.",
                preludeConfiguredBeforePopupCreation
                    ? "A DEBUG-only native action popup prelude was configured on the WebKit extension-page base configuration before controller creation."
                    : "No DEBUG native action popup prelude was configured before this WebKit controller was created; public WebKit APIs do not provide a later proven hook before popup JS executes.",
            ]
        )
        recordLifecycle(
            "observerStarted",
            popupWebViewAvailable: false,
            note: "passive DEBUG/local-experimental observer armed"
        )
    }

    func recordPerformActionAboutToRun(action: WKWebExtension.Action) {
        snapshot.actionEnabled = action.isEnabled
        snapshot.actionPresentsPopup = action.presentsPopup
        snapshot.associatedTabKnown = action.associatedTab != nil
        recordLifecycle(
            "performAction.aboutToRun",
            popupWebViewAvailable: false,
            note: "popupWebView intentionally not touched before performAction"
        )
    }

    func recordPerformActionReturned() {
        recordLifecycle(
            "performAction.returned",
            popupWebViewAvailable: popupWebView != nil
        )
    }

    func attachPresentationBoundary(
        action: WKWebExtension.Action,
        popover: NSPopover?,
        webView: WKWebView?
    ) {
        popupPopover = popover
        snapshot.actionEnabled = action.isEnabled
        snapshot.actionPresentsPopup = action.presentsPopup
        snapshot.associatedTabKnown = action.associatedTab != nil
        snapshot.popupPopoverAvailableAtPresentation = popover != nil
        snapshot.popupWebViewAvailableAtPresentation = webView != nil

        if let webView {
            attachPopupWebView(webView)
            recordPopupWebViewState(
                webView,
                milestone: "presentActionPopup.popupWebViewAvailable"
            )
        } else {
            recordLifecycle(
                "presentActionPopup.popupWebViewUnavailable",
                popupWebViewAvailable: false
            )
        }
    }

    func recordPopoverPresented(anchorKind: String) {
        recordLifecycle(
            "popupPopover.presented",
            popupWebViewAvailable: popupWebView != nil,
            sanitizedURLShape: Self.sanitizedURLShape(popupWebView?.url),
            isLoading: popupWebView?.isLoading,
            estimatedProgressBucket:
                Self.progressBucket(popupWebView?.estimatedProgress),
            note: anchorKind
        )
    }

    func recordPresentationFailed(reason: String) {
        recordLifecycle(
            "popupPopover.presentationFailed",
            popupWebViewAvailable: popupWebView != nil,
            sanitizedURLShape: Self.sanitizedURLShape(popupWebView?.url),
            isLoading: popupWebView?.isLoading,
            estimatedProgressBucket:
                Self.progressBucket(popupWebView?.estimatedProgress),
            note: reason
        )
    }

    func recordPopoverClosed() {
        recordLifecycle(
            "popupPopover.closed",
            popupWebViewAvailable: popupWebView != nil,
            sanitizedURLShape: Self.sanitizedURLShape(popupWebView?.url),
            isLoading: popupWebView?.isLoading,
            estimatedProgressBucket:
                Self.progressBucket(popupWebView?.estimatedProgress)
        )
    }

    func recordObserverDetached() {
        recordLifecycle(
            "observerDetached",
            popupWebViewAvailable: popupWebView != nil
        )
        observations.removeAll()
    }

    func observes(popover: NSPopover?) -> Bool {
        guard let popover else { return popupPopover == nil }
        return popupPopover === popover
    }

    func recordRoute(
        apiName: String,
        sourceContext: String,
        targetContext: String,
        nativeBoundary: String,
        metadataAvailable: Bool,
        payloadShape: String? = nil,
        resultClassifier: String? = nil,
        keyCount: Int? = nil,
        safeTopLevelFieldNames: [String] = [],
        portName: String? = nil,
        listenerRouteResult: String? = nil,
        firstMissingAPIOrError: String? = nil,
        sanitizedURLShape: String? = nil,
        notes: [String] = []
    ) {
        guard snapshot.routeObservations.count < 80 else { return }
        snapshot.routeObservations.append(
            ChromeMV3NativeActionPopupRouteObservation(
                apiName: apiName,
                sourceContext: sourceContext,
                targetContext: targetContext,
                nativeBoundary: nativeBoundary,
                metadataAvailable: metadataAvailable,
                payloadShape: payloadShape,
                resultClassifier: resultClassifier,
                keyCount: keyCount,
                safeTopLevelFieldNames: safeTopLevelFieldNames,
                portName: portName,
                listenerRouteResult: listenerRouteResult,
                firstMissingAPIOrError: firstMissingAPIOrError,
                sanitizedURLShape: sanitizedURLShape,
                notes: notes
            )
        )
    }

    func recordPreludeAttachment(
        resultClassifier: String?,
        firstMissingAPIOrError: String?
    ) {
        if resultClassifier == "preludeInstalledAtDocumentStart" {
            snapshot.nativePopupPreludeAttachedAtDocumentStart = true
        }
        if snapshot.nativePopupPreludeFirstMissingAPIOrError == nil {
            snapshot.nativePopupPreludeFirstMissingAPIOrError =
                firstMissingAPIOrError
        }
    }

    static func sanitizedPayloadShape(_ value: Any?) -> String {
        guard let value else { return "none" }

        if let dictionary = value as? [String: Any] {
            return sanitizedDictionaryShape(dictionary)
        }
        if let dictionary = value as? NSDictionary {
            var bridged: [String: Any] = [:]
            for (key, value) in dictionary {
                if let key = key as? String {
                    bridged[key] = value
                }
            }
            return sanitizedDictionaryShape(bridged)
        }
        if let array = value as? [Any] {
            return "array(count:\(array.count))"
        }
        if let array = value as? NSArray {
            return "array(count:\(array.count))"
        }
        if let string = value as? String {
            return "string(length:\(string.count))"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "boolean"
            }
            return "number"
        }
        if value is NSNull {
            return "null"
        }
        return "jsonValue(type:\(String(describing: type(of: value))))"
    }

    private func attachPopupWebView(_ webView: WKWebView) {
        guard popupWebView !== webView else { return }
        observations.removeAll()
        popupWebView = webView

        observations.append(
            webView.observe(\.url, options: [.initial, .new]) {
                [weak self, weak webView] _, _ in
                Task { @MainActor in
                    self?.recordPopupWebViewState(
                        webView,
                        milestone: "popupWebView.urlObserved"
                    )
                }
            }
        )
        observations.append(
            webView.observe(\.isLoading, options: [.initial, .new]) {
                [weak self, weak webView] _, _ in
                Task { @MainActor in
                    self?.recordPopupWebViewState(
                        webView,
                        milestone: "popupWebView.loadingObserved"
                    )
                }
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress, options: [.initial, .new]) {
                [weak self, weak webView] _, _ in
                Task { @MainActor in
                    self?.recordPopupWebViewState(
                        webView,
                        milestone: "popupWebView.progressObserved"
                    )
                }
            }
        )
        observations.append(
            webView.observe(\.title, options: [.new]) {
                [weak self, weak webView] _, _ in
                Task { @MainActor in
                    self?.recordPopupWebViewState(
                        webView,
                        milestone: "popupWebView.titleObserved"
                    )
                }
            }
        )
    }

    private func recordPopupWebViewState(
        _ webView: WKWebView?,
        milestone: String
    ) {
        recordLifecycle(
            milestone,
            popupWebViewAvailable: webView != nil,
            sanitizedURLShape: Self.sanitizedURLShape(webView?.url),
            isLoading: webView?.isLoading,
            estimatedProgressBucket:
                Self.progressBucket(webView?.estimatedProgress)
        )
    }

    private func recordLifecycle(
        _ milestone: String,
        popupWebViewAvailable: Bool,
        sanitizedURLShape: String? = nil,
        isLoading: Bool? = nil,
        estimatedProgressBucket: String? = nil,
        note: String? = nil
    ) {
        guard snapshot.lifecycleEvents.count < 120 else { return }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        snapshot.lifecycleEvents.append(
            ChromeMV3NativeActionPopupLifecycleEvent(
                milestone: milestone,
                elapsedMilliseconds: elapsed,
                popupWebViewAvailable: popupWebViewAvailable,
                sanitizedURLShape: sanitizedURLShape,
                isLoading: isLoading,
                estimatedProgressBucket: estimatedProgressBucket,
                note: note
            )
        )
    }

    private static func sanitizedDictionaryShape(
        _ dictionary: [String: Any]
    ) -> String {
        let safeFieldNames = dictionary.keys
            .filter { safeCommandTypeActionFieldNames.contains($0) }
            .sorted()
        let sensitiveKeyPresent = dictionary.keys.contains { key in
            sensitiveFieldNameFragments.contains { fragment in
                key.localizedCaseInsensitiveContains(fragment)
            }
        }
        return [
            "object(keyCount:\(dictionary.count)",
            "safeFieldNames:\(safeFieldNames)",
            "sensitiveKeyPresent:\(sensitiveKeyPresent))",
        ].joined(separator: ",")
    }

    private static func sanitizedURLShape(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return nil
        }

        if ExtensionManager.extensionSchemes.contains(scheme) {
            let lastPathComponent = url.lastPathComponent.isEmpty
                ? "<extension-resource>"
                : url.lastPathComponent
            return "\(scheme)://<extension>/\(lastPathComponent)"
        }

        if scheme == "http" || scheme == "https" {
            return "\(scheme)://<host>/<redacted-path>"
        }

        return "\(scheme)://<redacted>"
    }

    private static func progressBucket(_ progress: Double?) -> String? {
        guard let progress else { return nil }
        switch progress {
        case ..<0.01:
            return "0"
        case ..<0.5:
            return "0-49"
        case ..<1:
            return "50-99"
        default:
            return "100"
        }
    }

    private static let safeCommandTypeActionFieldNames: Set<String> = [
        "action",
        "command",
        "kind",
        "method",
        "name",
        "operation",
        "type",
    ]

    private static let sensitiveFieldNameFragments: Set<String> = [
        "auth",
        "cookie",
        "credential",
        "password",
        "secret",
        "session",
        "token",
        "vault",
    ]
}
#endif

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: NSPopoverDelegate {
    #if DEBUG
        @discardableResult
        func beginNativeActionPopupBoundaryObservation(
            extensionID: String,
            extensionContext: WKWebExtensionContext,
            action: WKWebExtension.Action
        ) -> Bool {
            guard Self.isNativeActionPopupBoundaryObservationEnabled else {
                return false
            }

            let recorder = ChromeMV3NativeActionPopupBoundaryRecorder(
                extensionID: extensionID,
                extensionContext: extensionContext,
                action: action,
                preludeConfiguredBeforePopupCreation:
                    nativeActionPopupPreludeInstalledInControllerConfiguration
            )
            nativeActionPopupBoundaryRecorders[extensionID] = recorder
            lastNativeActionPopupBoundarySnapshots.removeValue(forKey: extensionID)
            return true
        }

        func recordNativeActionPopupBoundaryPerformActionAboutToRun(
            extensionID: String,
            action: WKWebExtension.Action
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled else {
                return
            }
            nativeActionPopupBoundaryRecorders[extensionID]?
                .recordPerformActionAboutToRun(action: action)
        }

        func recordNativeActionPopupBoundaryPerformActionReturned(
            extensionID: String
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled else {
                return
            }
            nativeActionPopupBoundaryRecorders[extensionID]?
                .recordPerformActionReturned()
        }

        func recordNativeActionPopupPresentationBoundary(
            action: WKWebExtension.Action,
            extensionContext: WKWebExtensionContext,
            popover: NSPopover?,
            webView: WKWebView?
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled,
                  let extensionID = extensionID(for: extensionContext)
            else {
                return
            }

            nativeActionPopupBoundaryRecorders[extensionID]?
                .attachPresentationBoundary(
                    action: action,
                    popover: popover,
                    webView: webView
                )
        }

        func recordNativeActionPopupPopoverPresented(
            extensionID: String,
            anchorKind: String
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled else {
                return
            }
            nativeActionPopupBoundaryRecorders[extensionID]?
                .recordPopoverPresented(anchorKind: anchorKind)
        }

        func recordNativeActionPopupPresentationFailed(
            extensionID: String?,
            reason: String
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled else {
                return
            }
            let recorder: ChromeMV3NativeActionPopupBoundaryRecorder?
            if let extensionID {
                recorder = nativeActionPopupBoundaryRecorders[extensionID]
            } else {
                recorder = nativeActionPopupBoundaryRecorders.values.first
            }
            recorder?.recordPresentationFailed(reason: reason)
        }

        func finishNativeActionPopupBoundaryObservation(
            popover: NSPopover?
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled else {
                return
            }

            let matches = nativeActionPopupBoundaryRecorders.filter {
                $0.value.observes(popover: popover)
            }
            for (extensionID, recorder) in matches {
                recorder.recordPopoverClosed()
                recorder.recordObserverDetached()
                lastNativeActionPopupBoundarySnapshots[extensionID] =
                    recorder.snapshot
                nativeActionPopupBoundaryRecorders.removeValue(forKey: extensionID)
            }
        }

        func nativeActionPopupBoundarySnapshot(
            for extensionID: String
        ) -> ChromeMV3NativeActionPopupBoundarySnapshot? {
            nativeActionPopupBoundaryRecorders[extensionID]?.snapshot
                ?? lastNativeActionPopupBoundarySnapshots[extensionID]
        }

        func nativeActionPopupBoundaryDiagnostics(
            for snapshot: ChromeMV3NativeActionPopupBoundarySnapshot?
        ) -> [String] {
            guard let snapshot else {
                return [
                    "Native action popup boundary observer was disabled or did not receive a WebKit popup callback.",
                    "Snapshot retrieval is passive and did not create a popup, runtime, service-worker, content-script endpoint, native host, timer, or bridge by itself.",
                ]
            }

            var diagnostics = [
                "Native WebKit action popup boundary snapshot captured.",
                "Native popup bridge installed: \(snapshot.nativePopupBridgeInstalled).",
                "Native popup prelude configured before popup creation: \(snapshot.nativePopupPreludeConfiguredBeforePopupCreation).",
                "Native popup prelude attached at document-start: \(snapshot.nativePopupPreludeAttachedAtDocumentStart).",
                "Popup webView available at presentation: \(snapshot.popupWebViewAvailableAtPresentation).",
                "Popup popover available at presentation: \(snapshot.popupPopoverAvailableAtPresentation).",
            ]
            if let firstMissing = snapshot.nativePopupPreludeFirstMissingAPIOrError {
                diagnostics.append(
                    "Native popup prelude first missing API or error: \(firstMissing)."
                )
            }
            diagnostics.append(contentsOf: snapshot.sanitizedLogLines)
            diagnostics.append(contentsOf: snapshot.observerLimitations)
            diagnostics.append(
                "Snapshot retrieval is passive and did not create a popup, runtime, service-worker, content-script endpoint, native host, timer, or bridge by itself."
            )
            return diagnostics
        }

        func recordNativeActionPopupRouteObservation(
            for extensionContext: WKWebExtensionContext,
            apiName: String,
            sourceContext: String,
            targetContext: String,
            nativeBoundary: String,
            metadataAvailable: Bool,
            payloadShape: String? = nil,
            resultClassifier: String? = nil,
            notes: [String] = []
        ) {
            guard Self.isNativeActionPopupBoundaryObservationEnabled,
                  let extensionID = extensionID(for: extensionContext),
                  let recorder = nativeActionPopupBoundaryRecorders[extensionID]
            else {
                return
            }

            recorder.recordRoute(
                apiName: apiName,
                sourceContext: sourceContext,
                targetContext: targetContext,
                nativeBoundary: nativeBoundary,
                metadataAvailable: metadataAvailable,
                payloadShape: payloadShape,
                resultClassifier: resultClassifier,
                notes: notes
            )
        }

        func sanitizedNativeActionPopupPayloadShape(_ value: Any?) -> String {
            ChromeMV3NativeActionPopupBoundaryRecorder
                .sanitizedPayloadShape(value)
        }
    #endif

    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        guard let extensionId = extensionID(for: extensionContext) else {
            return
        }

        actionStatesByExtensionID[extensionId] =
            BrowserExtensionActionSurfaceState(
                extensionID: extensionId,
                label: action.label,
                badgeText: action.badgeText,
                hasUnreadBadgeText: action.hasUnreadBadgeText,
                isEnabled: action.isEnabled,
                presentsPopup: action.presentsPopup,
                icon: action.icon(for: CGSize(width: 18, height: 18))
            )
    }

    func clearActionSurfaceState(for extensionId: String) {
        actionStatesByExtensionID.removeValue(forKey: extensionId)
    }

    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        guard let installedExtension = installedExtensions.first(where: {
            $0.id == extensionId
        }) else {
            return .blocked(
                .extensionNotInstalled,
                message: "The extension is not installed in Sumi's local MV3 action surface."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction click extensionId=\(extensionId) manifestHash=\(installedExtension.manifestRootFingerprint) generatedBundlePath=\(installedExtension.packagePath) originalPackagePath=\(installedExtension.sourceBundlePath) extensionEnabled=\(installedExtension.isEnabled) runtimeState=\(runtimeState.rawValue) contextLoaded=\(getExtensionContext(for: extensionId) != nil) currentProfile=\(currentProfileId?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURLShape=\(sanitizedURLHubTraceURL(currentTab?.url))"
        )
        guard installedExtension.isEnabled else {
            return .blocked(
                .extensionDisabled,
                message: "\(installedExtension.name) is disabled."
            )
        }
        guard installedExtension.hasAction else {
            return .blocked(
                .actionMissing,
                message: "\(installedExtension.name) does not declare a Chrome action."
            )
        }
        guard installedExtension.defaultPopupPath != nil else {
            return .blocked(
                .noActionPopup,
                message: "\(installedExtension.name) does not declare action.default_popup; action-click dispatch is deferred."
            )
        }
        guard let currentTab else {
            return .blocked(
                .noEligibleTab,
                message: "No active eligible tab is available for the extension action."
            )
        }
        guard currentTab.isEphemeral == false else {
            return .blocked(
                .noEligibleTab,
                message: "Private tabs are not eligible for local MV3 action popups."
            )
        }
        guard hasActionCurrentPagePermission(
            installedExtension,
            currentURL: currentTab.url
        ) else {
            return .blocked(
                .currentPagePermissionMissing,
                message: "\(installedExtension.name) does not have host permission or activeTab for the current page."
            )
        }
        guard isModuleWorkerUnsupported(installedExtension) == false else {
            return .blocked(
                .moduleWorkerUnsupported,
                message: "\(installedExtension.name) declares a module service worker, which remains unsupported in this popup path."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction preflight passed extensionId=\(extensionId) localExperimentalRecordEnabled=true currentTabEligible=true currentPagePermission=true moduleWorkerUnsupported=false"
        )

        guard await requestExtensionRuntimeAndWait(reason: .extensionAction) else {
            return .blocked(
                runtimeState == .failed ? .runtimeLoadFailed : .runtimeUnavailable,
                message: "\(installedExtension.name) could not load WebKit extension runtime for the action popup."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction runtime ready extensionId=\(extensionId) loadedContexts=\(extensionContexts.count) selectedContextLoaded=\(getExtensionContext(for: extensionId) != nil)"
        )

        let extensionContext: WKWebExtensionContext
        do {
            guard let loadedContext = try await loadActionPopupContextIfNeeded(
                for: installedExtension
            ) else {
                return .blocked(
                    .contextUnavailable,
                    message: "\(installedExtension.name) has no enabled persisted local package record for WebKit context loading."
                )
            }
            extensionContext = loadedContext
        } catch {
            extensionRuntimeTrace(
                "urlHubAction selected context load failed extensionId=\(extensionId) error=\(error.localizedDescription)"
            )
            return .blocked(
                .runtimeLoadFailed,
                message: "\(installedExtension.name) WebKit context load failed for the selected local package: \(error.localizedDescription)"
            )
        }

        let adapter = stableAdapter(for: currentTab)
        guard let action = extensionContext.action(for: adapter) else {
            return .blocked(
                .actionMissing,
                message: "WebKit did not expose an action for \(installedExtension.name)."
            )
        }

        updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )

        guard action.isEnabled else {
            return .blocked(
                .actionDisabled,
                message: "\(action.label) is disabled for the current page."
            )
        }
        guard action.presentsPopup else {
            return .blocked(
                .noActionPopup,
                message: "\(action.label) has no WebKit action popup for the current page."
            )
        }

        extensionRuntimeTrace(
            "urlHubAction performAction extensionId=\(extensionId) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        )
        #if DEBUG
            _ = beginNativeActionPopupBoundaryObservation(
                extensionID: extensionId,
                extensionContext: extensionContext,
                action: action
            )
            recordNativeActionPopupBoundaryPerformActionAboutToRun(
                extensionID: extensionId,
                action: action
            )
        #endif
        extensionContext.performAction(for: adapter)
        #if DEBUG
            recordNativeActionPopupBoundaryPerformActionReturned(
                extensionID: extensionId
            )
        #endif
        recordRuntimeMetric(for: extensionId) { metrics in
            metrics.lastBackgroundWakeReason = .actionPopup
            metrics.backgroundWakeCount += 1
        }
        #if DEBUG
        await Task.yield()
        await Task.yield()
        let nativePopupSnapshot = nativeActionPopupBoundarySnapshot(
            for: extensionId
        )
        let nativePopupDiagnostics =
            nativeActionPopupBoundaryDiagnostics(for: nativePopupSnapshot)
        return .openedPopup(
            nativePopupBoundarySnapshot: nativePopupSnapshot,
            sanitizedBridgeSnapshot: nil,
            diagnostics: nativePopupDiagnostics + [
                "URL-hub opened the real WebKit action popup through WKWebExtensionContext.performAction.",
                "No ChromeMV3PopupOptionsJSBridgeHandler is installed on WebKit's native action.popupWebView; DEBUG route records, when present, come only from the passive native action popup prelude.",
            ]
        )
        #else
        return .openedPopup
        #endif
    }

    private func loadActionPopupContextIfNeeded(
        for installedExtension: InstalledExtension
    ) async throws -> WKWebExtensionContext? {
        if let extensionContext = getExtensionContext(for: installedExtension.id) {
            return extensionContext
        }

        guard let entity = try extensionEntity(for: installedExtension.id),
              entity.isEnabled
        else {
            return nil
        }

        extensionRuntimeTrace(
            "urlHubAction loading selected missing context extensionId=\(installedExtension.id) runtimeState=\(runtimeState.rawValue) packagePath=\(entity.packagePath)"
        )
        _ = try await loadEnabledExtension(
            from: entity,
            expectedLoadGeneration: extensionLoadGeneration
        )
        return getExtensionContext(for: installedExtension.id)
    }

    private func sanitizedURLHubTraceURL(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return "nil"
        }
        if Self.extensionSchemes.contains(scheme) {
            return "\(scheme)://<extension>/\(url.lastPathComponent.isEmpty ? "<resource>" : url.lastPathComponent)"
        }
        if scheme == "http" || scheme == "https" {
            return "\(scheme)://<host>/<redacted-path>"
        }
        return "\(scheme)://<redacted>"
    }

    private func isModuleWorkerUnsupported(
        _ installedExtension: InstalledExtension
    ) -> Bool {
        guard let background = installedExtension.manifest["background"]
                as? [String: Any],
              let type = background["type"] as? String
        else {
            return false
        }
        return type.caseInsensitiveCompare("module") == .orderedSame
    }

    private func hasActionCurrentPagePermission(
        _ installedExtension: InstalledExtension,
        currentURL: URL
    ) -> Bool {
        guard ["http", "https"].contains(currentURL.scheme?.lowercased() ?? "") else {
            return false
        }

        let manifest = installedExtension.manifest
        let permissions = stringArray(from: manifest["permissions"])
        let optionalPermissions = stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            return true
        }

        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { stringArray(from: $0["matches"]) }
        let hostPatterns =
            stringArray(from: manifest["host_permissions"])
            + permissions.filter(Self.isHostPermissionPattern)
            + contentScriptMatches

        return hostPatterns.contains {
            ChromeMV3HostMatchPattern($0).matches(
                url: currentURL.absoluteString
            )
        }
    }

    private static func isHostPermissionPattern(_ value: String) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private func stringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        reason: String = #function
    ) {
        let requestedController = requestExtensionRuntime(
            reason: .webViewConfiguration
        )
        let existingController = configuration.webExtensionController
        let shouldAssignController = existingController == nil && requestedController != nil

        extensionRuntimeTrace(
            "prepareConfiguration reason=\(reason) configuration=\(extensionRuntimeConfigurationDescription(configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(configuration.userContentController)) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(requestedController)) willAssign=\(shouldAssignController)"
        )

        if shouldAssignController {
            configuration.webExtensionController = requestedController
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        pruneActionAnchors(for: extensionId, keeping: anchorView)

        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        var anchors = actionAnchors[extensionId] ?? []

        if let index = anchors.firstIndex(where: { $0.view === anchorView }) {
            anchors[index] = anchor
        } else {
            anchors.append(anchor)
        }
        actionAnchors[extensionId] = anchors

        let viewIdentifier = ObjectIdentifier(anchorView)
        anchorView.postsFrameChangedNotifications = true

        if anchorObserverTokens[extensionId]?[viewIdentifier] != nil {
            return
        }

        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
        ) { [weak self, weak anchorView] _ in
            guard let anchorView else { return }
            Task { @MainActor [weak self] in
                guard let index = self?.actionAnchors[extensionId]?.firstIndex(where: { $0.view === anchorView }) else {
                    return
                }
                self?.actionAnchors[extensionId]?[index] = WeakAnchor(
                    view: anchorView,
                    window: anchorView.window
                )
                self?.pruneActionAnchors(for: extensionId, keeping: anchorView)
            }
        }

        anchorObserverTokens[extensionId, default: [:]][viewIdentifier] = token
        enforceActionAnchorLimit(for: extensionId, keeping: anchorView)
    }

    func clearActionAnchors(for extensionId: String) {
        removeAnchorObservers(for: extensionId)
        actionAnchors.removeValue(forKey: extensionId)
    }

    func closeOptionsWindow(for extensionId: String) {
        cleanupOptionsWindow(for: extensionId, shouldOrderOut: true)
    }

    func closeAllOptionsWindows() {
        Array(optionsWindows.keys).forEach { closeOptionsWindow(for: $0) }
    }

    func cleanupOptionsWindow(
        for extensionId: String,
        window: NSWindow? = nil,
        webView: WKWebView? = nil,
        shouldOrderOut: Bool
    ) {
        guard let resolvedWindow = window ?? optionsWindows[extensionId] else {
            optionsWindowDelegates.removeValue(forKey: extensionId)
            return
        }

        let delegate = optionsWindowDelegates[extensionId]
        delegate?.isCleaningUp = true

        let resolvedWebView = webView ?? resolvedWindow.contentView.flatMap {
            Self.firstWebView(in: $0)
        }
        if let resolvedWebView {
            SumiAuxiliaryWebViewShutdown.perform(
                on: resolvedWebView,
                browserManager: browserManager,
                reason: "Extension options window cleanup"
            )
        }

        if shouldOrderOut {
            resolvedWindow.orderOut(nil)
        }
        resolvedWindow.contentViewController = nil
        resolvedWindow.contentView = nil
        resolvedWindow.delegate = nil
        optionsWindows.removeValue(forKey: extensionId)
        optionsWindowDelegates.removeValue(forKey: extensionId)
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL? = nil,
        reason: String = #function
    ) {
        let existingController = webView.configuration.webExtensionController

        extensionRuntimeTrace(
            "prepareWebView reason=\(reason) webView=\(extensionRuntimeWebViewDescription(webView)) configuration=\(extensionRuntimeConfigurationDescription(webView.configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(extensionRuntimeControllerDescription(existingController)) extensionController=\(extensionRuntimeControllerDescription(extensionController)) willAssign=false"
        )

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        installExternallyConnectableNativeBridgeIfNeeded(
            into: webView.configuration.userContentController
        )
        updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: currentURL
        )
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let browserManager, let windowRegistry = browserManager.windowRegistry else {
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Browser manager is unavailable"]
                )
            )
            return
        }

        if let firstURL = tabURLs.first,
           OAuthDetector.isLikelyOAuthPopupURL(firstURL),
           let activeWindow = windowRegistry.activeWindow
        {
            let targetSpace = activeWindow.currentSpaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace

            let createdTab = browserManager.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: targetSpace,
                activate: false
            )

            if Self.isExtensionOwnedURL(firstURL),
               let resolvedContext = controller.extensionContext(for: firstURL)
            {
                createdTab.applyWebViewConfigurationOverride(
                    resolvedContext.webViewConfiguration
                        ?? browserConfiguration.webViewConfiguration
                )
            }

            browserManager.selectTab(createdTab, in: activeWindow)
            completionHandler(windowAdapter(for: activeWindow.id), nil)
            return
        }

        let existingWindowIDs = Set(windowRegistry.windows.keys)
        createWindow()

        Task { @MainActor [weak self, weak browserManager] in
            guard let self, let browserManager else { return }

            guard let windowState = await awaitWindowRegistration(existingWindowIDs) else {
                completionHandler(nil, NSError(
                    domain: "ExtensionManager",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Sumi could not resolve the new window"]
                ))
                return
            }

            let targetSpace = windowState.currentSpaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace

            let createdTab: Tab
            if let firstURL = tabURLs.first {
                createdTab = browserManager.tabManager.createNewTab(
                    url: firstURL.absoluteString,
                    in: targetSpace,
                    activate: false
                )

                if Self.isExtensionOwnedURL(firstURL),
                   let resolvedContext = controller.extensionContext(for: firstURL)
                {
                    createdTab.applyWebViewConfigurationOverride(
                        resolvedContext.webViewConfiguration
                            ?? browserConfiguration.webViewConfiguration
                    )
                }
            } else {
                createdTab = browserManager.tabManager.createNewTab(
                    in: targetSpace,
                    activate: false
                )
            }

            browserManager.selectTab(createdTab, in: windowState)
            completionHandler(self.windowAdapter(for: windowState.id), nil)
        }
    }

    func presentOptionsPageWindow(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        guard let extensionId = extensionID(for: extensionContext),
              let installedExtension = installedExtensions.first(where: { $0.id == extensionId })
        else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = loadedExtensionManifests[extensionId] ?? installedExtension.manifest

        let diskResolvedURL = try? ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: installedExtension.optionsPagePath,
            manifest: manifest,
            extensionRoot: extensionRoot
        )

        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = computeOptionsPageURL(for: extensionContext)
        let optionsURL: URL?
        if let diskResolvedURL {
            optionsURL = diskResolvedURL
        } else if let sdkURL {
            optionsURL = sdkURL
        } else if let manifestURL {
            optionsURL = manifestURL
        } else {
            optionsURL = nil
        }

        guard let optionsURL else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let baseConfiguration =
            extensionContext.webViewConfiguration
            ?? browserConfiguration.webViewConfiguration
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            from: baseConfiguration,
            surface: .extensionOptions,
            additionalUserScripts: baseConfiguration.userContentController.userScripts
        )
        prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "ExtensionManager.openOptionsPage.configuration"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        prepareWebViewForExtensionRuntime(
            webView,
            currentURL: optionsURL,
            reason: "ExtensionManager.openOptionsPage"
        )

        if optionsURL.isFileURL {
            do {
                let validatedOptionsURL = try ExtensionUtils.validatedExtensionPageURL(
                    optionsURL,
                    within: extensionRoot
                )
                webView.loadFileURL(
                    validatedOptionsURL,
                    allowingReadAccessTo: extensionRoot
                )
            } catch {
                completionHandler(error)
                return
            }
        } else {
            webView.load(URLRequest(url: optionsURL))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(displayName) – Options"

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.center()

        closeOptionsWindow(for: extensionId)
        let delegate = ExtensionOptionsWindowDelegate(
            extensionId: extensionId,
            manager: self,
            webView: webView
        )
        webView.uiDelegate = delegate
        window.delegate = delegate
        optionsWindows[extensionId] = window
        optionsWindowDelegates[extensionId] = delegate
        window.orderFront(nil)

        completionHandler(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        #if DEBUG
            finishNativeActionPopupBoundaryObservation(
                popover: notification.object as? NSPopover
            )
        #endif
        isPopupActive = false
    }

    private func removeAnchorObservers(for extensionId: String) {
        guard let tokens = anchorObserverTokens.removeValue(forKey: extensionId) else {
            return
        }

        for (_, token) in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func pruneActionAnchors(
        for extensionId: String,
        keeping anchorView: NSView? = nil
    ) {
        guard var anchors = actionAnchors[extensionId] else {
            return
        }

        anchors.removeAll { anchor in
            guard let view = anchor.view else { return true }
            if let anchorView, view === anchorView {
                return false
            }
            return anchor.window == nil || view.window == nil
        }

        if anchors.isEmpty {
            actionAnchors.removeValue(forKey: extensionId)
        } else {
            actionAnchors[extensionId] = anchors
        }

        let liveViewIDs = Set(anchors.compactMap { anchor -> ObjectIdentifier? in
            guard let view = anchor.view else { return nil }
            return ObjectIdentifier(view)
        })
        let keptViewID = anchorView.map(ObjectIdentifier.init)

        guard var tokens = anchorObserverTokens[extensionId] else {
            return
        }

        for viewID in Array(tokens.keys) {
            guard liveViewIDs.contains(viewID) == false,
                  viewID != keptViewID
            else {
                continue
            }
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            anchorObserverTokens.removeValue(forKey: extensionId)
        } else {
            anchorObserverTokens[extensionId] = tokens
        }
    }

    private func enforceActionAnchorLimit(
        for extensionId: String,
        keeping anchorView: NSView
    ) {
        let maxAnchors = 32
        guard var anchors = actionAnchors[extensionId],
              anchors.count > maxAnchors else {
            return
        }

        var removedViewIDs: [ObjectIdentifier] = []
        while anchors.count > maxAnchors {
            guard let removalIndex = anchors.firstIndex(where: { anchor in
                guard let view = anchor.view else { return true }
                return view !== anchorView
            }) else {
                break
            }

            if let view = anchors[removalIndex].view {
                removedViewIDs.append(ObjectIdentifier(view))
            }
            anchors.remove(at: removalIndex)
        }

        actionAnchors[extensionId] = anchors

        guard var tokens = anchorObserverTokens[extensionId] else {
            return
        }

        for viewID in removedViewIDs {
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            anchorObserverTokens.removeValue(forKey: extensionId)
        } else {
            anchorObserverTokens[extensionId] = tokens
        }
    }

    private static func firstWebView(in root: NSView) -> WKWebView? {
        if let webView = root as? WKWebView {
            return webView
        }

        for subview in root.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }

    private func showErrorAlert(_ error: ExtensionError) {
        let alert = NSAlert()
        alert.messageText = "Extension Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
