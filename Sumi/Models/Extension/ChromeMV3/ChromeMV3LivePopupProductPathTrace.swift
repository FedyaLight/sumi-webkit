//
//  ChromeMV3LivePopupProductPathTrace.swift
//  Sumi
//
//  DEBUG-only sanitized live popup product-path trace for URL-hub action clicks.
//

import Foundation
#if canImport(WebKit)
import WebKit
#endif

#if DEBUG

enum ChromeMV3LivePopupProductPathKind: String, Codable, Equatable, Sendable {
    case testHarnessDirectOpen
    case urlHubActionClick
    case nativeWebKitFallback
    case developerPreviewManagerAction
}

enum ChromeMV3LivePopupFailureClassifier: String, Codable, Equatable, Sendable {
    case liveTraceNotEmitted
    case schemeHandlerNotInstalledOnPopupConfiguration
    case popupDocumentNotLoaded
    case requiredScriptResourceLoadFailure
    case requiredStyleResourceLoadFailure
    case requiredWasmResourceLoadFailure
    case requiredChunkResourceLoadFailure
    case optionalSourceMapProbeIgnored
    case networkHintIgnored
    case schemeHandlerSyncLoadUnsupported
    case generatedBundlePathMappingFailure
    case generatedBundleResourceMissing
    case mimeResolutionFailure
    case resourceReadFailure
    case bridgeNotInstalledBecauseResourcesFailed
    case scriptsNotExecutedBecauseResourcesFailed
    case popoverPresentedDOMProbeEmptyBecauseResourcesFailed
    case popoverPresentedButContentViewZeroSize
    case popoverPresentedButWebViewZeroSize
    case popoverPresentedButWebViewHidden
    case popoverPresentedButWrongWebView
    case popoverPresentedButWebViewDetached
    case popoverPresentedButURLNotLoaded
    case popoverPresentedButNavigationFailed
    case popoverPresentedButResourcesFailed
    case popoverPresentedButBridgeMissing
    case popoverPresentedButScriptsNotExecuted
    case popoverPresentedButDOMExistsButCSSHidden
    case popoverPresentedButDOMExistsButZeroVisibleText
    case popoverPresentedButDOMVisibleInProbeButNotOnScreen
    case popoverPresentedThenExtensionBlankedDOM
    case popupDismissedOrReplacedAfterPresentation
    case extensionLocalAppState
    case extensionLocalRenderState
    case livePopupVisible
    case liveTraceSampledTooEarly
    case popupDOMContentLoadedNotObserved
    case popupLoadNotObserved
    case popupBridgeJSNotInjected
    case popupBridgeInjectedTooLate
    case popupChromeAPIMissingBeforeBundle
    case popupBootstrapCheckpointMissing
    case popupBootstrapConsoleError
    case popupBootstrapUnhandledRejection
    case popupAppRootPresentButEmpty
    case popupAppRootMountedButNoVisibleText
    case popupWaitingOnStorageState
    case popupWaitingOnRuntimeMessage
    case popupWaitingOnPortResponse
    case popupWaitingOnServiceWorkerListener
    case popupWaitingOnTabsOrScripting
    case popupMissingChromeAPIAbort
    case unknown
}

struct ChromeMV3LivePopupStagedSnapshot: Codable, Equatable, Sendable {
    var stage: String
    var readyState: String
    var navigationStarted: Bool
    var navigationFinished: Bool
    var urlLoaded: Bool
    var firstJSCheckpoint: Bool
    var bridgeInstalled: Bool
    var scriptsExecuted: Bool
    var runtimeErrorCategory: String
    var consoleErrorCategory: String
    var unhandledRejectionCategory: String
    var appRootPresent: Bool
    var bodyChildCountBucket: String
    var appRootChildCountBucket: String
    var visibleTextBucket: String
    var formControlCountBucket: String
    var buttonCountBucket: String
    var ariaBusyOrLoadingCategory: String
    var storageReadCountBucket: String
    var storageWriteCountBucket: String
    var runtimeSendMessageCountBucket: String
    var runtimeConnectCountBucket: String
    var portMessageCountBucket: String
    var tabsQueryCountBucket: String
    var tabsSendMessageCountBucket: String
    var scriptingExecuteScriptCountBucket: String
    var pendingBridgeRoutesBucket: String
    var serviceWorkerOnMessageListenerCountBucket: String
    var serviceWorkerOnConnectListenerCountBucket: String

    var compactSanitizedLogLine: String {
        [
            "stage=\(stage)",
            "readyState=\(readyState)",
            "navigationStarted=\(navigationStarted)",
            "navigationFinished=\(navigationFinished)",
            "urlLoaded=\(urlLoaded)",
            "firstJSCheckpoint=\(firstJSCheckpoint)",
            "bridgeInstalled=\(bridgeInstalled)",
            "scriptsExecuted=\(scriptsExecuted)",
            "runtimeErrorCategory=\(runtimeErrorCategory)",
            "consoleErrorCategory=\(consoleErrorCategory)",
            "unhandledRejectionCategory=\(unhandledRejectionCategory)",
            "appRootPresent=\(appRootPresent)",
            "bodyChildCountBucket=\(bodyChildCountBucket)",
            "appRootChildCountBucket=\(appRootChildCountBucket)",
            "visibleTextBucket=\(visibleTextBucket)",
            "formControlCountBucket=\(formControlCountBucket)",
            "buttonCountBucket=\(buttonCountBucket)",
            "ariaBusyOrLoadingCategory=\(ariaBusyOrLoadingCategory)",
            "storageReadCountBucket=\(storageReadCountBucket)",
            "storageWriteCountBucket=\(storageWriteCountBucket)",
            "runtimeSendMessageCountBucket=\(runtimeSendMessageCountBucket)",
            "runtimeConnectCountBucket=\(runtimeConnectCountBucket)",
            "portMessageCountBucket=\(portMessageCountBucket)",
            "tabsQueryCountBucket=\(tabsQueryCountBucket)",
            "tabsSendMessageCountBucket=\(tabsSendMessageCountBucket)",
            "scriptingExecuteScriptCountBucket=\(scriptingExecuteScriptCountBucket)",
            "pendingBridgeRoutesBucket=\(pendingBridgeRoutesBucket)",
            "serviceWorkerOnMessageListenerCountBucket=\(serviceWorkerOnMessageListenerCountBucket)",
            "serviceWorkerOnConnectListenerCountBucket=\(serviceWorkerOnConnectListenerCountBucket)",
        ].joined(separator: " ")
    }
}

struct ChromeMV3LivePopupDOMCheckpoint: Codable, Equatable, Sendable {
    var readyState: String
    var visibleTextLengthBucket: String
    var controlCountBucket: String
    var bodyChildCount: Int
    var appRootPresent: Bool
    var navigationCommitted: Bool
    var visibilityCategory: String
    var backgroundCategory: String
}

struct ChromeMV3LivePopupProductPathTrace: Codable, Equatable, Sendable {
    var productPath: ChromeMV3LivePopupProductPathKind
    var expectedPopupPath: String
    var actualPopupPath: String
    var extensionIDHash: String
    var profileIDHash: String
    var loadingMode: String
    var forceNativeActionPopup: Bool
    var forceControlledCompatibilityActionPopupOff: Bool
    var compatibilityPolicyState: String
    var compatibilityPolicyReason: String
    var selectedTabBound: Bool
    var anchorKind: String
    var anchorViewAvailable: Bool
    var anchorInWindow: Bool
    var anchorBoundsSizeBucket: String
    var popupHostCreated: Bool
    var popoverPresented: Bool
    var popoverShown: Bool
    var presentationAttempts: Int
    var presentationSkipReason: String?
    var contentViewAttachedToWindow: Bool
    var contentViewSizeBucket: String
    var popoverContentSizeBucket: String
    var webViewCreated: Bool
    var webViewAttachedToHost: Bool
    var webViewFrameSizeBucket: String
    var webViewHidden: Bool
    var webViewAlphaBucket: String
    var webViewInWindowHierarchy: Bool
    var webViewDeallocated: Bool
    var loadedURLCategory: String
    var navigationStarted: Bool
    var navigationFinished: Bool
    var navigationFailed: Bool
    var urlLoadCommitted: Bool
    var generatedRootHandlerActive: Bool
    var bridgeInstalled: Bool
    var scriptsExecuted: Bool
    var firstJSCheckpointReached: Bool
    var runtimeErrorCategory: String?
    var firstDOMCheckpoint: ChromeMV3LivePopupDOMCheckpoint?
    var finalDOMCheckpoint: ChromeMV3LivePopupDOMCheckpoint?
    var dismissReason: String?
    var nativeHostLaunched: Bool
    var selectedPopupPath: String
    var requiredResourceLoadFailure: Bool
    var resourceFailureCategory: String?
    var resourceLoadBlockerCategory: String?
    var extensionClassifier: String?
    var extensionBlankedDOM: Bool
    var popupHostSessionIdentityHash: String
    var webViewIdentityHash: String
    var bridgeHandlerIdentityHash: String
    var popoverDisplaysSameWebViewAsLoaded: Bool
    var contentViewReplacedWebView: Bool
    var failureClassifier: ChromeMV3LivePopupFailureClassifier
    var stagedSnapshots: [ChromeMV3LivePopupStagedSnapshot]
    var lifecycleEventCategories: [String]
    var diagnostics: [String]

    var compactSanitizedLogLines: [String] {
        [
            "path=\(productPath.rawValue)",
            "expectedPopupPath=\(expectedPopupPath)",
            "actualPopupPath=\(actualPopupPath)",
            "extensionIDHash=\(extensionIDHash)",
            "profileIDHash=\(profileIDHash)",
            "loadingMode=\(loadingMode)",
            "policy=\(compatibilityPolicyState)",
            "policyReason=\(compatibilityPolicyReason)",
            "forceNative=\(forceNativeActionPopup)",
            "forceControlledOff=\(forceControlledCompatibilityActionPopupOff)",
            "selectedTabBound=\(selectedTabBound)",
            "anchorKind=\(anchorKind)",
            "anchorView=\(anchorViewAvailable)",
            "anchorInWindow=\(anchorInWindow)",
            "anchorBounds=\(anchorBoundsSizeBucket)",
            "hostCreated=\(popupHostCreated)",
            "popoverPresented=\(popoverPresented)",
            "popoverShown=\(popoverShown)",
            "presentationAttempts=\(presentationAttempts)",
            "presentationSkip=\(presentationSkipReason ?? "none")",
            "contentViewInWindow=\(contentViewAttachedToWindow)",
            "contentViewSize=\(contentViewSizeBucket)",
            "popoverContentSize=\(popoverContentSizeBucket)",
            "webViewCreated=\(webViewCreated)",
            "webViewAttached=\(webViewAttachedToHost)",
            "webViewFrame=\(webViewFrameSizeBucket)",
            "webViewHidden=\(webViewHidden)",
            "webViewAlpha=\(webViewAlphaBucket)",
            "webViewInHierarchy=\(webViewInWindowHierarchy)",
            "webViewDeallocated=\(webViewDeallocated)",
            "loadedURLCategory=\(loadedURLCategory)",
            "navigationStarted=\(navigationStarted)",
            "navigationFinished=\(navigationFinished)",
            "navigationFailed=\(navigationFailed)",
            "urlLoaded=\(urlLoadCommitted)",
            "generatedRootHandler=\(generatedRootHandlerActive)",
            "bridgeInstalled=\(bridgeInstalled)",
            "scriptsExecuted=\(scriptsExecuted)",
            "firstJSCheckpoint=\(firstJSCheckpointReached)",
            "runtimeError=\(runtimeErrorCategory ?? "none")",
            "firstDOMTextBucket=\(firstDOMCheckpoint?.visibleTextLengthBucket ?? "none")",
            "firstDOMVisibility=\(firstDOMCheckpoint?.visibilityCategory ?? "none")",
            "finalDOMTextBucket=\(finalDOMCheckpoint?.visibleTextLengthBucket ?? "none")",
            "finalDOMVisibility=\(finalDOMCheckpoint?.visibilityCategory ?? "none")",
            "finalDOMAppRoot=\(finalDOMCheckpoint?.appRootPresent ?? false)",
            "extensionBlankedDOM=\(extensionBlankedDOM)",
            "sessionHash=\(popupHostSessionIdentityHash)",
            "webViewHash=\(webViewIdentityHash)",
            "bridgeHash=\(bridgeHandlerIdentityHash)",
            "sameWebView=\(popoverDisplaysSameWebViewAsLoaded)",
            "contentViewReplaced=\(contentViewReplacedWebView)",
            "dismissReason=\(dismissReason ?? "none")",
            "nativeHostLaunched=\(nativeHostLaunched)",
            "selectedPopupPath=\(selectedPopupPath)",
            "requiredResourceLoadFailure=\(requiredResourceLoadFailure)",
            "resourceFailureCategory=\(resourceFailureCategory ?? "none")",
            "resourceBlocker=\(resourceLoadBlockerCategory ?? "none")",
            "extensionClassifier=\(extensionClassifier ?? "none")",
            "failureClassifier=\(failureClassifier.rawValue)",
            "stagedSnapshotCount=\(stagedSnapshots.count)",
            "lifecycle=\(lifecycleEventCategories.joined(separator: ","))",
        ]
    }
}

enum ChromeMV3LivePopupProductPathTraceBuilder {
    static let domProbeScript = """
    (() => {
      const body = document.body;
      const text = body && body.innerText ? body.innerText.trim() : "";
      const controls = document.querySelectorAll(
        'button,input,a[href],select,textarea'
      ).length;
      const appRoot = document.querySelector(
        'app-root,[data-app-root],main,#app,#root,#react'
      );
      const visibilityCategory = (() => {
        if (!body) return "detached";
        const style = window.getComputedStyle(body);
        if (style.display === "none") return "displayNone";
        if (style.visibility === "hidden") return "visibilityHidden";
        if (parseFloat(style.opacity || "1") === 0) return "opacityZero";
        const rect = body.getBoundingClientRect();
        if (rect.width <= 1 || rect.height <= 1) return "zeroSize";
        if (text.length > 0 || controls > 0) return "visible";
        if (appRoot && appRoot.children.length > 0) return "visible";
        if (body.childElementCount > 0) {
          const bg = style.backgroundColor || "";
          const fg = style.color || "";
          if (
            (bg === "rgba(0, 0, 0, 0)" || bg === "transparent")
            && (fg === "rgba(0, 0, 0, 0)" || fg === "transparent")
          ) {
            return "transparentOrWhiteOnWhite";
          }
        }
        return "unknown";
      })();
      const backgroundCategory = (() => {
        if (!body) return "none";
        const style = window.getComputedStyle(body);
        const bg = style.backgroundColor || "";
        if (bg === "rgba(0, 0, 0, 0)" || bg === "transparent") {
          return "transparent";
        }
        if (bg.includes("255, 255, 255") || bg.includes("255,255,255")) {
          return "white";
        }
        if (bg.includes("0, 0, 0") || bg.includes("0,0,0")) {
          return "dark";
        }
        return "colored";
      })();
      return JSON.stringify({
        readyState: document.readyState || "unknown",
        visibleTextLength: text.length,
        controlCount: controls,
        bodyChildCount: body ? body.childElementCount : 0,
        appRootPresent: appRoot != null,
        navigationCommitted: document.readyState === "complete"
          || document.readyState === "interactive",
        visibilityCategory: visibilityCategory,
        backgroundCategory: backgroundCategory
      });
    })();
    """

    static let stagedProbeScript = """
    (() => {
      const body = document.body;
      const text = body && body.innerText ? body.innerText.trim() : "";
      const title = document.title || "";
      const queryCount = (selector) => {
        try {
          return document.querySelectorAll(selector).length;
        } catch (_) {
          return 0;
        }
      };
      const appRoot = document.querySelector(
        'app-root,[data-app-root],main,#app,#root,#react'
      );
      const formControlCount = queryCount("input,textarea,select");
      const buttonCount = queryCount(
        "button,[role='button'],input[type='button'],input[type='submit']"
      );
      const hasBusy = queryCount(
        "[role='progressbar'],[aria-busy='true'],.spinner,.loading,.loader,[data-loading='true']"
      ) > 0;
      const hasLoadingText = /\\b(loading|please wait|initializing|syncing)\\b/i
        .test(text + " " + title);
      let ariaBusyOrLoadingCategory = "none";
      if (hasBusy && hasLoadingText) {
        ariaBusyOrLoadingCategory = "busyAndLoadingText";
      } else if (hasBusy) {
        ariaBusyOrLoadingCategory = "busy";
      } else if (hasLoadingText) {
        ariaBusyOrLoadingCategory = "loadingText";
      }
      return JSON.stringify({
        readyState: document.readyState || "unknown",
        visibleTextLength: text.length,
        formControlCount: formControlCount,
        buttonCount: buttonCount,
        bodyChildCount: body ? body.childElementCount : 0,
        appRootPresent: appRoot != null,
        appRootChildCount: appRoot ? appRoot.childElementCount : 0,
        navigationCommitted: document.readyState === "complete"
          || document.readyState === "interactive",
        ariaBusyOrLoadingCategory: ariaBusyOrLoadingCategory
      });
    })();
    """

    static func textLengthBucket(_ length: Int) -> String {
        switch length {
        case 0:
            return "0"
        case 1 ... 20:
            return "1-20"
        case 21 ... 100:
            return "21-100"
        case 101 ... 500:
            return "101-500"
        default:
            return "500+"
        }
    }

    static func controlCountBucket(_ count: Int) -> String {
        countBucket(count)
    }

    static func countBucket(_ count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case 1 ... 3:
            return "1-3"
        case 4 ... 10:
            return "4-10"
        default:
            return "10+"
        }
    }

    static func sizeBucket(width: CGFloat, height: CGFloat) -> String {
        if width <= 1 || height <= 1 {
            return "zero"
        }
        if width < 120 || height < 120 {
            return "small"
        }
        if width < 320 || height < 320 {
            return "medium"
        }
        return "large"
    }

    static func objectIdentityHash(_ object: AnyObject?) -> String {
        guard let object else { return "none" }
        return String(ObjectIdentifier(object).hashValue, radix: 16)
    }

    static func domCheckpoint(from object: [String: Any]) -> ChromeMV3LivePopupDOMCheckpoint {
        let visibleTextLength = object["visibleTextLength"] as? Int ?? 0
        let controlCount = object["controlCount"] as? Int ?? 0
        return ChromeMV3LivePopupDOMCheckpoint(
            readyState: object["readyState"] as? String ?? "unknown",
            visibleTextLengthBucket: textLengthBucket(visibleTextLength),
            controlCountBucket: controlCountBucket(controlCount),
            bodyChildCount: object["bodyChildCount"] as? Int ?? 0,
            appRootPresent: object["appRootPresent"] as? Bool ?? false,
            navigationCommitted: object["navigationCommitted"] as? Bool ?? false,
            visibilityCategory: object["visibilityCategory"] as? String ?? "unknown",
            backgroundCategory: object["backgroundCategory"] as? String ?? "unknown"
        )
    }

    static func domProbeIndicatesVisible(_ checkpoint: ChromeMV3LivePopupDOMCheckpoint)
        -> Bool
    {
        if checkpoint.visibleTextLengthBucket != "0" {
            return true
        }
        if checkpoint.controlCountBucket != "0" {
            return true
        }
        if checkpoint.visibilityCategory == "visible" {
            return true
        }
        if checkpoint.appRootPresent, checkpoint.bodyChildCount > 0 {
            return true
        }
        return false
    }

    static func loadedURLCategory(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        for event in events.reversed() {
            for diagnostic in event.diagnostics {
                if diagnostic.hasPrefix("loadScheme=") {
                    return String(diagnostic.dropFirst("loadScheme=".count))
                }
                if diagnostic.hasPrefix("urlShape=") {
                    let shape = String(diagnostic.dropFirst("urlShape=".count))
                    if shape.hasPrefix("diagnostic-extension:") {
                        return "customScheme"
                    }
                    if shape.hasPrefix("file:") {
                        return "file"
                    }
                    if shape.hasPrefix("extension:") {
                        return "extension"
                    }
                    if shape.hasPrefix("remote:") {
                        return "remote"
                    }
                    if shape.hasPrefix("https") || shape.hasPrefix("http") {
                        return "https"
                    }
                    return "other"
                }
            }
        }
        return "none"
    }

    static func navigationState(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        readyState: String? = nil,
        urlLoadCommitted: Bool = false
    ) -> (started: Bool, finished: Bool, failed: Bool) {
        let hostStarted = events.contains {
            $0.eventKind == "hostNavigationAction"
                || $0.apiName == "webkit.navigationAction"
        }
        let hostFinished = events.contains {
            $0.eventKind == "hostNavigationFinish"
                || $0.apiName == "webkit.didFinish"
        }
        let hostFailed = events.contains {
            $0.eventKind == "hostNavigationFailure"
                || $0.eventKind == "hostNavigationFail"
        }
        let domCommitted =
            readyState == "interactive"
            || readyState == "complete"
            || urlLoadCommitted
        return (
            started: hostStarted || domCommitted,
            finished: hostFinished || readyState == "complete" || urlLoadCommitted,
            failed: hostFailed
        )
    }

    static func domContentLoadedObserved(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        events.contains { event in
            event.diagnostics.contains { $0 == "reason=domcontentloaded" }
                || event.eventKind == "livePopupStagedSnapshot"
                    && event.diagnostics.contains { $0 == "stage=afterDOMContentLoaded" }
        }
    }

    static func loadEventObserved(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        events.contains { event in
            event.diagnostics.contains { $0 == "reason=window-load" }
                || event.eventKind == "livePopupStagedSnapshot"
                    && event.diagnostics.contains { $0 == "stage=afterLoadEvent" }
        }
    }

    static func firstJSCheckpointReached(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        observedMethods: [String] = []
    ) -> Bool {
        if observedMethods.isEmpty == false {
            return true
        }
        return events.contains {
            $0.eventKind == "postBootstrapCheckpoint"
                || $0.apiName == "postBootstrap.sentinel"
                || $0.eventKind == "livePopupStagedSnapshot"
                    && $0.diagnostics.contains { $0 == "stage=afterBridgeBootstrap" }
        }
    }

    static func scriptsExecuted(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        observedMethods: [String] = []
    ) -> Bool {
        if observedMethods.isEmpty == false {
            return true
        }
        return events.contains { event in
            switch event.eventKind {
            case "postBootstrapCheckpoint", "bridgeCallStarted", "extensionMethodCalled",
                "consoleError", "unhandledRejection", "popup.renderTimeline",
                "livePopupStagedSnapshot":
                return true
            default:
                return false
            }
        }
    }

    static func runtimeErrorCategory(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        if events.contains(where: {
            $0.eventKind == "scriptError"
                || $0.eventKind == "windowError"
        }) {
            return "scriptError"
        }
        if events.contains(where: {
            $0.eventKind.contains("reject")
                || $0.eventKind == "unhandledRejection"
        }) {
            return "unhandledRejection"
        }
        if events.contains(where: {
            $0.eventKind == "consoleError"
                || ($0.resultClassifier?.contains("error") == true)
        }) {
            return "consoleOrRuntimeError"
        }
        return "none"
    }

    static func consoleErrorCategory(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        let consoleErrors = events.filter {
            $0.eventKind == "consoleError"
                || $0.eventKind == "scriptError"
                || $0.eventKind == "windowError"
        }
        guard consoleErrors.isEmpty == false else { return "none" }
        if consoleErrors.contains(where: {
            $0.resultClassifier?.localizedCaseInsensitiveContains("missing") == true
                || $0.firstMissingAPIOrPermissionOrLifecycleError != nil
        }) {
            return "missingAPIOrPermission"
        }
        return "consoleError"
    }

    static func unhandledRejectionCategory(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        events.contains { $0.eventKind == "unhandledRejection" }
            ? "unhandledRejection" : "none"
    }

    static func bridgeBootstrapProbeObserved(
        phase: String,
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        events.contains { event in
            event.eventKind == "bridgeBootstrapProbe"
                && event.diagnostics.contains { $0 == "phase=\(phase)" }
        }
    }

    static func bridgeBootstrapProbeDiagnostic(
        _ key: String,
        phase: String,
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        guard
            let event = events.last(where: { probe in
                probe.eventKind == "bridgeBootstrapProbe"
                    && probe.diagnostics.contains { $0 == "phase=\(phase)" }
            }),
            let diagnostic = event.diagnostics.first(where: {
                $0.hasPrefix("\(key)=")
            })
        else { return nil }
        return String(diagnostic.dropFirst("\(key)=".count))
    }

    static func bridgeInjectedTooLate(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        if bridgeBootstrapProbeDiagnostic(
            "bridgeInjectedTooLateCandidate",
            phase: "atDocumentStartBridgeInjection",
            from: events
        ) == "true" {
            return true
        }
        if bridgeBootstrapProbeDiagnostic(
            "chromePresentBeforeBridge",
            phase: "atDocumentStartBridgeInjection",
            from: events
        ) == "true" {
            return true
        }
        if bridgeBootstrapProbeDiagnostic(
            "browserPresentBeforeBridge",
            phase: "atDocumentStartBridgeInjection",
            from: events
        ) == "true" {
            return true
        }
        let readyState = bridgeBootstrapProbeDiagnostic(
            "readyState",
            phase: "atDocumentStartBridgeInjection",
            from: events
        )
        if let readyState, readyState != "loading", readyState != "unknown" {
            return true
        }
        return false
    }

    static func firstMissingChromeAPIBeforeBundle(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        let missing = bridgeBootstrapProbeDiagnostic(
            "firstMissingAPI",
            phase: "beforeFirstExtensionScript",
            from: events
        )
        guard let missing, missing != "none" else { return nil }
        return missing
    }

    struct APIRouteCountBuckets: Equatable, Sendable {
        var storageRead: Int = 0
        var storageWrite: Int = 0
        var runtimeSendMessage: Int = 0
        var runtimeConnect: Int = 0
        var portMessage: Int = 0
        var tabsQuery: Int = 0
        var tabsSendMessage: Int = 0
        var scriptingExecuteScript: Int = 0
        var pendingBridgeRoutes: Int = 0
        var serviceWorkerOnMessageListener: Int = 0
        var serviceWorkerOnConnectListener: Int = 0
    }

    static func apiRouteCountBuckets(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        pendingRoutes: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = []
    ) -> APIRouteCountBuckets {
        var buckets = APIRouteCountBuckets()
        buckets.pendingBridgeRoutes = pendingRoutes.count
        for event in events {
            let api = event.apiName.lowercased()
            switch event.eventKind {
            case "extensionMethodCalled", "bridgeCallStarted", "bridgeCallResolved",
                "bridgeCallRejected":
                if api.contains("storage.local.get")
                    || api.contains("storage.session.get")
                    || api.contains("storage.sync.get")
                    || api.contains("storage.managed.get")
                {
                    buckets.storageRead += 1
                }
                if api.contains("storage.local.set")
                    || api.contains("storage.session.set")
                    || api.contains("storage.sync.set")
                    || api.contains("storage.local.remove")
                    || api.contains("storage.session.remove")
                    || api.contains("storage.sync.remove")
                    || api.contains("storage.local.clear")
                {
                    buckets.storageWrite += 1
                }
                if api.contains("runtime.sendmessage") {
                    buckets.runtimeSendMessage += 1
                }
                if api.contains("runtime.connect") {
                    buckets.runtimeConnect += 1
                }
                if api.contains("port.postmessage") || api.contains("port.onmessage") {
                    buckets.portMessage += 1
                }
                if api.contains("tabs.query") {
                    buckets.tabsQuery += 1
                }
                if api.contains("tabs.sendmessage") {
                    buckets.tabsSendMessage += 1
                }
                if api.contains("scripting.executescript") {
                    buckets.scriptingExecuteScript += 1
                }
                if api.contains("runtime.onmessage") {
                    buckets.serviceWorkerOnMessageListener += 1
                }
                if api.contains("runtime.onconnect") {
                    buckets.serviceWorkerOnConnectListener += 1
                }
            default:
                break
            }
        }
        return buckets
    }

    static func buildStagedSnapshot(
        stage: String,
        domObject: [String: Any],
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        pendingRoutes: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        observedMethods: [String],
        bridgeInstalled: Bool,
        navigationStarted: Bool,
        navigationFinished: Bool
    ) -> ChromeMV3LivePopupStagedSnapshot {
        let readyState = domObject["readyState"] as? String ?? "unknown"
        let urlLoaded = domObject["navigationCommitted"] as? Bool ?? false
        let buckets = apiRouteCountBuckets(
            from: routeEvents,
            pendingRoutes: pendingRoutes
        )
        return ChromeMV3LivePopupStagedSnapshot(
            stage: stage,
            readyState: readyState,
            navigationStarted: navigationStarted,
            navigationFinished: navigationFinished,
            urlLoaded: urlLoaded,
            firstJSCheckpoint: firstJSCheckpointReached(
                from: routeEvents,
                observedMethods: observedMethods
            ),
            bridgeInstalled: bridgeInstalled,
            scriptsExecuted: scriptsExecuted(
                from: routeEvents,
                observedMethods: observedMethods
            ),
            runtimeErrorCategory: runtimeErrorCategory(from: routeEvents),
            consoleErrorCategory: consoleErrorCategory(from: routeEvents),
            unhandledRejectionCategory: unhandledRejectionCategory(from: routeEvents),
            appRootPresent: domObject["appRootPresent"] as? Bool ?? false,
            bodyChildCountBucket: countBucket(
                domObject["bodyChildCount"] as? Int ?? 0
            ),
            appRootChildCountBucket: countBucket(
                domObject["appRootChildCount"] as? Int ?? 0
            ),
            visibleTextBucket: textLengthBucket(
                domObject["visibleTextLength"] as? Int ?? 0
            ),
            formControlCountBucket: countBucket(
                domObject["formControlCount"] as? Int ?? 0
            ),
            buttonCountBucket: countBucket(
                domObject["buttonCount"] as? Int ?? 0
            ),
            ariaBusyOrLoadingCategory:
                domObject["ariaBusyOrLoadingCategory"] as? String ?? "none",
            storageReadCountBucket: countBucket(buckets.storageRead),
            storageWriteCountBucket: countBucket(buckets.storageWrite),
            runtimeSendMessageCountBucket: countBucket(buckets.runtimeSendMessage),
            runtimeConnectCountBucket: countBucket(buckets.runtimeConnect),
            portMessageCountBucket: countBucket(buckets.portMessage),
            tabsQueryCountBucket: countBucket(buckets.tabsQuery),
            tabsSendMessageCountBucket: countBucket(buckets.tabsSendMessage),
            scriptingExecuteScriptCountBucket: countBucket(
                buckets.scriptingExecuteScript
            ),
            pendingBridgeRoutesBucket: countBucket(buckets.pendingBridgeRoutes),
            serviceWorkerOnMessageListenerCountBucket: countBucket(
                buckets.serviceWorkerOnMessageListener
            ),
            serviceWorkerOnConnectListenerCountBucket: countBucket(
                buckets.serviceWorkerOnConnectListener
            )
        )
    }

    static func synthesizeStagedSnapshots(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        observedMethods: [String],
        bridgeInstalled: Bool,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?
    ) -> [ChromeMV3LivePopupStagedSnapshot] {
        var snapshots: [ChromeMV3LivePopupStagedSnapshot] = []
        let domObject: [String: Any] = [
            "readyState": finalDOM?.readyState ?? "unknown",
            "visibleTextLength": bucketLowerBound(finalDOM?.visibleTextLengthBucket),
            "formControlCount": bucketLowerBound(finalDOM?.controlCountBucket),
            "buttonCount": 0,
            "bodyChildCount": finalDOM?.bodyChildCount ?? 0,
            "appRootPresent": finalDOM?.appRootPresent ?? false,
            "appRootChildCount": finalDOM?.appRootPresent == true
                ? max(0, finalDOM?.bodyChildCount ?? 0) : 0,
            "navigationCommitted": finalDOM?.navigationCommitted ?? false,
            "ariaBusyOrLoadingCategory": "none",
        ]
        let navigation = navigationState(
            from: events,
            readyState: finalDOM?.readyState,
            urlLoadCommitted: finalDOM?.navigationCommitted ?? false
        )
        func append(stage: String, prefixCount: Int) {
            let prefix = Array(events.prefix(prefixCount))
            snapshots.append(
                buildStagedSnapshot(
                    stage: stage,
                    domObject: domObject,
                    routeEvents: prefix,
                    pendingRoutes: [],
                    observedMethods: observedMethods,
                    bridgeInstalled: bridgeInstalled,
                    navigationStarted: navigation.started,
                    navigationFinished: navigation.finished
                )
            )
        }
        if let index = events.firstIndex(where: {
            $0.eventKind == "hostNavigationAction"
                || $0.apiName == "webkit.navigationAction"
        }) {
            append(stage: "afterURLAssignment", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.diagnostics.contains { $0 == "reason=domcontentloaded" }
                || ($0.eventKind == "livePopupStagedSnapshot"
                    && $0.diagnostics.contains { $0 == "stage=afterDOMContentLoaded" })
        }) {
            append(stage: "afterDOMContentLoaded", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.diagnostics.contains { $0 == "reason=window-load" }
                || ($0.eventKind == "livePopupStagedSnapshot"
                    && $0.diagnostics.contains { $0 == "stage=afterLoadEvent" })
        }) {
            append(stage: "afterLoadEvent", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.eventKind == "bridgeBootstrapProbe"
                && $0.diagnostics.contains { $0 == "phase=atDocumentStartBridgeInjection" }
        }) {
            append(stage: "atDocumentStartBridgeInjection", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.eventKind == "bridgeBootstrapProbe"
                && $0.diagnostics.contains { $0 == "phase=beforeFirstExtensionScript" }
        }) {
            append(stage: "beforeFirstExtensionScript", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.eventKind == "postBootstrapCheckpoint"
                || ($0.eventKind == "livePopupStagedSnapshot"
                    && $0.diagnostics.contains { $0 == "stage=afterBridgeBootstrap" })
        }) {
            append(stage: "afterBridgeBootstrap", prefixCount: index + 1)
        }
        for (stage, marker) in [
            ("after250ms", "reason=timer-250ms"),
            ("after1000ms", "reason=timer-900ms"),
            ("after3000ms", "reason=timer-3500ms"),
        ] {
            if let index = events.firstIndex(where: {
                $0.diagnostics.contains { $0 == marker }
                    || ($0.eventKind == "livePopupStagedSnapshot"
                        && $0.diagnostics.contains { $0 == "stage=\(stage)" })
            }) {
                append(stage: stage, prefixCount: index + 1)
            }
        }
        if let index = events.firstIndex(where: {
            $0.eventKind == "consoleError" || $0.eventKind == "scriptError"
        }) {
            append(stage: "onConsoleError", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: { $0.eventKind == "unhandledRejection" }) {
            append(stage: "onUnhandledRejection", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.apiName.lowercased().contains("storage.")
        }) {
            append(stage: "onStorageRoute", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.apiName.lowercased().contains("runtime.")
        }) {
            append(stage: "onRuntimeRoute", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.apiName.lowercased().contains("port.")
                || $0.apiName.lowercased().contains("runtime.connect")
        }) {
            append(stage: "onPortRoute", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.apiName.lowercased().contains("tabs.")
        }) {
            append(stage: "onTabsRoute", prefixCount: index + 1)
        }
        if let index = events.firstIndex(where: {
            $0.apiName.lowercased().contains("scripting.")
        }) {
            append(stage: "onScriptingRoute", prefixCount: index + 1)
        }
        return snapshots
    }

    private static func bucketLowerBound(_ bucket: String?) -> Int {
        switch bucket {
        case "1-20": return 1
        case "21-100": return 21
        case "101-500": return 101
        case "500+": return 500
        case "1-3": return 1
        case "4-10": return 4
        case "10+": return 10
        default: return 0
        }
    }

    static let standardStagedSummaryStageOrder: [String] = [
        "afterURLAssignment",
        "atDocumentStartBridgeInjection",
        "beforeFirstExtensionScript",
        "afterDOMContentLoaded",
        "afterLoadEvent",
        "after250ms",
        "after1000ms",
        "after3000ms",
    ]

    static let routeTriggeredStagedSummaryStageOrder: [String] = [
        "onConsoleError",
        "onUnhandledRejection",
        "onStorageRoute",
        "onRuntimeRoute",
        "onPortRoute",
        "onTabsRoute",
        "onScriptingRoute",
        "afterBridgeBootstrap",
    ]

    static func stagedSummaryLogLines(
        trace: ChromeMV3LivePopupProductPathTrace,
        extensionLabel: String
    ) -> [String] {
        var lines: [String] = [
            "BEGIN live-popup-staged-summary extension=\(extensionLabel) failureClassifier=\(trace.failureClassifier.rawValue) loadingMode=\(trace.loadingMode) firstJSCheckpoint=\(trace.firstJSCheckpointReached)",
        ]
        var emittedStages: Set<String> = []
        for stage in standardStagedSummaryStageOrder
            + routeTriggeredStagedSummaryStageOrder
        {
            guard let snapshot = trace.stagedSnapshots.last(where: { $0.stage == stage }),
                  emittedStages.insert(stage).inserted
            else { continue }
            lines.append(snapshot.compactSanitizedLogLine)
        }
        for snapshot in trace.stagedSnapshots where emittedStages.contains(snapshot.stage) == false {
            lines.append(snapshot.compactSanitizedLogLine)
            emittedStages.insert(snapshot.stage)
        }
        lines.append("END live-popup-staged-summary")
        return lines
    }

    static func stagedSnapshotIndicatesVisible(
        _ snapshot: ChromeMV3LivePopupStagedSnapshot
    ) -> Bool {
        snapshot.visibleTextBucket != "0"
            || snapshot.formControlCountBucket != "0"
            || snapshot.buttonCountBucket != "0"
    }

    static func stagedSnapshotShowsExecutedScripts(
        _ snapshots: [ChromeMV3LivePopupStagedSnapshot]
    ) -> Bool {
        snapshots.contains { $0.scriptsExecuted && $0.firstJSCheckpoint }
            || snapshots.contains { $0.scriptsExecuted }
    }

    static func reconciledScriptsExecuted(
        trace: ChromeMV3LivePopupProductPathTrace
    ) -> Bool {
        trace.scriptsExecuted
            || stagedSnapshotShowsExecutedScripts(trace.stagedSnapshots)
    }

    static func reconciledFirstJSCheckpoint(
        trace: ChromeMV3LivePopupProductPathTrace
    ) -> Bool {
        trace.firstJSCheckpointReached
            || trace.stagedSnapshots.contains { $0.firstJSCheckpoint }
    }

    static func reconcileTraceWithStagedSnapshots(
        _ trace: ChromeMV3LivePopupProductPathTrace
    ) -> ChromeMV3LivePopupProductPathTrace {
        guard trace.stagedSnapshots.isEmpty == false else { return trace }
        var reconciled = trace
        if stagedSnapshotShowsExecutedScripts(trace.stagedSnapshots) {
            reconciled.scriptsExecuted = true
        }
        if trace.stagedSnapshots.contains(where: { $0.firstJSCheckpoint }) {
            reconciled.firstJSCheckpointReached = true
        }
        if let latest = preferredStagedSnapshot(trace.stagedSnapshots) {
            if latest.runtimeErrorCategory != "none" {
                reconciled.runtimeErrorCategory = latest.runtimeErrorCategory
            }
        }
        return reconciled
    }

    static func preferredStagedSnapshot(
        _ snapshots: [ChromeMV3LivePopupStagedSnapshot]
    ) -> ChromeMV3LivePopupStagedSnapshot? {
        let priority = [
            "after3000ms", "after1000ms", "after250ms", "afterLoadEvent",
            "afterDOMContentLoaded", "afterBridgeBootstrap",
            "beforeFirstExtensionScript", "atDocumentStartBridgeInjection",
            "afterURLAssignment",
        ]
        for stage in priority {
            if let match = snapshots.last(where: { $0.stage == stage }) {
                return match
            }
        }
        return snapshots.last
    }

    static func classifyBootstrapFailure(
        trace: ChromeMV3LivePopupProductPathTrace,
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = []
    ) -> ChromeMV3LivePopupFailureClassifier? {
        let final = trace.finalDOMCheckpoint
        let snapshots = trace.stagedSnapshots
        let latest = preferredStagedSnapshot(snapshots)
        let domContentLoadedSeen =
            snapshots.contains { $0.stage == "afterDOMContentLoaded" }
        let loadEventSeen = snapshots.contains { $0.stage == "afterLoadEvent" }

        if routeEvents.isEmpty == false {
            if trace.bridgeInstalled,
               bridgeBootstrapProbeObserved(
                   phase: "atDocumentStartBridgeInjection",
                   from: routeEvents
               ) == false
            {
                return .popupBridgeJSNotInjected
            }
            if bridgeInjectedTooLate(from: routeEvents) {
                return .popupBridgeInjectedTooLate
            }
            if firstMissingChromeAPIBeforeBundle(from: routeEvents) != nil {
                return .popupChromeAPIMissingBeforeBundle
            }
        }

        if let latest {
            if latest.consoleErrorCategory == "missingAPIOrPermission" {
                return .popupMissingChromeAPIAbort
            }
            if latest.consoleErrorCategory != "none" {
                return .popupBootstrapConsoleError
            }
            if latest.unhandledRejectionCategory != "none" {
                return .popupBootstrapUnhandledRejection
            }
            if latest.pendingBridgeRoutesBucket != "0" {
                if latest.storageReadCountBucket != "0"
                    || latest.storageWriteCountBucket != "0"
                {
                    return .popupWaitingOnStorageState
                }
                if latest.runtimeSendMessageCountBucket != "0" {
                    return .popupWaitingOnRuntimeMessage
                }
                if latest.portMessageCountBucket != "0"
                    || latest.runtimeConnectCountBucket != "0"
                {
                    return .popupWaitingOnPortResponse
                }
                if latest.tabsQueryCountBucket != "0"
                    || latest.tabsSendMessageCountBucket != "0"
                    || latest.scriptingExecuteScriptCountBucket != "0"
                {
                    return .popupWaitingOnTabsOrScripting
                }
            }
            if latest.serviceWorkerOnMessageListenerCountBucket != "0"
                || latest.serviceWorkerOnConnectListenerCountBucket != "0"
            {
                return .popupWaitingOnServiceWorkerListener
            }
            if let early = snapshots.first(where: { $0.stage == "after250ms" }),
               let late = snapshots.last(where: { $0.stage == "after3000ms" }),
               early.visibleTextBucket == "0",
               late.visibleTextBucket != "0"
            {
                return .liveTraceSampledTooEarly
            }
            if latest.firstJSCheckpoint == false {
                return .popupBootstrapCheckpointMissing
            }
            if latest.urlLoaded,
               domContentLoadedSeen == false,
               latest.readyState == "loading"
            {
                return .popupDOMContentLoadedNotObserved
            }
            if latest.urlLoaded,
               loadEventSeen == false,
               latest.readyState != "complete"
            {
                return .popupLoadNotObserved
            }
            if latest.appRootPresent,
               latest.appRootChildCountBucket != "0",
               latest.visibleTextBucket == "0",
               latest.formControlCountBucket == "0"
            {
                return .popupAppRootMountedButNoVisibleText
            }
            if latest.appRootPresent,
               latest.visibleTextBucket == "0",
               latest.formControlCountBucket == "0"
            {
                return .popupAppRootPresentButEmpty
            }
        }

        if reconciledFirstJSCheckpoint(trace: trace) == false {
            return .popupBootstrapCheckpointMissing
        }
        if final?.appRootPresent == true,
           final?.visibleTextLengthBucket == "0"
        {
            return .popupAppRootPresentButEmpty
        }
        return nil
    }

    struct PostParseSanitizedDiagnostics: Equatable, Sendable {
        var parseExecutionClassifier: String
        var executeScriptResultCategory: String
        var contentScriptListenerCategory: String
        var contentScriptMessagingCategory: String
        var serviceWorkerListenerCategory: String
        var popupMessagingCategory: String
        var storageCategory: String
        var pendingRouteBucket: String
        var finalVisibleTextBucket: String
        var finalAppRootPresent: Bool
        var firstBrowserBlocker: String
        var continuationBlocker: String
        var filesExecuted: Bool
        var pendingRouteCount: Int
        var appStateClassification: String

        var logLines: [String] {
            [
                "postParseParseExecutionClassifier=\(parseExecutionClassifier)",
                "postParseExecuteScriptResultCategory=\(executeScriptResultCategory)",
                "postParseContentScriptListenerCategory=\(contentScriptListenerCategory)",
                "postParseContentScriptMessagingCategory=\(contentScriptMessagingCategory)",
                "postParseServiceWorkerListenerCategory=\(serviceWorkerListenerCategory)",
                "postParsePopupMessagingCategory=\(popupMessagingCategory)",
                "postParseStorageCategory=\(storageCategory)",
                "postParsePendingRouteBucket=\(pendingRouteBucket)",
                "postParseFinalVisibleTextBucket=\(finalVisibleTextBucket)",
                "postParseFinalAppRootPresent=\(finalAppRootPresent)",
                "postParseFirstBrowserBlocker=\(firstBrowserBlocker)",
                "postParseContinuationBlocker=\(continuationBlocker)",
            ]
        }
    }

    static func postParseFilesExecutedObserved(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Bool {
        snapshot.callRecords.contains { record in
            record.namespace == "scripting"
                && record.methodName == "executeScript"
                && record.succeeded
                && record.diagnostics.contains {
                    $0.contains("executionClassifier=filesExecuted")
                }
        }
        || snapshot.sanitizedBridgeRouteRecords.contains { route in
            route.apiName == "scripting.executeScript"
                && (
                    route.diagnostics.contains {
                        $0.contains("executionClassifier=filesExecuted")
                    }
                    || route.resultClassifier.contains("executeScriptSucceeded")
                )
        }
    }

    static func postParseSanitizedDiagnostics(
        bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?
    ) -> PostParseSanitizedDiagnostics? {
        guard let snapshot = bridgeSnapshot,
              postParseFilesExecutedObserved(in: snapshot)
        else { return nil }

        let trace = snapshot.appStateDependencyTrace.correlationSummary
        let subsequentRoutes = postParseRoutes(in: snapshot)
        let serviceWorkerListeners =
            postParseServiceWorkerListenerCounts(in: snapshot)
        let contentScriptEndpoints = snapshot.contentScriptEndpointSummary
        let contentScriptListenerRegistered =
            (contentScriptEndpoints?.messageListenerEndpointCount ?? 0) > 0
            || subsequentRoutes.contains {
                $0.targetContext == "contentScript" && $0.listenerCount > 0
            }
        let continuationEvents = snapshot.jsDebugRouteEvents.filter {
            $0.eventKind == "executeScriptContinuationCheckpoint"
        }
        let continuationBlocker =
            classifyPostParseContinuationBlocker(
                snapshot: snapshot,
                continuationEvents: continuationEvents,
                finalDOM: finalDOM
            )
        let firstBrowserBlocker = classifyPostParseBrowserBlocker(
            snapshot: snapshot,
            subsequentRoutes: subsequentRoutes,
            contentScriptListenerRegistered: contentScriptListenerRegistered,
            serviceWorkerListeners: serviceWorkerListeners,
            trace: trace,
            finalDOM: finalDOM
        )
        let executeScriptRecord = snapshot.callRecords.last {
            $0.namespace == "scripting" && $0.methodName == "executeScript"
        }
        let parseExecutionClassifier =
            executeScriptRecord?.diagnostics.first {
                $0.hasPrefix("executionClassifier=")
            }?.replacingOccurrences(of: "executionClassifier=", with: "")
            ?? "filesExecuted"
        let executeScriptResultCategory =
            continuationEvents.compactMap(\.resultClassifier).last
            ?? executeScriptRecord?.lastErrorCode
            ?? "none"
        let contentScriptListenerCategory =
            contentScriptListenerRegistered
            ? "listenerRegistered"
            : "listenerMissing"
        let contentScriptMessagingCategory =
            categorizePostParseRoutes(
                subsequentRoutes.filter {
                    $0.targetContext == "contentScript"
                        || $0.apiName == "tabs.sendMessage"
                }
            )
        let serviceWorkerListenerCategory =
            "onMessage=\(serviceWorkerListeners.onMessage),onConnect=\(serviceWorkerListeners.onConnect)"
        let popupMessagingCategory = categorizePostParseRoutes(
            subsequentRoutes.filter {
                ["runtime.sendMessage", "runtime.connect"].contains($0.apiName)
                    && $0.sourceContext != "contentScript"
            }
        )
        let storageCategory: String
        if trace.writtenKeyHashesWithoutObservedOnChangedDelivery.isEmpty
            == false
        {
            storageCategory = "onChangedMissed"
        } else if trace.popupReadKeyHashesNeverWritten.isEmpty == false {
            storageCategory = "readNoWriter"
        } else if trace.popupReadKeyHashesWrittenByServiceWorker.isEmpty
            == false
        {
            storageCategory = "serviceWorkerWriteObserved"
        } else if trace.storageOnChangedReachedRegisteredListeners {
            storageCategory = "onChangedDelivered"
        } else {
            storageCategory = "noObservableWrite"
        }

        return PostParseSanitizedDiagnostics(
            parseExecutionClassifier: parseExecutionClassifier,
            executeScriptResultCategory: executeScriptResultCategory,
            contentScriptListenerCategory: contentScriptListenerCategory,
            contentScriptMessagingCategory: contentScriptMessagingCategory,
            serviceWorkerListenerCategory: serviceWorkerListenerCategory,
            popupMessagingCategory: popupMessagingCategory,
            storageCategory: storageCategory,
            pendingRouteBucket: countBucket(trace.pendingRouteCount),
            finalVisibleTextBucket: finalDOM?.visibleTextLengthBucket ?? "0",
            finalAppRootPresent: finalDOM?.appRootPresent ?? false,
            firstBrowserBlocker: firstBrowserBlocker,
            continuationBlocker: continuationBlocker,
            filesExecuted: true,
            pendingRouteCount: trace.pendingRouteCount,
            appStateClassification: trace.classification
        )
    }

    static func deriveExtensionClassifier(
        bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?
    ) -> String? {
        guard let snapshot = bridgeSnapshot else { return nil }
        let correlation =
            snapshot.appStateDependencyTrace.correlationSummary.classification
        guard let postParse = postParseSanitizedDiagnostics(
            bridgeSnapshot: snapshot,
            finalDOM: finalDOM
        ) else {
            return correlation == "notClassified" ? nil : correlation
        }

        let browserBlocker = postParse.firstBrowserBlocker
        if browserBlocker != "unknown",
           browserBlocker != "appStateWaitWithNoObservableBrowserDependency"
        {
            return correlation == "notClassified" ? nil : correlation
        }

        if postParse.continuationBlocker == "popupLocalAppStateBranch"
            || postParse.appStateClassification == "appStateWaitWithNoWriter"
            || postParse.storageCategory == "readNoWriter"
        {
            return "extensionLocalAppState"
        }

        if finalDOM.map(domProbeIndicatesVisible) != true,
           postParse.pendingRouteCount == 0,
           postParse.filesExecuted
        {
            return "extensionLocalRenderState"
        }

        return correlation == "notClassified" ? nil : correlation
    }

    private static func postParseExecuteScriptRouteIndex(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Int? {
        snapshot.sanitizedBridgeRouteRecords.lastIndex { route in
            guard route.apiName == "scripting.executeScript" else {
                return false
            }
            return route.diagnostics.contains {
                $0.contains("executionClassifier=filesExecuted")
            } || route.resultClassifier.contains("executeScriptSucceeded")
        }
    }

    private static func postParseRoutes(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] {
        guard let index = postParseExecuteScriptRouteIndex(in: snapshot)
        else { return [] }
        return Array(snapshot.sanitizedBridgeRouteRecords[(index + 1)...])
    }

    private static func postParseServiceWorkerListenerCounts(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> (onMessage: Int, onConnect: Int) {
        var onMessage = 0
        var onConnect = 0
        for route in snapshot.sanitizedBridgeRouteRecords {
            if route.apiName == "runtime.onMessage"
                || route.diagnostics.contains(where: {
                    $0.contains("runtime.onMessage listener")
                })
            {
                onMessage = max(onMessage, route.listenerCount)
            }
            if route.apiName == "runtime.onConnect"
                || route.diagnostics.contains(where: {
                    $0.contains("runtime.onConnect listener")
                })
            {
                onConnect = max(onConnect, route.listenerCount)
            }
        }
        return (onMessage, onConnect)
    }

    private static func categorizePostParseRoutes(
        _ routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord]
    ) -> String {
        guard routes.isEmpty == false else { return "none" }
        if routes.contains(where: postParseRouteFailed) {
            return "failed"
        }
        if routes.contains(where: { $0.listenerInvoked }) {
            return "delivered"
        }
        return "observed"
    }

    private static func postParseRouteFailed(
        _ route: ChromeMV3PopupOptionsSanitizedBridgeRouteRecord
    ) -> Bool {
        if route.firstMissingAPIOrPermissionOrLifecycleError != nil {
            return true
        }
        switch route.resultClassifier {
        case "permissionDenied", "noReceivingEnd", "noListener", "blocked",
            "listenerThrew", "listenerPresentButNoResponse":
            return true
        default:
            return false
        }
    }

    private static func classifyPostParseRouteBlocker(
        _ route: ChromeMV3PopupOptionsSanitizedBridgeRouteRecord,
        contentScriptListenerRegistered: Bool,
        serviceWorkerOnMessageCount: Int,
        serviceWorkerOnConnectCount: Int
    ) -> String? {
        guard postParseRouteFailed(route) else { return nil }
        switch route.apiName {
        case "runtime.sendMessage":
            if route.sourceContext == "contentScript" {
                return "contentScriptToServiceWorkerRouteDropped"
            }
            if serviceWorkerOnMessageCount == 0
                && route.listenerCount == 0
                && route.listenerInvoked == false
            {
                return "serviceWorkerOnMessageMissing"
            }
            return "popupToServiceWorkerRouteDropped"
        case "runtime.connect":
            if serviceWorkerOnConnectCount == 0
                && route.listenerCount == 0
                && route.listenerInvoked == false
            {
                return "serviceWorkerOnConnectMissing"
            }
            return "popupToServiceWorkerRouteDropped"
        case "tabs.sendMessage":
            if contentScriptListenerRegistered == false {
                return "contentScriptListenerMissing"
            }
            return "popupToContentScriptRouteDropped"
        case "tabs.query", "tabs.getCurrent":
            return "tabsTargetMappingWrong"
        default:
            if route.targetContext == "contentScript" {
                return "popupToContentScriptRouteDropped"
            }
            if route.targetContext == "serviceWorker" {
                return "popupToServiceWorkerRouteDropped"
            }
            return nil
        }
    }

    private static func classifyPostParseBrowserBlocker(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        subsequentRoutes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        contentScriptListenerRegistered: Bool,
        serviceWorkerListeners: (onMessage: Int, onConnect: Int),
        trace: ChromeMV3AppStateDependencyCorrelationSummary,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?
    ) -> String {
        if subsequentRoutes.contains(where: { $0.apiName == "tabs.sendMessage" }),
           contentScriptListenerRegistered == false
        {
            return "contentScriptListenerMissing"
        }

        if let tabsSendMessageRoute = subsequentRoutes.first(where: {
            $0.apiName == "tabs.sendMessage"
        }),
           contentScriptListenerRegistered,
           tabsSendMessageRoute.listenerInvoked == false,
           postParseRouteFailed(tabsSendMessageRoute)
        {
            return "messageBeforeContentScriptReady"
        }

        for route in subsequentRoutes {
            if let blocker = classifyPostParseRouteBlocker(
                route,
                contentScriptListenerRegistered:
                    contentScriptListenerRegistered,
                serviceWorkerOnMessageCount: serviceWorkerListeners.onMessage,
                serviceWorkerOnConnectCount: serviceWorkerListeners.onConnect
            ) {
                return blocker
            }
        }

        if snapshot.pendingUnresolvedJSDebugRoutes.isEmpty == false {
            if subsequentRoutes.contains(where: {
                $0.apiName == "tabs.sendMessage"
            }) {
                return "popupToContentScriptRouteDropped"
            }
            return "popupToServiceWorkerRouteDropped"
        }

        if trace.classification == "appStateWaitWithNoWriter"
            || (
                trace.repeatedEmptyReadKeyHashes.isEmpty == false
                    && trace.popupReadKeyHashesNeverWritten.isEmpty == false
            )
        {
            return "storageAppStateReadNoWriter"
        }
        if trace.writtenKeyHashesWithoutObservedOnChangedDelivery.isEmpty
            == false
        {
            return "storageOnChangedMissed"
        }
        if trace.popupReadKeyHashesWrittenByServiceWorker.isEmpty == false
            && trace.popupReadKeyHashesNeverWritten.isEmpty == false
        {
            return "storageWriteNotVisibleToPopup"
        }
        if trace.missingAPIsObserved.isEmpty == false {
            return "missingNarrowChromeAPI"
        }
        if trace.networkOrAuthDependencyObserved {
            return "networkOrAuthWait"
        }
        if trace.classification == "appStateWaitWithNoObservableDependency"
            || trace.classification
                == "appStateWaitWithNoObservableBrowserDependency"
        {
            return "appStateWaitWithNoObservableBrowserDependency"
        }

        if let finalDOM,
           finalDOM.appRootPresent,
           finalDOM.visibleTextLengthBucket == "0"
        {
            return "appStateWaitWithNoObservableBrowserDependency"
        }

        return "unknown"
    }

    private static func classifyPostParseContinuationBlocker(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        continuationEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?
    ) -> String {
        guard continuationEvents.isEmpty == false else {
            return "noPopupContinuationObserved"
        }
        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationException"
        }) {
            return "popupContinuationException"
        }
        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationUnhandledRejection"
        }) {
            return "popupContinuationUnhandledRejection"
        }
        let popupResolved = continuationEvents.contains {
            $0.diagnostics.contains("phase=popupPromiseResolved")
                || $0.diagnostics.contains("phase=popupCallbackInvoked")
        }
        if popupResolved,
           finalDOM.map(domProbeIndicatesVisible) != true
        {
            let localBranch = continuationEvents.compactMap { event in
                event.diagnostics.first { $0.hasPrefix("localBranchClassifier=") }
                    .map { String($0.dropFirst("localBranchClassifier=".count)) }
            }.last
            if localBranch == "appState" {
                return "popupLocalAppStateBranch"
            }
            return "popupRenderGateNoStateTransition"
        }
        return "none"
    }

    static func extensionBlankedDOM(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        events.contains { event in
            (event.apiName == "popup.renderTimeline"
                && event.resultClassifier?.contains("blankingDetected=true") == true)
                || event.diagnostics.contains { $0.contains("blankingDetected=true") }
        }
    }

    static func resourceFailureClassifier(
        blocker: String?,
        resourceCategory: String?,
        loadingMode: String,
        generatedRootHandlerActive: Bool
    ) -> ChromeMV3LivePopupFailureClassifier? {
        guard let blocker, blocker != "unknown" else {
            if loadingMode.contains("diagnostic"),
               generatedRootHandlerActive == false
            {
                return .schemeHandlerNotInstalledOnPopupConfiguration
            }
            return nil
        }
        switch blocker {
        case "generatedRootResourceMissing", "extensionPackageResourceAbsent":
            return .generatedBundleResourceMissing
        case "generatedRootPathMappingWrong":
            return .generatedBundlePathMappingFailure
        case "mimeTypeWrong":
            return .mimeResolutionFailure
        case "moduleScriptLoadFailure":
            if resourceCategory?.localizedCaseInsensitiveContains("chunk") == true {
                return .requiredChunkResourceLoadFailure
            }
            return .requiredScriptResourceLoadFailure
        case "classicScriptLoadFailure":
            if resourceCategory?.localizedCaseInsensitiveContains("chunk") == true {
                return .requiredChunkResourceLoadFailure
            }
            return .requiredScriptResourceLoadFailure
        case "stylesheetLoadFailure":
            return .requiredStyleResourceLoadFailure
        case "wasmLoadFailure":
            return .requiredWasmResourceLoadFailure
        case "popupNavigationReset":
            return .popupDocumentNotLoaded
        default:
            if loadingMode.contains("diagnostic") {
                return .schemeHandlerSyncLoadUnsupported
            }
            return .popoverPresentedButResourcesFailed
        }
    }

    static func classify(
        _ trace: ChromeMV3LivePopupProductPathTrace,
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = []
    ) -> ChromeMV3LivePopupFailureClassifier {
        if let resourceClassifier = resourceFailureClassifier(
            blocker: trace.resourceLoadBlockerCategory,
            resourceCategory: trace.resourceFailureCategory,
            loadingMode: trace.loadingMode,
            generatedRootHandlerActive: trace.generatedRootHandlerActive
        ) {
            if trace.bridgeInstalled == false {
                return .bridgeNotInstalledBecauseResourcesFailed
            }
            if trace.scriptsExecuted == false {
                return .scriptsNotExecutedBecauseResourcesFailed
            }
            if trace.popoverPresented,
               trace.finalDOMCheckpoint.map(domProbeIndicatesVisible) == false
            {
                return .popoverPresentedDOMProbeEmptyBecauseResourcesFailed
            }
            return resourceClassifier
        }

        if trace.popoverShown && trace.popoverPresented == false {
            return .popupDismissedOrReplacedAfterPresentation
        }

        if trace.popoverPresented == false {
            if trace.extensionClassifier == "extensionLocalAppState" {
                return .extensionLocalAppState
            }
            if trace.extensionClassifier == "extensionLocalRenderState" {
                return .extensionLocalRenderState
            }
            return .unknown
        }

        if trace.contentViewSizeBucket == "zero" {
            return .popoverPresentedButContentViewZeroSize
        }
        if trace.webViewFrameSizeBucket == "zero" {
            return .popoverPresentedButWebViewZeroSize
        }
        if trace.webViewHidden || trace.webViewAlphaBucket == "zero" {
            return .popoverPresentedButWebViewHidden
        }
        if trace.contentViewReplacedWebView || trace.popoverDisplaysSameWebViewAsLoaded == false {
            return .popoverPresentedButWrongWebView
        }
        if trace.webViewDeallocated
            || trace.webViewInWindowHierarchy == false
            || trace.webViewAttachedToHost == false
        {
            return .popoverPresentedButWebViewDetached
        }
        if trace.urlLoadCommitted == false {
            return .popoverPresentedButURLNotLoaded
        }
        if trace.navigationFailed {
            return .popoverPresentedButNavigationFailed
        }
        if trace.bridgeInstalled == false {
            return .popoverPresentedButBridgeMissing
        }

        if let latest = preferredStagedSnapshot(trace.stagedSnapshots),
           stagedSnapshotIndicatesVisible(latest),
           trace.requiredResourceLoadFailure == false,
           latest.consoleErrorCategory == "none",
           latest.unhandledRejectionCategory == "none",
           reconciledScriptsExecuted(trace: trace)
        {
            return .livePopupVisible
        }

        if reconciledScriptsExecuted(trace: trace) == false {
            return .popoverPresentedButScriptsNotExecuted
        }

        let domProbeVisible =
            trace.finalDOMCheckpoint.map(domProbeIndicatesVisible) ?? false
        let presentationRenderable =
            trace.webViewFrameSizeBucket != "zero"
            && trace.webViewHidden == false
            && trace.webViewAlphaBucket != "zero"
            && trace.webViewInWindowHierarchy
            && trace.popoverDisplaysSameWebViewAsLoaded
            && trace.contentViewAttachedToWindow

        if domProbeVisible && presentationRenderable == false {
            return .popoverPresentedButDOMVisibleInProbeButNotOnScreen
        }

        if let first = trace.firstDOMCheckpoint,
           let final = trace.finalDOMCheckpoint
        {
            let firstVisible = domProbeIndicatesVisible(first)
            let finalVisible = domProbeIndicatesVisible(final)
            if firstVisible && finalVisible == false {
                return .popoverPresentedThenExtensionBlankedDOM
            }
            if firstVisible == false && finalVisible == false {
                let cssHiddenCategories: Set<String> = [
                    "displayNone",
                    "visibilityHidden",
                    "opacityZero",
                    "zeroSize",
                    "transparentOrWhiteOnWhite",
                ]
                if cssHiddenCategories.contains(final.visibilityCategory) {
                    return .popoverPresentedButDOMExistsButCSSHidden
                }
            }
        }

        if let bootstrapClassifier = classifyBootstrapFailure(
            trace: trace,
            routeEvents: routeEvents
        ) {
            return bootstrapClassifier
        }

        if let final = trace.finalDOMCheckpoint,
           domProbeIndicatesVisible(final) == false
        {
            let cssHiddenCategories: Set<String> = [
                "displayNone",
                "visibilityHidden",
                "opacityZero",
                "zeroSize",
                "transparentOrWhiteOnWhite",
            ]
            if cssHiddenCategories.contains(final.visibilityCategory) {
                return .popoverPresentedButDOMExistsButCSSHidden
            }
            if final.bodyChildCount > 0 || final.appRootPresent {
                return .popoverPresentedButDOMExistsButZeroVisibleText
            }
        }

        if trace.extensionClassifier == "extensionLocalAppState" {
            return .extensionLocalAppState
        }
        if trace.extensionClassifier == "extensionLocalRenderState" {
            return .extensionLocalRenderState
        }
        if trace.extensionBlankedDOM {
            return .popoverPresentedThenExtensionBlankedDOM
        }

        let hasSignals =
            trace.finalDOMCheckpoint != nil
            || trace.stagedSnapshots.isEmpty == false
            || trace.firstJSCheckpointReached
            || trace.scriptsExecuted
        if hasSignals {
            return .popupAppRootPresentButEmpty
        }
        return .unknown
    }
}

@MainActor
final class ChromeMV3LivePopupStagedSnapshotCollector {
    private weak var webView: WKWebView?
    private weak var bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?
    private(set) var snapshots: [ChromeMV3LivePopupStagedSnapshot] = []
    private var scheduledWork: [DispatchWorkItem] = []
    private var bridgePollTask: Task<Void, Never>?
    private var navigationStarted = false
    private var navigationFinished = false
    private let bridgeInstalled: Bool

    init(
        webView: WKWebView,
        bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?,
        bridgeInstalled: Bool
    ) {
        self.webView = webView
        self.bridgeHandler = bridgeHandler
        self.bridgeInstalled = bridgeInstalled
    }

    func begin() {
        capture(stage: "afterURLAssignment")
        schedule(after: 0.25, stage: "after250ms")
        schedule(after: 1.0, stage: "after1000ms")
        schedule(after: 3.0, stage: "after3000ms")
        startBridgeEventPolling()
    }

    func recordNavigationStarted() {
        navigationStarted = true
    }

    func recordNavigationFinished() {
        navigationFinished = true
        capture(stage: "afterLoadEvent")
    }

    func tearDown() {
        scheduledWork.forEach { $0.cancel() }
        scheduledWork.removeAll()
        bridgePollTask?.cancel()
        bridgePollTask = nil
    }

    private func schedule(after delay: TimeInterval, stage: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.capture(stage: stage)
        }
        scheduledWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startBridgeEventPolling() {
        bridgePollTask?.cancel()
        bridgePollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var seenSequences: Set<Int> = []
            while Task.isCancelled == false {
                self.captureTriggeredSnapshots(seenSequences: &seenSequences)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func captureTriggeredSnapshots(seenSequences: inout Set<Int>) {
        guard let bridgeHandler else { return }
        let events = bridgeHandler.diagnosticsSnapshot.jsDebugRouteEvents
        for event in events {
            guard seenSequences.insert(event.sequence).inserted else { continue }
            switch event.eventKind {
            case "livePopupStagedSnapshot":
                if let stage = event.diagnostics.first(where: { $0.hasPrefix("stage=") }) {
                    capture(stage: String(stage.dropFirst("stage=".count)))
                }
            case "consoleError", "scriptError", "windowError":
                capture(stage: "onConsoleError")
            case "unhandledRejection":
                capture(stage: "onUnhandledRejection")
            default:
                let api = event.apiName.lowercased()
                if api.contains("storage.") {
                    capture(stage: "onStorageRoute")
                } else if api.contains("runtime.sendmessage")
                    || api.contains("runtime.onmessage")
                {
                    capture(stage: "onRuntimeRoute")
                } else if api.contains("runtime.connect") || api.contains("port.") {
                    capture(stage: "onPortRoute")
                } else if api.contains("tabs.") {
                    capture(stage: "onTabsRoute")
                } else if api.contains("scripting.") {
                    capture(stage: "onScriptingRoute")
                } else if event.eventKind == "bridgeBootstrapProbe" {
                    if event.diagnostics.contains(where: {
                        $0 == "phase=atDocumentStartBridgeInjection"
                    }) {
                        capture(stage: "atDocumentStartBridgeInjection")
                    } else if event.diagnostics.contains(where: {
                        $0 == "phase=beforeFirstExtensionScript"
                    }) {
                        capture(stage: "beforeFirstExtensionScript")
                    }
                } else if event.eventKind == "postBootstrapCheckpoint" {
                    capture(stage: "afterBridgeBootstrap")
                } else if event.diagnostics.contains(where: { $0 == "reason=domcontentloaded" }) {
                    capture(stage: "afterDOMContentLoaded")
                } else if event.diagnostics.contains(where: { $0 == "reason=window-load" }) {
                    capture(stage: "afterLoadEvent")
                }
            }
        }
    }

    private func capture(stage: String) {
        guard snapshots.contains(where: { $0.stage == stage }) == false else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let webView = self.webView else { return }
            let bridgeSnapshot = self.bridgeHandler?.diagnosticsSnapshot
            let routeEvents = bridgeSnapshot?.jsDebugRouteEvents ?? []
            let pendingRoutes =
                bridgeSnapshot?.pendingUnresolvedJSDebugRoutes ?? []
            let observedMethods = bridgeSnapshot?.observedMethods ?? []
            let domObject: [String: Any]
            if let raw = try? await webView.evaluateJavaScript(
                ChromeMV3LivePopupProductPathTraceBuilder.stagedProbeScript
            ) as? String,
                let data = raw.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            {
                domObject = object
            } else {
                domObject = [
                    "readyState": "unknown",
                    "visibleTextLength": 0,
                    "formControlCount": 0,
                    "buttonCount": 0,
                    "bodyChildCount": 0,
                    "appRootPresent": false,
                    "appRootChildCount": 0,
                    "navigationCommitted": false,
                    "ariaBusyOrLoadingCategory": "none",
                ]
            }
            let readyState = domObject["readyState"] as? String
            let urlLoaded = domObject["navigationCommitted"] as? Bool ?? false
            let navigation = ChromeMV3LivePopupProductPathTraceBuilder.navigationState(
                from: routeEvents,
                readyState: readyState,
                urlLoadCommitted: urlLoaded
            )
            let snapshot = ChromeMV3LivePopupProductPathTraceBuilder.buildStagedSnapshot(
                stage: stage,
                domObject: domObject,
                routeEvents: routeEvents,
                pendingRoutes: pendingRoutes,
                observedMethods: observedMethods,
                bridgeInstalled: self.bridgeInstalled,
                navigationStarted: self.navigationStarted || navigation.started,
                navigationFinished: self.navigationFinished || navigation.finished
            )
            if self.snapshots.contains(where: { $0.stage == stage }) == false {
                self.snapshots.append(snapshot)
            }
        }
    }
}

#endif
