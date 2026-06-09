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
    case serviceWorkerOnConnectListenerMissing
    case serviceWorkerConnectDispatchedBeforeStartup
    case runtimePortSenderShapeMismatch
    case extensionLocalNoOnConnectListener
    case popupWaitingOnTabsOrScripting
    case popupMissingChromeAPIAbort
    case appStateWaitWithNoWriter
    case popupAppRootEmptyAfterBootstrap
    case portConnectedNoSwOutbox
    case runtimePortEnvelopeMismatch
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
    var nativeMessagingRequestCountBucket: String
    var nativeMessagingResultCategory: String
    var swOutboxCapturedCountBucket: String
    var swOutboxDeliveredToPopupCountBucket: String
    var popupPortOnMessageListenerCategory: String
    var pendingInboundPortMessagesBucket: String
    var portDisconnectCategory: String

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
            "nativeMessagingRequestCountBucket=\(nativeMessagingRequestCountBucket)",
            "nativeMessagingResultCategory=\(nativeMessagingResultCategory)",
            "swOutboxCapturedCountBucket=\(swOutboxCapturedCountBucket)",
            "swOutboxDeliveredToPopupCountBucket=\(swOutboxDeliveredToPopupCountBucket)",
            "popupPortOnMessageListenerCategory=\(popupPortOnMessageListenerCategory)",
            "pendingInboundPortMessagesBucket=\(pendingInboundPortMessagesBucket)",
            "portDisconnectCategory=\(portDisconnectCategory)",
        ].joined(separator: " ")
    }
}

struct ChromeMV3ControlledPopupAppStateBoundaryDiagnostics: Equatable, Sendable {
    var firstStableAppStateClassifier: String
    var extensionBoundaryClassifier: String
    var boundaryKind: String
    var nativeMessagingRequestCategory: String
    var nativeMessagingResultCategory: String
    var pendingRouteBucket: String
    var serviceWorkerListenerCategory: String
    var popupMessagingCategory: String
    var portRouteCategory: String
    var storageCategory: String
    var after3000msSnapshotLine: String?

    var logLines: [String] {
        var lines = [
            "firstStableAppStateClassifier=\(firstStableAppStateClassifier)",
            "extensionBoundaryClassifier=\(extensionBoundaryClassifier)",
            "boundaryKind=\(boundaryKind)",
            "nativeMessagingRequestCategory=\(nativeMessagingRequestCategory)",
            "nativeMessagingResultCategory=\(nativeMessagingResultCategory)",
            "pendingRouteBucket=\(pendingRouteBucket)",
            "serviceWorkerListenerCategory=\(serviceWorkerListenerCategory)",
            "popupMessagingCategory=\(popupMessagingCategory)",
            "portRouteCategory=\(portRouteCategory)",
            "storageCategory=\(storageCategory)",
        ]
        if let after3000msSnapshotLine {
            lines.append(after3000msSnapshotLine)
        }
        return lines
    }
}

struct ChromeMV3LivePopupStorageLifecycleContext: Equatable, Sendable {
    var installStoragePersistedCategory: String
    var popupWakeStorageSeededCategory: String
    var installStorageWriteCountBucket: String
    var popupWakeDeferredStartupDrainCountBucket: String

    static let notObserved = ChromeMV3LivePopupStorageLifecycleContext(
        installStoragePersistedCategory: "notObserved",
        popupWakeStorageSeededCategory: "notObserved",
        installStorageWriteCountBucket: "notObserved",
        popupWakeDeferredStartupDrainCountBucket: "notObserved"
    )

    #if DEBUG
        static func fromLocalLifecycleDispatch(
            _ result: ChromeMV3LocalLifecycleDispatchResult?
        ) -> ChromeMV3LivePopupStorageLifecycleContext {
            guard let result else { return .notObserved }
            let installPersisted =
                result.storageLocalPersistedFromWorker
                    && result.storageLocalWriteCount > 0
            return ChromeMV3LivePopupStorageLifecycleContext(
                installStoragePersistedCategory:
                    result.dispatched
                        ? (
                            installPersisted
                                ? "installPersisted"
                                : (
                                    result.storageLocalWriteCount > 0
                                        ? "installWriteNotPersisted"
                                        : "installDispatchedNoWrite"
                                )
                        )
                        : "installDispatchSkipped",
                popupWakeStorageSeededCategory: "notObserved",
                installStorageWriteCountBucket:
                    ChromeMV3LivePopupProductPathTraceBuilder.countBucket(
                        result.storageLocalWriteCount
                    ),
                popupWakeDeferredStartupDrainCountBucket: "notObserved"
            )
        }
    #endif
}

struct ChromeMV3FirstVisibleUIGateDiagnostics: Equatable, Sendable {
    var firstVisibleUIGateCategory: String
    var appInitializerGateCategory: String
    var angularBootstrapCategory: String
    var routerActivationCategory: String
    var redirectGuardCategory: String
    var loginRouteActivationCategory: String
    var firstVisibleComponentCategory: String
    var staticLoadingShellCategory: String
    var migrationWaitCategory: String
    var migrationStateCategory: String
    var migrationStateShapeCategory: String
    var accountScaffoldCategory: String
    var viewCacheStateCategory: String
    var sdkReadyCategory: String
    var i18nReadyCategory: String
    var themeReadyCategory: String
    var popupSizeReadyCategory: String
    var storageMigrationReadCategory: String
    var storageMigrationWriteVisibilityCategory: String
    var nativeDependencyForVisibleUICategory: String
    var appInitializerEnteredCategory: String
    var sdkLoadAwaitCategory: String
    var migrationWaitEnteredCategory: String
    var migrationWaitResolvedCategory: String
    var i18nInitCategory: String
    var viewCacheInitCategory: String
    var popupSizeInitCategory: String
    var themeInitCategory: String
    var appInitializerUnresolvedAwaitCategory: String
    var swStorageWriteCapturedCountBucket: String
    var swStorageWriteMirroredCountBucket: String
    var popupReadWrittenByServiceWorkerCountBucket: String
    var storageNamespaceMatchCategory: String
    var storageSnapshotImportedCategory: String
    var storageOnChangedDeliveryCategory: String
    var installStoragePersistedCategory: String
    var popupWakeStorageSeededCategory: String

    var logLines: [String] {
        [
            "firstVisibleUIGateCategory=\(firstVisibleUIGateCategory)",
            "appInitializerGateCategory=\(appInitializerGateCategory)",
            "appInitializerEnteredCategory=\(appInitializerEnteredCategory)",
            "sdkLoadAwaitCategory=\(sdkLoadAwaitCategory)",
            "migrationWaitEnteredCategory=\(migrationWaitEnteredCategory)",
            "migrationWaitResolvedCategory=\(migrationWaitResolvedCategory)",
            "i18nInitCategory=\(i18nInitCategory)",
            "viewCacheInitCategory=\(viewCacheInitCategory)",
            "popupSizeInitCategory=\(popupSizeInitCategory)",
            "themeInitCategory=\(themeInitCategory)",
            "appInitializerUnresolvedAwaitCategory=\(appInitializerUnresolvedAwaitCategory)",
            "angularBootstrapCategory=\(angularBootstrapCategory)",
            "routerActivationCategory=\(routerActivationCategory)",
            "redirectGuardCategory=\(redirectGuardCategory)",
            "loginRouteActivationCategory=\(loginRouteActivationCategory)",
            "firstVisibleComponentCategory=\(firstVisibleComponentCategory)",
            "staticLoadingShellCategory=\(staticLoadingShellCategory)",
            "migrationWaitCategory=\(migrationWaitCategory)",
            "migrationStateCategory=\(migrationStateCategory)",
            "migrationStateShapeCategory=\(migrationStateShapeCategory)",
            "accountScaffoldCategory=\(accountScaffoldCategory)",
            "viewCacheStateCategory=\(viewCacheStateCategory)",
            "sdkReadyCategory=\(sdkReadyCategory)",
            "i18nReadyCategory=\(i18nReadyCategory)",
            "themeReadyCategory=\(themeReadyCategory)",
            "popupSizeReadyCategory=\(popupSizeReadyCategory)",
            "storageMigrationReadCategory=\(storageMigrationReadCategory)",
            "storageMigrationWriteVisibilityCategory=\(storageMigrationWriteVisibilityCategory)",
            "nativeDependencyForVisibleUICategory=\(nativeDependencyForVisibleUICategory)",
            "swStorageWriteCapturedCountBucket=\(swStorageWriteCapturedCountBucket)",
            "swStorageWriteMirroredCountBucket=\(swStorageWriteMirroredCountBucket)",
            "popupReadWrittenByServiceWorkerCountBucket=\(popupReadWrittenByServiceWorkerCountBucket)",
            "storageNamespaceMatchCategory=\(storageNamespaceMatchCategory)",
            "storageSnapshotImportedCategory=\(storageSnapshotImportedCategory)",
            "storageOnChangedDeliveryCategory=\(storageOnChangedDeliveryCategory)",
            "installStoragePersistedCategory=\(installStoragePersistedCategory)",
            "popupWakeStorageSeededCategory=\(popupWakeStorageSeededCategory)",
        ]
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
        "#loading,[id='loading'],[role='progressbar'],[aria-busy='true'],.spinner,.loading,.loader,[data-loading='true'],[class*='spin'],[class*='Spin']"
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

    static let firstVisibleUIGateProbeScript = """
    (() => {
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
      const body = document.body;
      const text = body && body.innerText ? body.innerText.trim() : "";
      const staticLoadingShellCount = queryCount(
        '#loading,[id="loading"],[data-loading="true"]'
      );
      const spinnerLikeCount = queryCount(
        '[role="progressbar"],[aria-busy="true"],.spinner,.loading,.loader,[class*="spin"],[class*="Spin"]'
      );
      const ngVersionPresent =
        (appRoot && appRoot.hasAttribute("ng-version"))
          || queryCount("[ng-version]") > 0;
      const routerOutlet = document.querySelector("router-outlet");
      const routerOutletPresent = routerOutlet != null;
      const routeHost = appRoot || body;
      const hyphenComponentCount = routeHost
        ? Array.from(routeHost.querySelectorAll("*")).filter((node) => {
            const tag = node.tagName ? node.tagName.toLowerCase() : "";
            return tag.includes("-")
              && tag !== "app-root"
              && tag !== "router-outlet";
          }).length
        : 0;
      const formControlCount = queryCount("input,textarea,select");
      const buttonCount = queryCount(
        "button,[role='button'],input[type='button'],input[type='submit']"
      );
      const visibleControlCount = formControlCount + buttonCount;
      const visibilityCategory = (() => {
        const target = appRoot || body;
        if (!target) return "detached";
        const style = window.getComputedStyle(target);
        if (style.display === "none") return "displayNone";
        if (style.visibility === "hidden") return "visibilityHidden";
        if (parseFloat(style.opacity || "1") === 0) return "opacityZero";
        const rect = target.getBoundingClientRect();
        if (rect.width <= 1 || rect.height <= 1) return "zeroSize";
        if (text.length > 0 || visibleControlCount > 0) return "visible";
        return "unknown";
      })();
      const pathnameDepth = location && location.pathname
        ? location.pathname.split("/").filter(Boolean).length
        : 0;
      const htmlLocaleClassPresent = document.documentElement
        ? Array.from(document.documentElement.classList).some(
            (className) =>
              typeof className === "string"
                && className.startsWith("locale_")
          )
        : false;
      return JSON.stringify({
        readyState: document.readyState || "unknown",
        visibleTextLength: text.length,
        formControlCount: formControlCount,
        buttonCount: buttonCount,
        appRootPresent: appRoot != null,
        appRootChildCount: appRoot ? appRoot.childElementCount : 0,
        staticLoadingShellCount: staticLoadingShellCount,
        spinnerLikeCount: spinnerLikeCount,
        ngVersionPresent: ngVersionPresent,
        routerOutletPresent: routerOutletPresent,
        hyphenComponentCount: hyphenComponentCount,
        pathnameDepth: pathnameDepth,
        visibilityCategory: visibilityCategory,
        htmlLocaleClassPresent: htmlLocaleClassPresent
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
        var nativeMessagingRequest: Int = 0
    }

    static func apiRouteCountBuckets(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        pendingRoutes: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = [],
        routeRecords:
            [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = [],
        harnessOnMessageListenerCount: Int = 0,
        harnessOnConnectListenerCount: Int = 0
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
                if api.contains("nativemessaging.")
                    || api.contains("runtime.connectnative")
                    || api.contains("runtime.sendnativemessage")
                {
                    buckets.nativeMessagingRequest += 1
                }
            default:
                break
            }
        }
        let serviceWorkerListeners = serviceWorkerListenerCounts(
            from: routeRecords,
            harnessOnMessageListenerCount: harnessOnMessageListenerCount,
            harnessOnConnectListenerCount: harnessOnConnectListenerCount
        )
        buckets.serviceWorkerOnMessageListener = serviceWorkerListeners.onMessage
        buckets.serviceWorkerOnConnectListener = serviceWorkerListeners.onConnect
        return buckets
    }

    static func serviceWorkerListenerCounts(
        from routeRecords: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        harnessOnMessageListenerCount: Int = 0,
        harnessOnConnectListenerCount: Int = 0
    ) -> (onMessage: Int, onConnect: Int) {
        var onMessage = 0
        var onConnect = 0
        for route in routeRecords {
            switch route.apiName {
            case "runtime.sendMessage":
                if route.sourceContext != "contentScript" {
                    onMessage = max(onMessage, route.listenerCount)
                }
            case "runtime.connect":
                onConnect = max(onConnect, route.listenerCount)
            default:
                break
            }
            if route.diagnostics.contains(where: {
                $0.contains("runtime.onMessage listener")
            }) {
                onMessage = max(onMessage, route.listenerCount)
            }
            if route.diagnostics.contains(where: {
                $0.contains("runtime.onConnect listener")
                    || $0.contains("runtime.onConnect JavaScript listener")
            }) {
                onConnect = max(onConnect, route.listenerCount)
            }
        }
        if onMessage == 0, harnessOnMessageListenerCount > 0 {
            onMessage = harnessOnMessageListenerCount
        }
        if onConnect == 0, harnessOnConnectListenerCount > 0 {
            onConnect = harnessOnConnectListenerCount
        }
        return (onMessage, onConnect)
    }

    static func harnessListenerCounts(
        from bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
    ) -> (onMessage: Int, onConnect: Int) {
        guard let trace = bridgeSnapshot?.appStateDependencyTrace else {
            return (0, 0)
        }
        return (
            trace.serviceWorkerHarnessOnMessageListenerCount,
            trace.serviceWorkerHarnessOnConnectListenerCount
        )
    }

    struct PortDeliveryDiagnostics: Equatable, Sendable {
        var swOutboxCaptured: Int = 0
        var swOutboxDelivered: Int = 0
        var pendingInbound: Int = 0
        var listenerCategory: String = "notObserved"
        var disconnectCategory: String = "notObserved"
    }

    static func portEventDiagnosticValue(
        _ key: String,
        from event: ChromeMV3PopupOptionsJSDebugRouteEventRecord
    ) -> String? {
        event.diagnostics.first(where: { $0.hasPrefix("\(key)=") }).map {
            String($0.dropFirst("\(key)=".count))
        }
    }

    static func diagnosticBucketLowerBound(_ bucket: String) -> Int {
        switch bucket {
        case "0":
            return 0
        case "1":
            return 1
        case "2plus":
            return 2
        case "1-3":
            return 1
        case "4-10":
            return 4
        case "10+":
            return 10
        default:
            return 0
        }
    }

    static func portDeliveryDiagnostics(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> PortDeliveryDiagnostics {
        var result = PortDeliveryDiagnostics()
        var connectObserved = false
        var listenerAdded = false

        for event in events {
            switch event.eventKind {
            case "portSwOutboxReceived":
                result.swOutboxCaptured += max(
                    1,
                    diagnosticBucketLowerBound(
                        portEventDiagnosticValue(
                            "queuedSwOutboxCountBucket",
                            from: event
                        ) ?? "1"
                    )
                )
            case "portSwOutboxDelivered":
                result.swOutboxDelivered += max(
                    1,
                    diagnosticBucketLowerBound(
                        portEventDiagnosticValue(
                            "deliveredSwToPopupCountBucket",
                            from: event
                        ) ?? "1"
                    )
                )
            case "portSwOutboxQueued":
                result.pendingInbound += max(
                    1,
                    diagnosticBucketLowerBound(
                        portEventDiagnosticValue(
                            "queuedSwOutboxCountBucket",
                            from: event
                        ) ?? "1"
                    )
                )
            case "portListenerAdded":
                guard event.apiName == "Port.onMessage" else { break }
                listenerAdded = true
                if let category = portEventDiagnosticValue(
                    "listenerRegistrationCategory",
                    from: event
                ) {
                    result.listenerCategory =
                        category == "additionalListener"
                        ? "additionalListener" : "listenerRegistered"
                } else {
                    result.listenerCategory = "listenerRegistered"
                }
            case "portDisconnected":
                result.disconnectCategory =
                    event.resultClassifier == "lastError"
                    ? "disconnectedWithError" : "disconnected"
            case "portObjectReturned":
                if event.apiName == "runtime.connect" {
                    connectObserved = true
                }
            default:
                if event.apiName.lowercased().contains("runtime.connect") {
                    connectObserved = true
                }
            }
        }

        if connectObserved,
           listenerAdded == false,
           result.listenerCategory == "notObserved"
        {
            if let received = events.last(where: {
                $0.eventKind == "portSwOutboxReceived"
            }),
                let category = portEventDiagnosticValue(
                    "listenerRegistrationCategory",
                    from: received
                )
            {
                result.listenerCategory = category
            } else {
                result.listenerCategory = "listenerAbsent"
            }
        }
        if connectObserved == false, result.disconnectCategory == "notObserved" {
            result.disconnectCategory = "none"
        }
        return result
    }

    static func nativeMessagingRequestCategory(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        var categories: Set<String> = []
        for event in events {
            let api = event.apiName.lowercased()
            if api.contains("runtime.connectnative") {
                categories.insert("runtime.connectNative")
            } else if api.contains("runtime.sendnativemessage") {
                categories.insert("runtime.sendNativeMessage")
            } else if api.contains("nativemessaging.") {
                categories.insert("nativeMessaging.namespace")
            }
        }
        guard categories.isEmpty == false else { return "none" }
        return categories.sorted().joined(separator: "+")
    }

    static func nativeMessagingResultCategory(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        pendingRoutes: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = []
    ) -> String {
        let nativeEvents = events.filter { event in
            let api = event.apiName.lowercased()
            return api.contains("nativemessaging.")
                || api.contains("runtime.connectnative")
                || api.contains("runtime.sendnativemessage")
        }
        guard nativeEvents.isEmpty == false else { return "notRequested" }
        if pendingRoutes.contains(where: { event in
            let api = event.apiName.lowercased()
            return api.contains("nativemessaging.")
                || api.contains("runtime.connectnative")
                || api.contains("runtime.sendnativemessage")
        }) {
            return "pending"
        }
        if nativeEvents.contains(where: {
            $0.resultClassifier == "permissionDenied"
                || $0.resultClassifier == "blocked"
                || $0.firstMissingAPIOrPermissionOrLifecycleError?
                    .localizedCaseInsensitiveContains("native messaging") == true
                || $0.firstMissingAPIOrPermissionOrLifecycleError?
                    .localizedCaseInsensitiveContains("Specified native messaging host not found")
                    == true
        }) {
            return "unavailableError"
        }
        if nativeEvents.contains(where: {
            $0.diagnostics.contains(where: {
                $0.localizedCaseInsensitiveContains("fixture host")
                    || $0.localizedCaseInsensitiveContains("processLaunchAttempted=true")
            })
        }) {
            return "fixtureOrHostAttempted"
        }
        if nativeEvents.contains(where: {
            $0.eventKind == "bridgeCallResolved"
                || $0.resultClassifier?.contains("Succeeded") == true
        }) {
            return "resolved"
        }
        return "observed"
    }

    static func portRouteCategory(
        from routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        pendingRoutes: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        let connectRoutes = routes.filter { $0.apiName == "runtime.connect" }
        guard connectRoutes.isEmpty == false else { return "notObserved" }
        if pendingRoutes.contains(where: { $0.apiName == "runtime.connect" })
            || pendingRoutes.contains(where: { $0.apiName.hasPrefix("Port.") })
        {
            return "waiting"
        }
        if connectRoutes.contains(where: {
            ["noReceivingEnd", "noListener", "blocked", "permissionDenied",
             "listenerPresentButNoResponse", "Port message not delivered",
             "Port response not delivered"].contains($0.resultClassifier)
        }) {
            return "failed"
        }
        if connectRoutes.contains(where: { $0.listenerInvoked }) {
            if connectRoutes.contains(where: { $0.portMessageCount > 0 }) {
                return "delivered"
            }
            return "connected"
        }
        return "observed"
    }

    static func normalizeExtensionBoundaryClassifier(_ classifier: String) -> String {
        switch classifier {
        case "appStateWaitWithNoWriter", "appStateWaitWithNoObservableDependency",
            "appStateWaitWithSuppressedEvent", "appStateWaitWithDelayedWriter",
            "appStateWaitWithUnresolvedBridgeRoute", "appStateWaitWithMissingAPI",
            "appStateWaitWithNetworkOrAuthDependency":
            return "extensionLocalAppState"
        case "appStateWaitWithNoObservableBrowserDependency":
            return "extensionLocalRenderState"
        default:
            return classifier
        }
    }

    static func firstStableAppStateClassifier(
        bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        stagedSnapshots: [ChromeMV3LivePopupStagedSnapshot] = []
    ) -> String {
        let correlation =
            bridgeSnapshot?.appStateDependencyTrace.correlationSummary
                .classification
        if let correlation, correlation != "notClassified" {
            return correlation
        }
        let lateStages = ["after3000ms", "after1000ms", "after250ms"]
        for stage in lateStages {
            if stagedSnapshots.contains(where: { $0.stage == stage }) {
                break
            }
        }
        return correlation ?? "notClassified"
    }

    private static func finalPostBootstrapCoarseStatus(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        events.last(where: { event in
            event.eventKind == "postBootstrapCheckpoint"
                && event.diagnostics.contains { $0 == "phase=final" }
        })?.resultClassifier
            ?? events.last(where: { $0.eventKind == "postBootstrapCheckpoint" })?
            .resultClassifier
    }

    private static func migrationShapedPopupReads(
        in operations: [ChromeMV3AppStateStorageOperationTraceRecord]
    ) -> [ChromeMV3AppStateStorageOperationTraceRecord] {
        operations.filter { record in
            record.context == "popup"
                && record.operation == "get"
                && (
                    record.keyShape == "singleKey"
                        || record.keyShape == "stringKey"
                        || record.keyShape == "objectKeys"
                )
        }
    }

    private static func serviceWorkerStorageWrites(
        in operations: [ChromeMV3AppStateStorageOperationTraceRecord]
    ) -> [ChromeMV3AppStateStorageOperationTraceRecord] {
        operations.filter { record in
            record.context == "serviceWorker"
                && ["set", "remove", "clear"].contains(record.operation)
        }
    }

    private static func deriveStorageMirrorDiagnostics(
        bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        correlation: ChromeMV3AppStateDependencyCorrelationSummary,
        storageLifecycleContext: ChromeMV3LivePopupStorageLifecycleContext
    ) -> (
        swStorageWriteCapturedCountBucket: String,
        swStorageWriteMirroredCountBucket: String,
        popupReadWrittenByServiceWorkerCountBucket: String,
        storageNamespaceMatchCategory: String,
        storageSnapshotImportedCategory: String,
        storageOnChangedDeliveryCategory: String,
        installStoragePersistedCategory: String,
        popupWakeStorageSeededCategory: String
    ) {
        let storageOperations =
            bridgeSnapshot?.appStateDependencyTrace.storageOperations ?? []
        let swWrites = serviceWorkerStorageWrites(in: storageOperations)
        let mirroredWriteCount =
            correlation.popupReadKeyHashesWrittenByServiceWorker.count
        let storageChangeDispatches =
            bridgeSnapshot?.appStateDependencyTrace.storageChangeDispatches
            ?? []
        let onChangedDelivered =
            storageChangeDispatches.contains { dispatch in
                dispatch.listenerReceivedByContext.values.contains(true)
            }
        let onChangedObserved = storageChangeDispatches.isEmpty == false
        let snapshotImported =
            bridgeSnapshot?.diagnostics.contains {
                $0.localizedCaseInsensitiveContains(
                    "Loaded existing developer-preview storage.local snapshot"
                )
            } ?? false
        let namespaceMatched =
            bridgeSnapshot?.diagnostics.contains {
                $0.localizedCaseInsensitiveContains(
                    "scoped by profile ID, extension ID"
                )
            } ?? false
        let storageOnChangedDeliveryCategory: String
        if onChangedDelivered {
            storageOnChangedDeliveryCategory = "onChangedDelivered"
        } else if onChangedObserved {
            storageOnChangedDeliveryCategory = "onChangedDeliveryFailure"
        } else if correlation.writtenKeyHashesWithoutObservedOnChangedDelivery
            .isEmpty == false
        {
            storageOnChangedDeliveryCategory = "onChangedMissed"
        } else {
            storageOnChangedDeliveryCategory = "notObserved"
        }
        let swStorageWriteMirroredCountBucket: String
        if swWrites.isEmpty {
            swStorageWriteMirroredCountBucket = "0"
        } else if mirroredWriteCount > 0 {
            swStorageWriteMirroredCountBucket =
                countBucket(mirroredWriteCount)
        } else {
            swStorageWriteMirroredCountBucket = "0"
        }
        return (
            swStorageWriteCapturedCountBucket: countBucket(swWrites.count),
            swStorageWriteMirroredCountBucket: swStorageWriteMirroredCountBucket,
            popupReadWrittenByServiceWorkerCountBucket:
                countBucket(mirroredWriteCount),
            storageNamespaceMatchCategory:
                namespaceMatched ? "namespaceMatched" : "notObserved",
            storageSnapshotImportedCategory:
                snapshotImported
                    ? "storageSnapshotImported"
                    : "storageSnapshotNotImported",
            storageOnChangedDeliveryCategory: storageOnChangedDeliveryCategory,
            installStoragePersistedCategory:
                storageLifecycleContext.installStoragePersistedCategory,
            popupWakeStorageSeededCategory:
                storageLifecycleContext.popupWakeStorageSeededCategory
        )
    }

    private static func deriveAppInitializerPhaseDiagnostics(
        scriptsExecuted: Bool,
        staticLoadingShellCount: Int,
        ngVersionPresent: Bool,
        migrationReads: [ChromeMV3AppStateStorageOperationTraceRecord],
        migrationEmptyReads: Int,
        migrationPopulatedReads: Int,
        i18nRouteCount: Int,
        hyphenComponentCount: Int,
        routerOutletPresent: Bool,
        htmlLocaleClassPresent: Bool,
        correlation: ChromeMV3AppStateDependencyCorrelationSummary,
        storageMigrationWriteVisibilityCategory: String,
        installStoragePersistedCategory: String,
        swStorageWriteCapturedCountBucket: String,
        popupReadWrittenByServiceWorkerCountBucket: String,
        storageSnapshotImportedCategory: String,
        storageOnChangedDeliveryCategory: String
    ) -> (
        appInitializerEnteredCategory: String,
        sdkLoadAwaitCategory: String,
        migrationWaitEnteredCategory: String,
        migrationWaitResolvedCategory: String,
        i18nInitCategory: String,
        viewCacheInitCategory: String,
        popupSizeInitCategory: String,
        themeInitCategory: String,
        appInitializerUnresolvedAwaitCategory: String
    ) {
        let migrationShapedReadObserved = migrationReads.isEmpty == false
        let sdkLoadResolved =
            migrationShapedReadObserved || i18nRouteCount > 0 || ngVersionPresent
        let migrationWaitEntered = migrationShapedReadObserved
        let migrationWaitResolved =
            migrationPopulatedReads > 0 || i18nRouteCount > 0 || ngVersionPresent
        let initializerEntered =
            scriptsExecuted
            && (
                staticLoadingShellCount > 0
                    || ngVersionPresent == false
            )

        let appInitializerEnteredCategory =
            initializerEntered ? "entered" : "notObserved"
        let sdkLoadAwaitCategory: String
        if sdkLoadResolved {
            sdkLoadAwaitCategory = "sdkLoadResolved"
        } else if scriptsExecuted && staticLoadingShellCount > 0 {
            sdkLoadAwaitCategory = "sdkLoadStillPending"
        } else {
            sdkLoadAwaitCategory = "notObserved"
        }
        let migrationWaitEnteredCategory =
            migrationWaitEntered ? "entered" : "notObserved"
        let migrationWaitResolvedCategory: String
        if migrationWaitResolved {
            migrationWaitResolvedCategory = "resolved"
        } else if migrationWaitEntered {
            migrationWaitResolvedCategory = "stillPending"
        } else {
            migrationWaitResolvedCategory = "notObserved"
        }
        let i18nInitCategory: String
        if i18nRouteCount > 0 {
            i18nInitCategory = "i18nInitObserved"
        } else if migrationWaitResolved && ngVersionPresent == false {
            i18nInitCategory = "i18nInitPending"
        } else {
            i18nInitCategory = "notObserved"
        }
        let viewCacheInitCategory: String
        if ngVersionPresent && hyphenComponentCount > 0 {
            viewCacheInitCategory = "viewCacheInitObserved"
        } else if i18nRouteCount > 0 && ngVersionPresent == false {
            viewCacheInitCategory = "viewCacheInitPending"
        } else {
            viewCacheInitCategory = "notObserved"
        }
        let popupSizeInitCategory: String
        if ngVersionPresent && routerOutletPresent {
            popupSizeInitCategory = "popupSizeInitObserved"
        } else if ngVersionPresent {
            popupSizeInitCategory = "popupSizeInitPending"
        } else {
            popupSizeInitCategory = "notObserved"
        }
        let themeInitCategory: String
        if htmlLocaleClassPresent {
            themeInitCategory = "themeInitObserved"
        } else if ngVersionPresent {
            themeInitCategory = "themeInitPending"
        } else {
            themeInitCategory = "notObserved"
        }

        let appInitializerUnresolvedAwaitCategory: String
        if ngVersionPresent && staticLoadingShellCount == 0 {
            appInitializerUnresolvedAwaitCategory = "appInitializerComplete"
        } else if sdkLoadAwaitCategory == "sdkLoadStillPending" {
            appInitializerUnresolvedAwaitCategory = "sdkLoadStillPending"
        } else if swStorageWriteCapturedCountBucket != "0"
            && popupReadWrittenByServiceWorkerCountBucket == "0"
        {
            appInitializerUnresolvedAwaitCategory =
                "serviceWorkerStorageWriteNotMirrored"
        } else if swStorageWriteCapturedCountBucket == "0"
            && installStoragePersistedCategory == "installDispatchedNoWrite"
            && migrationWaitEntered
            && migrationWaitResolved == false
        {
            appInitializerUnresolvedAwaitCategory =
                "serviceWorkerMigrationWriteMissing"
        } else if storageSnapshotImportedCategory
            == "storageSnapshotNotImported"
            && migrationWaitEntered
        {
            appInitializerUnresolvedAwaitCategory = "storageSnapshotNotImported"
        } else if storageOnChangedDeliveryCategory == "onChangedDeliveryFailure"
            || storageOnChangedDeliveryCategory == "onChangedMissed"
        {
            appInitializerUnresolvedAwaitCategory =
                "storageOnChangedDeliveryFailure"
        } else if migrationWaitEntered
            && migrationWaitResolved == false
        {
            if migrationPopulatedReads > 0 {
                appInitializerUnresolvedAwaitCategory =
                    "migrationWaitEnteredAndPending"
            } else if migrationEmptyReads > 0 {
                appInitializerUnresolvedAwaitCategory = "migrationStateMissing"
            } else {
                appInitializerUnresolvedAwaitCategory =
                    "migrationWaitEnteredAndPending"
            }
        } else if migrationPopulatedReads > 0 && migrationWaitResolved == false
        {
            appInitializerUnresolvedAwaitCategory = "migrationStateShapeMismatch"
        } else if i18nInitCategory == "i18nInitPending" {
            appInitializerUnresolvedAwaitCategory =
                "appInitializerWaitingForI18n"
        } else if viewCacheInitCategory == "viewCacheInitPending" {
            appInitializerUnresolvedAwaitCategory =
                "appInitializerWaitingForViewCache"
        } else if popupSizeInitCategory == "popupSizeInitPending" {
            appInitializerUnresolvedAwaitCategory =
                "appInitializerWaitingForPopupSize"
        } else if themeInitCategory == "themeInitPending" {
            appInitializerUnresolvedAwaitCategory =
                "appInitializerWaitingForTheme"
        } else if staticLoadingShellCount > 0 && ngVersionPresent == false {
            appInitializerUnresolvedAwaitCategory =
                "loginRouteNotActivatedBecauseInitializerPending"
        } else if storageMigrationWriteVisibilityCategory
            == "readNoWriter"
            && correlation.popupReadKeyHashesNeverWritten.isEmpty == false
        {
            appInitializerUnresolvedAwaitCategory = "migrationStateMissing"
        } else {
            appInitializerUnresolvedAwaitCategory = "appInitializerUnknownAwait"
        }

        return (
            appInitializerEnteredCategory: appInitializerEnteredCategory,
            sdkLoadAwaitCategory: sdkLoadAwaitCategory,
            migrationWaitEnteredCategory: migrationWaitEnteredCategory,
            migrationWaitResolvedCategory: migrationWaitResolvedCategory,
            i18nInitCategory: i18nInitCategory,
            viewCacheInitCategory: viewCacheInitCategory,
            popupSizeInitCategory: popupSizeInitCategory,
            themeInitCategory: themeInitCategory,
            appInitializerUnresolvedAwaitCategory:
                appInitializerUnresolvedAwaitCategory
        )
    }

    static func deriveFirstVisibleUIGateDiagnostics(
        bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?,
        stagedSnapshots: [ChromeMV3LivePopupStagedSnapshot] = [],
        probeObject: [String: Any]? = nil,
        requiredResourceLoadFailure: Bool = false,
        storageLifecycleContext:
            ChromeMV3LivePopupStorageLifecycleContext = .notObserved
    ) -> ChromeMV3FirstVisibleUIGateDiagnostics? {
        guard bridgeSnapshot != nil || probeObject != nil else { return nil }
        let correlation =
            bridgeSnapshot?.appStateDependencyTrace.correlationSummary
            ?? ChromeMV3AppStateDependencyCorrelationSummary(
                classification: "notClassified",
                serviceWorkerState: "notObserved",
                popupReadKeyHashesNeverWritten: [],
                popupReadKeyHashesWrittenByServiceWorker: [],
                writtenKeyHashesWithoutObservedOnChangedDelivery: [],
                repeatedEmptyReadKeyHashes: [],
                serviceWorkerStorageWritesAfterConnect: false,
                serviceWorkerStorageWriteCountAfterConnect: 0,
                storageOnChangedReachedRegisteredListeners: false,
                missingAPIsObserved: [],
                networkOrAuthDependencyObserved: false,
                pendingRouteCount: 0,
                popupReachedUsableOnboardingOrLoginUI: false,
                domUsable: false,
                diagnostics: []
            )
        let routeEvents = bridgeSnapshot?.jsDebugRouteEvents ?? []
        let latest = preferredStagedSnapshot(stagedSnapshots)
        let postBootstrapStatus = finalPostBootstrapCoarseStatus(from: routeEvents)
        let migrationReads = migrationShapedPopupReads(
            in: bridgeSnapshot?.appStateDependencyTrace.storageOperations ?? []
        )
        let migrationEmptyReads = migrationReads.filter(\.emptyResult).count
        let migrationPopulatedReads = migrationReads.filter(\.populatedResult).count
        let repeatedMigrationReads =
            correlation.repeatedEmptyReadKeyHashes.count
        let neverWrittenReads =
            correlation.popupReadKeyHashesNeverWritten.count
        let serviceWorkerWrites =
            correlation.popupReadKeyHashesWrittenByServiceWorker.count
        let swWritesAfterConnect =
            correlation.serviceWorkerStorageWritesAfterConnect

        let ngVersionPresent = probeObject?["ngVersionPresent"] as? Bool ?? false
        let staticLoadingShellCount = probeObject?["staticLoadingShellCount"] as? Int ?? 0
        let spinnerLikeCount = probeObject?["spinnerLikeCount"] as? Int ?? 0
        let routerOutletPresent = probeObject?["routerOutletPresent"] as? Bool ?? false
        let hyphenComponentCount = probeObject?["hyphenComponentCount"] as? Int ?? 0
        let visibleTextLength = probeObject?["visibleTextLength"] as? Int
            ?? bucketLowerBound(finalDOM?.visibleTextLengthBucket ?? "0")
        let formControlCount = probeObject?["formControlCount"] as? Int ?? 0
        let buttonCount = probeObject?["buttonCount"] as? Int ?? 0
        let visibilityCategory =
            probeObject?["visibilityCategory"] as? String
            ?? finalDOM?.visibilityCategory
            ?? "unknown"
        let pathnameDepth = probeObject?["pathnameDepth"] as? Int ?? 0
        let htmlLocaleClassPresent =
            probeObject?["htmlLocaleClassPresent"] as? Bool ?? false

        let consoleErrorCategory = latest?.consoleErrorCategory ?? "none"
        let unhandledRejectionCategory =
            latest?.unhandledRejectionCategory ?? "none"
        let nativeMessagingCategory = nativeMessagingResultCategory(
            from: routeEvents,
            pendingRoutes:
                bridgeSnapshot?.pendingUnresolvedJSDebugRoutes ?? []
        )
        let nativeMessagingRequests = routeEvents.contains { event in
            let api = event.apiName.lowercased()
            return api.contains("nativemessaging.")
                || api.contains("runtime.connectnative")
                || api.contains("runtime.sendnativemessage")
        }

        let staticLoadingShellCategory: String
        if staticLoadingShellCount > 0 {
            staticLoadingShellCategory = "staticLoadingPresent"
        } else if ngVersionPresent {
            staticLoadingShellCategory = "staticLoadingRemoved"
        } else {
            staticLoadingShellCategory = "staticLoadingAbsent"
        }

        let angularBootstrapCategory: String
        if ngVersionPresent {
            angularBootstrapCategory = "bootstrapComplete"
        } else if latest?.scriptsExecuted == true
            || latest?.firstJSCheckpoint == true
        {
            angularBootstrapCategory = "bootstrapNotObserved"
        } else {
            angularBootstrapCategory = "notStarted"
        }

        let sdkReadyCategory: String
        if consoleErrorCategory != "none"
            || unhandledRejectionCategory != "none"
        {
            sdkReadyCategory = "sdkBlocked"
        } else if latest?.scriptsExecuted == true {
            sdkReadyCategory = "sdkReady"
        } else {
            sdkReadyCategory = "notObserved"
        }

        let migrationStateCategory: String
        if migrationPopulatedReads > 0 {
            migrationStateCategory = "migrationStateVisible"
        } else if migrationEmptyReads > 0 || repeatedMigrationReads > 0 {
            migrationStateCategory = "migrationStateMissing"
        } else {
            migrationStateCategory = "notObserved"
        }

        let migrationStateShapeCategory: String
        if migrationPopulatedReads > 0 {
            migrationStateShapeCategory = "objectPopulated"
        } else if migrationEmptyReads > 0 {
            migrationStateShapeCategory = "objectEmpty"
        } else {
            migrationStateShapeCategory = "notObserved"
        }

        let storageMigrationReadCategory: String
        if migrationPopulatedReads > 0 {
            storageMigrationReadCategory = "populatedRead"
        } else if migrationEmptyReads > 0 {
            storageMigrationReadCategory = "emptyRead"
        } else {
            storageMigrationReadCategory = "notObserved"
        }

        let storageMigrationWriteVisibilityCategory: String
        if serviceWorkerWrites > 0 {
            storageMigrationWriteVisibilityCategory = "serviceWorkerWriteVisible"
        } else if swWritesAfterConnect {
            storageMigrationWriteVisibilityCategory = "serviceWorkerWriteNotMirrored"
        } else if neverWrittenReads > 0 {
            storageMigrationWriteVisibilityCategory = "readNoWriter"
        } else {
            storageMigrationWriteVisibilityCategory = "notObserved"
        }

        let migrationWaitCategory: String
        if ngVersionPresent && staticLoadingShellCount == 0 {
            migrationWaitCategory = "resolved"
        } else if migrationEmptyReads > 0 && migrationPopulatedReads == 0 {
            migrationWaitCategory = "stillPending"
        } else {
            migrationWaitCategory = "notObserved"
        }

        let accountScaffoldCategory: String
        if neverWrittenReads > 0 && migrationPopulatedReads == 0 {
            accountScaffoldCategory = "guestScaffoldMissing"
        } else if migrationPopulatedReads > 0 {
            accountScaffoldCategory = "guestScaffoldPresent"
        } else {
            accountScaffoldCategory = "notObserved"
        }

        let i18nRouteCount = routeEvents.filter {
            $0.targetContext == "i18n"
        }.count
        let i18nReadyCategory =
            i18nRouteCount > 0 ? "i18nRouteObserved" : "notObserved"

        let themeReadyCategory =
            ngVersionPresent ? "themeAppliedOrPending" : "notObserved"
        let popupSizeReadyCategory =
            ngVersionPresent ? "popupSizeAppliedOrPending" : "notObserved"
        let viewCacheStateCategory =
            ngVersionPresent && hyphenComponentCount == 0
                ? "viewCacheWaitingBeforeFirstPaint"
                : "notObserved"

        let routerActivationCategory: String
        if routerOutletPresent == false {
            routerActivationCategory = ngVersionPresent
                ? "routerOutletMissing"
                : "routerNotStarted"
        } else if hyphenComponentCount == 0 {
            routerActivationCategory = "routerStartedNoVisibleRoute"
        } else {
            routerActivationCategory = "routerStartedWithComponents"
        }

        let redirectGuardCategory: String
        if ngVersionPresent == false {
            redirectGuardCategory = "redirectGuardNotRun"
        } else if pathnameDepth == 0 && hyphenComponentCount == 0 {
            redirectGuardCategory = "redirectGuardPending"
        } else if hyphenComponentCount > 0 || pathnameDepth > 0 {
            redirectGuardCategory = "redirectGuardObserved"
        } else {
            redirectGuardCategory = "redirectGuardNotRun"
        }

        let loginRouteActivationCategory: String
        if hyphenComponentCount > 0 {
            loginRouteActivationCategory = "guestRouteComponentPresent"
        } else if ngVersionPresent && routerOutletPresent {
            loginRouteActivationCategory = "loginRouteNotActivated"
        } else {
            loginRouteActivationCategory = "notObserved"
        }

        let firstVisibleComponentCategory: String
        if visibleTextLength > 0 || formControlCount > 0 || buttonCount > 0 {
            firstVisibleComponentCategory = "visibleComponentObserved"
        } else if hyphenComponentCount > 0
            && ["displayNone", "visibilityHidden", "opacityZero", "zeroSize"]
                .contains(visibilityCategory)
        {
            firstVisibleComponentCategory = "componentMountedButHidden"
        } else if spinnerLikeCount > 0 || staticLoadingShellCount > 0 {
            firstVisibleComponentCategory = "firstVisibleComponentWaiting"
        } else if hyphenComponentCount > 0 {
            firstVisibleComponentCategory = "componentMountedNoVisibleText"
        } else {
            firstVisibleComponentCategory = "notConstructed"
        }

        let appInitializerGateCategory: String
        if ngVersionPresent && staticLoadingShellCount == 0 {
            appInitializerGateCategory = "appInitializerComplete"
        } else if migrationWaitCategory == "stillPending" {
            appInitializerGateCategory = "appInitializerWaitingForMigration"
        } else if ngVersionPresent == false {
            appInitializerGateCategory = "appInitializerStillPending"
        } else {
            appInitializerGateCategory = "appInitializerPartial"
        }

        let nativeDependencyForVisibleUICategory =
            nativeMessagingRequests ? nativeMessagingCategory : "notRequested"

        let storageMirrorDiagnostics = deriveStorageMirrorDiagnostics(
            bridgeSnapshot: bridgeSnapshot,
            correlation: correlation,
            storageLifecycleContext: storageLifecycleContext
        )
        let appInitializerPhase = deriveAppInitializerPhaseDiagnostics(
            scriptsExecuted: latest?.scriptsExecuted == true
                || latest?.firstJSCheckpoint == true,
            staticLoadingShellCount: staticLoadingShellCount,
            ngVersionPresent: ngVersionPresent,
            migrationReads: migrationReads,
            migrationEmptyReads: migrationEmptyReads,
            migrationPopulatedReads: migrationPopulatedReads,
            i18nRouteCount: i18nRouteCount,
            hyphenComponentCount: hyphenComponentCount,
            routerOutletPresent: routerOutletPresent,
            htmlLocaleClassPresent: htmlLocaleClassPresent,
            correlation: correlation,
            storageMigrationWriteVisibilityCategory:
                storageMigrationWriteVisibilityCategory,
            installStoragePersistedCategory:
                storageMirrorDiagnostics.installStoragePersistedCategory,
            swStorageWriteCapturedCountBucket:
                storageMirrorDiagnostics.swStorageWriteCapturedCountBucket,
            popupReadWrittenByServiceWorkerCountBucket:
                storageMirrorDiagnostics
                .popupReadWrittenByServiceWorkerCountBucket,
            storageSnapshotImportedCategory:
                storageMirrorDiagnostics.storageSnapshotImportedCategory,
            storageOnChangedDeliveryCategory:
                storageMirrorDiagnostics.storageOnChangedDeliveryCategory
        )

        let firstVisibleUIGateCategory: String
        if requiredResourceLoadFailure {
            firstVisibleUIGateCategory = "templateOrChunkLoadMissing"
        } else if sdkReadyCategory == "sdkBlocked" {
            firstVisibleUIGateCategory = "sdkBlocked"
        } else if nativeMessagingRequests
            && nativeMessagingCategory != "notRequested"
        {
            firstVisibleUIGateCategory = "nativeDependencyRequiredForVisibleUI"
        } else if appInitializerPhase.appInitializerUnresolvedAwaitCategory
            != "appInitializerComplete"
            && appInitializerPhase.appInitializerUnresolvedAwaitCategory
                != "appInitializerUnknownAwait"
        {
            firstVisibleUIGateCategory =
                appInitializerPhase.appInitializerUnresolvedAwaitCategory
        } else if appInitializerGateCategory == "appInitializerStillPending"
            || (
                staticLoadingShellCategory == "staticLoadingPresent"
                    && ngVersionPresent == false
            )
        {
            firstVisibleUIGateCategory = "appInitializerStillPending"
        } else if appInitializerGateCategory
            == "appInitializerWaitingForMigration"
            || migrationWaitCategory == "stillPending"
        {
            firstVisibleUIGateCategory = migrationPopulatedReads > 0
                ? "migrationWaitStillPending"
                : "migrationStateMissing"
        } else if migrationStateCategory == "migrationStateMissing"
            && neverWrittenReads > 0
        {
            firstVisibleUIGateCategory = repeatedMigrationReads > 0
                ? "storageShapeBlocksLoginRoute"
                : "missingGuestStateForLoginRoute"
        } else if routerActivationCategory == "routerNotStarted" {
            firstVisibleUIGateCategory = "routerNotStarted"
        } else if redirectGuardCategory == "redirectGuardNotRun"
            || redirectGuardCategory == "redirectGuardPending"
        {
            firstVisibleUIGateCategory = redirectGuardCategory
                == "redirectGuardPending"
                ? "redirectGuardNotRun"
                : "redirectGuardNotRun"
        } else if loginRouteActivationCategory == "loginRouteNotActivated" {
            firstVisibleUIGateCategory = "loginRouteNotActivated"
        } else if routerActivationCategory == "routerStartedNoVisibleRoute" {
            firstVisibleUIGateCategory = "routerStartedNoVisibleRoute"
        } else if firstVisibleComponentCategory == "componentMountedButHidden" {
            firstVisibleUIGateCategory = "componentMountedButHidden"
        } else if firstVisibleComponentCategory
            == "firstVisibleComponentWaiting"
            || postBootstrapStatus == "spinner/loading"
            || spinnerLikeCount > 0
        {
            firstVisibleUIGateCategory = viewCacheStateCategory
                == "viewCacheWaitingBeforeFirstPaint"
                ? "viewCacheWaitingBeforeFirstPaint"
                : "firstVisibleComponentWaiting"
        } else if visibleTextLength == 0 && formControlCount == 0
            && buttonCount == 0
        {
            if ["displayNone", "visibilityHidden", "opacityZero", "zeroSize"]
                .contains(visibilityCategory)
            {
                firstVisibleUIGateCategory = "cssOrLayoutHidesFirstUI"
            } else if postBootstrapStatus == "blank"
                || postBootstrapStatus == "waits on app state"
            {
                firstVisibleUIGateCategory = "extensionLocalRenderState"
            } else {
                firstVisibleUIGateCategory = "unknownOnlyIfNoSignal"
            }
        } else {
            firstVisibleUIGateCategory = "extensionLocalRenderState"
        }

        return ChromeMV3FirstVisibleUIGateDiagnostics(
            firstVisibleUIGateCategory: firstVisibleUIGateCategory,
            appInitializerGateCategory: appInitializerGateCategory,
            angularBootstrapCategory: angularBootstrapCategory,
            routerActivationCategory: routerActivationCategory,
            redirectGuardCategory: redirectGuardCategory,
            loginRouteActivationCategory: loginRouteActivationCategory,
            firstVisibleComponentCategory: firstVisibleComponentCategory,
            staticLoadingShellCategory: staticLoadingShellCategory,
            migrationWaitCategory: migrationWaitCategory,
            migrationStateCategory: migrationStateCategory,
            migrationStateShapeCategory: migrationStateShapeCategory,
            accountScaffoldCategory: accountScaffoldCategory,
            viewCacheStateCategory: viewCacheStateCategory,
            sdkReadyCategory: sdkReadyCategory,
            i18nReadyCategory: i18nReadyCategory,
            themeReadyCategory: themeReadyCategory,
            popupSizeReadyCategory: popupSizeReadyCategory,
            storageMigrationReadCategory: storageMigrationReadCategory,
            storageMigrationWriteVisibilityCategory:
                storageMigrationWriteVisibilityCategory,
            nativeDependencyForVisibleUICategory:
                nativeDependencyForVisibleUICategory,
            appInitializerEnteredCategory:
                appInitializerPhase.appInitializerEnteredCategory,
            sdkLoadAwaitCategory: appInitializerPhase.sdkLoadAwaitCategory,
            migrationWaitEnteredCategory:
                appInitializerPhase.migrationWaitEnteredCategory,
            migrationWaitResolvedCategory:
                appInitializerPhase.migrationWaitResolvedCategory,
            i18nInitCategory: appInitializerPhase.i18nInitCategory,
            viewCacheInitCategory: appInitializerPhase.viewCacheInitCategory,
            popupSizeInitCategory: appInitializerPhase.popupSizeInitCategory,
            themeInitCategory: appInitializerPhase.themeInitCategory,
            appInitializerUnresolvedAwaitCategory:
                appInitializerPhase.appInitializerUnresolvedAwaitCategory,
            swStorageWriteCapturedCountBucket:
                storageMirrorDiagnostics.swStorageWriteCapturedCountBucket,
            swStorageWriteMirroredCountBucket:
                storageMirrorDiagnostics.swStorageWriteMirroredCountBucket,
            popupReadWrittenByServiceWorkerCountBucket:
                storageMirrorDiagnostics
                .popupReadWrittenByServiceWorkerCountBucket,
            storageNamespaceMatchCategory:
                storageMirrorDiagnostics.storageNamespaceMatchCategory,
            storageSnapshotImportedCategory:
                storageMirrorDiagnostics.storageSnapshotImportedCategory,
            storageOnChangedDeliveryCategory:
                storageMirrorDiagnostics.storageOnChangedDeliveryCategory,
            installStoragePersistedCategory:
                storageMirrorDiagnostics.installStoragePersistedCategory,
            popupWakeStorageSeededCategory:
                storageMirrorDiagnostics.popupWakeStorageSeededCategory
        )
    }

    static func controlledPopupAppStateBoundaryDiagnostics(
        bridgeSnapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?,
        stagedSnapshots: [ChromeMV3LivePopupStagedSnapshot] = [],
        firstVisibleUIGate: ChromeMV3FirstVisibleUIGateDiagnostics? = nil
    ) -> ChromeMV3ControlledPopupAppStateBoundaryDiagnostics? {
        guard let snapshot = bridgeSnapshot else { return nil }
        let trace = snapshot.appStateDependencyTrace.correlationSummary
        let postParse = postParseSanitizedDiagnostics(
            bridgeSnapshot: snapshot,
            finalDOM: finalDOM
        )
        let extensionBoundaryClassifier = normalizeExtensionBoundaryClassifier(
            deriveExtensionClassifier(
                bridgeSnapshot: snapshot,
                finalDOM: finalDOM,
                firstVisibleUIGate: firstVisibleUIGate
            ) ?? trace.classification
        )
        let firstStable = firstStableAppStateClassifier(
            bridgeSnapshot: snapshot,
            stagedSnapshots: stagedSnapshots
        )
        let routeEvents = snapshot.jsDebugRouteEvents
        let pendingRoutes = snapshot.pendingUnresolvedJSDebugRoutes
        let serviceWorkerListeners =
            postParseServiceWorkerListenerCounts(in: snapshot)
        let popupMessagingCategory = postParse.map(\.popupMessagingCategory)
            ?? categorizePostParseRoutes(
                snapshot.sanitizedBridgeRouteRecords.filter {
                    ["runtime.sendMessage", "runtime.connect"].contains($0.apiName)
                        && $0.sourceContext != "contentScript"
                }
            )
        let storageCategory = postParse?.storageCategory
            ?? (trace.popupReadKeyHashesNeverWritten.isEmpty == false
                ? "readNoWriter" : "noObservableWrite")
        let browserBlocker = postParse?.firstBrowserBlocker ?? "unknown"
        let boundaryKind: String
        switch extensionBoundaryClassifier {
        case "extensionLocalAppState", "extensionLocalRenderState",
            "appStateWaitWithNoWriter", "appStateWaitWithNoObservableDependency":
            boundaryKind = "extension-local"
        default:
            if [
                "storageAppStateReadNoWriter", "storageOnChangedMissed",
                "storageWriteNotVisibleToPopup", "missingNarrowChromeAPI",
                "serviceWorkerOnMessageMissing", "serviceWorkerOnConnectMissing",
                "popupToServiceWorkerRouteDropped",
                "popupToContentScriptRouteDropped", "networkOrAuthWait",
            ].contains(browserBlocker) {
                boundaryKind = "browser-side"
            } else if trace.classification == "appStateWaitWithNoWriter" {
                boundaryKind = "extension-local"
            } else {
                boundaryKind = "unknown"
            }
        }
        let after3000msSnapshotLine =
            stagedSnapshots.last(where: { $0.stage == "after3000ms" })?
            .compactSanitizedLogLine
            .replacingOccurrences(of: "stage=after3000ms ", with: "after3000ms=")

        return ChromeMV3ControlledPopupAppStateBoundaryDiagnostics(
            firstStableAppStateClassifier: firstStable,
            extensionBoundaryClassifier: extensionBoundaryClassifier,
            boundaryKind: boundaryKind,
            nativeMessagingRequestCategory:
                nativeMessagingRequestCategory(from: routeEvents),
            nativeMessagingResultCategory: nativeMessagingResultCategory(
                from: routeEvents,
                pendingRoutes: pendingRoutes
            ),
            pendingRouteBucket: countBucket(trace.pendingRouteCount),
            serviceWorkerListenerCategory:
                "onMessage=\(serviceWorkerListeners.onMessage),onConnect=\(serviceWorkerListeners.onConnect)",
            popupMessagingCategory: popupMessagingCategory,
            portRouteCategory: portRouteCategory(
                from: snapshot.sanitizedBridgeRouteRecords,
                pendingRoutes: pendingRoutes
            ),
            storageCategory: storageCategory,
            after3000msSnapshotLine: after3000msSnapshotLine
        )
    }

    static func buildStagedSnapshot(
        stage: String,
        domObject: [String: Any],
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        pendingRoutes: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        observedMethods: [String],
        bridgeInstalled: Bool,
        navigationStarted: Bool,
        navigationFinished: Bool,
        routeRecords:
            [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = [],
        harnessOnMessageListenerCount: Int = 0,
        harnessOnConnectListenerCount: Int = 0
    ) -> ChromeMV3LivePopupStagedSnapshot {
        let readyState = domObject["readyState"] as? String ?? "unknown"
        let urlLoaded = domObject["navigationCommitted"] as? Bool ?? false
        let buckets = apiRouteCountBuckets(
            from: routeEvents,
            pendingRoutes: pendingRoutes,
            routeRecords: routeRecords,
            harnessOnMessageListenerCount: harnessOnMessageListenerCount,
            harnessOnConnectListenerCount: harnessOnConnectListenerCount
        )
        let portDelivery = portDeliveryDiagnostics(from: routeEvents)
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
            ),
            nativeMessagingRequestCountBucket: countBucket(
                buckets.nativeMessagingRequest
            ),
            nativeMessagingResultCategory: nativeMessagingResultCategory(
                from: routeEvents,
                pendingRoutes: pendingRoutes
            ),
            swOutboxCapturedCountBucket: countBucket(portDelivery.swOutboxCaptured),
            swOutboxDeliveredToPopupCountBucket: countBucket(
                portDelivery.swOutboxDelivered
            ),
            popupPortOnMessageListenerCategory: portDelivery.listenerCategory,
            pendingInboundPortMessagesBucket: countBucket(portDelivery.pendingInbound),
            portDisconnectCategory: portDelivery.disconnectCategory
        )
    }

    static func synthesizeStagedSnapshots(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        observedMethods: [String],
        bridgeInstalled: Bool,
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?,
        routeRecords:
            [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = [],
        harnessOnMessageListenerCount: Int = 0,
        harnessOnConnectListenerCount: Int = 0
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
                    navigationFinished: navigation.finished,
                    routeRecords: routeRecords,
                    harnessOnMessageListenerCount:
                        harnessOnMessageListenerCount,
                    harnessOnConnectListenerCount:
                        harnessOnConnectListenerCount
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
        "onNativeMessagingRoute",
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

    static func bridgeInjectionProven(
        trace: ChromeMV3LivePopupProductPathTrace
    ) -> Bool {
        guard trace.bridgeInstalled
            || trace.stagedSnapshots.contains(where: { $0.bridgeInstalled })
        else {
            return false
        }
        return reconciledScriptsExecuted(trace: trace)
            || reconciledFirstJSCheckpoint(trace: trace)
    }

    static func reconcileTraceWithStagedSnapshots(
        _ trace: ChromeMV3LivePopupProductPathTrace
    ) -> ChromeMV3LivePopupProductPathTrace {
        guard trace.stagedSnapshots.isEmpty == false else { return trace }
        var reconciled = trace
        if trace.stagedSnapshots.contains(where: { $0.bridgeInstalled }) {
            reconciled.bridgeInstalled = true
        }
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

    /// Lower-bound service-worker listener counts observed across the staged
    /// snapshots. Staged buckets are derived from real service-worker harness
    /// listener state captured at each stage, so they remain authoritative even
    /// when a single top-level reading is taken after the shared lifecycle
    /// session has already been released and reports zero.
    static func stagedServiceWorkerListenerLowerBounds(
        _ snapshots: [ChromeMV3LivePopupStagedSnapshot]
    ) -> (onMessage: Int, onConnect: Int) {
        var onMessage = 0
        var onConnect = 0
        for snapshot in snapshots {
            onMessage = max(
                onMessage,
                diagnosticBucketLowerBound(
                    snapshot.serviceWorkerOnMessageListenerCountBucket
                )
            )
            onConnect = max(
                onConnect,
                diagnosticBucketLowerBound(
                    snapshot.serviceWorkerOnConnectListenerCountBucket
                )
            )
        }
        return (onMessage, onConnect)
    }

    /// Port outbox delivery diagnostics derived from the preferred staged
    /// snapshot when present, otherwise reconstructed from the route events.
    /// Mirrors the extraction used by `classifyPortDeliveryFailure` so the
    /// connect-blocker and port-delivery classifiers reason from the same
    /// authoritative evidence.
    static func connectBlockerPortDelivery(
        trace: ChromeMV3LivePopupProductPathTrace,
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> PortDeliveryDiagnostics {
        if let latest = preferredStagedSnapshot(trace.stagedSnapshots) {
            return PortDeliveryDiagnostics(
                swOutboxCaptured: diagnosticBucketLowerBound(
                    latest.swOutboxCapturedCountBucket
                ),
                swOutboxDelivered: diagnosticBucketLowerBound(
                    latest.swOutboxDeliveredToPopupCountBucket
                ),
                pendingInbound: diagnosticBucketLowerBound(
                    latest.pendingInboundPortMessagesBucket
                ),
                listenerCategory: latest.popupPortOnMessageListenerCategory,
                disconnectCategory: latest.portDisconnectCategory
            )
        }
        return portDeliveryDiagnostics(from: routeEvents)
    }

    static func classifyServiceWorkerConnectBlocker(
        trace: ChromeMV3LivePopupProductPathTrace,
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = [],
        routeRecords:
            [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = [],
        harnessOnConnectCount: Int = 0,
        harnessOnMessageCount: Int = 0
    ) -> ChromeMV3LivePopupFailureClassifier? {
        guard let latest = preferredStagedSnapshot(trace.stagedSnapshots) else {
            return nil
        }
        let runtimeConnectObserved =
            latest.runtimeConnectCountBucket != "0"
            || routeEvents.contains {
                $0.apiName.lowercased().contains("runtime.connect")
            }
        guard runtimeConnectObserved else { return nil }

        // Service-worker Port outbox delivery is authoritative proof that the
        // service-worker runtime.onConnect listener fired and the Port
        // round-trips. Per the Chrome messaging docs, a Port created by
        // runtime.connect immediately reaches runtime.onConnect in the
        // receiving end, and messages posted back from that end only exist if a
        // listener ran. When any outbox was captured or delivered, a "missing
        // listener" / "connect dispatched before startup" classification is
        // provably wrong, so defer to the port-delivery / app-state classifiers.
        let portDelivery = connectBlockerPortDelivery(
            trace: trace,
            routeEvents: routeEvents
        )
        if portDelivery.swOutboxCaptured > 0
            || portDelivery.swOutboxDelivered > 0
        {
            return nil
        }

        // Reconcile the (possibly stale) top-level harness listener counts with
        // the listener state captured in the staged snapshots. A top-level
        // reading of zero must not override staged evidence that the
        // service-worker runtime.onConnect/onMessage listeners were live, or the
        // classifier reports a missing listener when the real condition is a
        // connect/startup ordering issue or a pending port response.
        let stagedListeners =
            stagedServiceWorkerListenerLowerBounds(trace.stagedSnapshots)
        let harnessOnConnectCount =
            max(harnessOnConnectCount, stagedListeners.onConnect)
        let harnessOnMessageCount =
            max(harnessOnMessageCount, stagedListeners.onMessage)

        let serviceWorkerListeners = serviceWorkerListenerCounts(
            from: routeRecords,
            harnessOnMessageListenerCount: harnessOnMessageCount,
            harnessOnConnectListenerCount: harnessOnConnectCount
        )
        let popupConnectRoutes = routeRecords.filter {
            $0.apiName == "runtime.connect" && $0.sourceContext != "contentScript"
        }
        let connectFailedRoutes = popupConnectRoutes.filter(postParseRouteFailed)
        let connectDelivered = popupConnectRoutes.contains(where: \.listenerInvoked)

        if harnessOnConnectCount == 0, serviceWorkerListeners.onConnect == 0 {
            if connectFailedRoutes.isEmpty {
                if connectDelivered == false,
                   latest.pendingBridgeRoutesBucket != "0"
                {
                    return .serviceWorkerConnectDispatchedBeforeStartup
                }
                // No observed failed runtime.connect route record. The popup
                // context cannot directly observe service-worker onConnect
                // listener registration, so the absence of staged listener
                // evidence is not proof of a missing listener. Defer to the
                // port-delivery classifier (for example .portConnectedNoSwOutbox)
                // rather than asserting a missing listener from stale state.
                return nil
            }
            return .serviceWorkerOnConnectListenerMissing
        }

        if let failedRoute = connectFailedRoutes.first {
            if failedRoute.listenerCount == 0, failedRoute.listenerInvoked == false {
                if harnessOnConnectCount > 0 {
                    return .serviceWorkerConnectDispatchedBeforeStartup
                }
                return .serviceWorkerOnConnectListenerMissing
            }
            if failedRoute.listenerCount > 0, failedRoute.listenerInvoked == false {
                return .runtimePortSenderShapeMismatch
            }
        }

        if connectDelivered == false,
           latest.pendingBridgeRoutesBucket == "0",
           serviceWorkerListeners.onConnect > 0
        {
            return .popupWaitingOnPortResponse
        }

        return nil
    }

    static func classifyBootstrapFailure(
        trace: ChromeMV3LivePopupProductPathTrace,
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = [],
        routeRecords:
            [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = [],
        harnessOnConnectCount: Int = 0,
        harnessOnMessageCount: Int = 0
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
               ) == false,
               bridgeInjectionProven(trace: trace) == false
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
            if let connectBlocker = classifyServiceWorkerConnectBlocker(
                trace: trace,
                routeEvents: routeEvents,
                routeRecords: routeRecords,
                harnessOnConnectCount: harnessOnConnectCount,
                harnessOnMessageCount: harnessOnMessageCount
            ) {
                return connectBlocker
            }
            if latest.runtimeSendMessageCountBucket != "0",
               latest.serviceWorkerOnMessageListenerCountBucket == "0"
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

    static func classifyPortDeliveryFailure(
        trace: ChromeMV3LivePopupProductPathTrace,
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = []
    ) -> ChromeMV3LivePopupFailureClassifier? {
        let latest = preferredStagedSnapshot(trace.stagedSnapshots)
        let portDelivery = latest.map {
            PortDeliveryDiagnostics(
                swOutboxCaptured: diagnosticBucketLowerBound(
                    $0.swOutboxCapturedCountBucket
                ),
                swOutboxDelivered: diagnosticBucketLowerBound(
                    $0.swOutboxDeliveredToPopupCountBucket
                ),
                pendingInbound: diagnosticBucketLowerBound(
                    $0.pendingInboundPortMessagesBucket
                ),
                listenerCategory: $0.popupPortOnMessageListenerCategory,
                disconnectCategory: $0.portDisconnectCategory
            )
        } ?? portDeliveryDiagnostics(from: routeEvents)
        let runtimeConnectObserved =
            (latest?.runtimeConnectCountBucket ?? "0") != "0"
            || routeEvents.contains {
                $0.apiName.lowercased().contains("runtime.connect")
            }
        guard runtimeConnectObserved else { return nil }

        if portDelivery.swOutboxCaptured == 0 {
            return .portConnectedNoSwOutbox
        }
        if portDelivery.swOutboxDelivered == 0 {
            return .runtimePortEnvelopeMismatch
        }
        return nil
    }

    static func classifyAppStateBootstrapGap(
        trace: ChromeMV3LivePopupProductPathTrace,
        firstVisibleUIGate: ChromeMV3FirstVisibleUIGateDiagnostics? = nil
    ) -> ChromeMV3LivePopupFailureClassifier? {
        if let firstVisibleUIGate,
           firstVisibleUIGate.firstVisibleUIGateCategory
               != "missingGuestStateForLoginRoute",
           firstVisibleUIGate.firstVisibleUIGateCategory
               != "storageShapeBlocksLoginRoute",
           [
               "appInitializerStillPending",
               "appInitializerWaitingForMigration",
               "sdkLoadStillPending",
               "migrationWaitEnteredAndPending",
               "migrationStateMissing",
               "migrationStateShapeMismatch",
               "serviceWorkerMigrationWriteMissing",
               "serviceWorkerStorageWriteNotMirrored",
               "storageSnapshotNotImported",
               "storageOnChangedDeliveryFailure",
               "appInitializerWaitingForI18n",
               "appInitializerWaitingForViewCache",
               "appInitializerWaitingForPopupSize",
               "appInitializerWaitingForTheme",
               "loginRouteNotActivatedBecauseInitializerPending",
               "appInitializerUnknownAwait",
               "migrationWaitStillPending",
               "migrationStateMissing",
               "routerNotStarted",
               "redirectGuardNotRun",
               "loginRouteNotActivated",
               "routerStartedNoVisibleRoute",
               "componentMountedButHidden",
               "firstVisibleComponentWaiting",
               "viewCacheWaitingBeforeFirstPaint",
               "extensionLocalRenderState",
               "cssOrLayoutHidesFirstUI",
           ].contains(firstVisibleUIGate.firstVisibleUIGateCategory)
        {
            return .extensionLocalRenderState
        }
        if trace.extensionClassifier == "extensionLocalAppState" {
            return .extensionLocalAppState
        }
        if trace.extensionClassifier == "extensionLocalRenderState" {
            return .extensionLocalRenderState
        }
        if trace.extensionClassifier == "appStateWaitWithNoWriter" {
            return .appStateWaitWithNoWriter
        }

        guard let latest = preferredStagedSnapshot(trace.stagedSnapshots) else {
            return nil
        }
        guard latest.visibleTextBucket == "0",
              latest.storageReadCountBucket != "0",
              latest.storageWriteCountBucket == "0",
              bridgeInjectionProven(trace: trace)
        else {
            return nil
        }

        if latest.appRootPresent {
            return .popupAppRootEmptyAfterBootstrap
        }
        return .appStateWaitWithNoWriter
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
        finalDOM: ChromeMV3LivePopupDOMCheckpoint?,
        firstVisibleUIGate: ChromeMV3FirstVisibleUIGateDiagnostics? = nil
    ) -> String? {
        guard let snapshot = bridgeSnapshot else { return nil }
        let correlation =
            snapshot.appStateDependencyTrace.correlationSummary.classification
        if let firstVisibleUIGate,
           [
               "appInitializerStillPending",
               "appInitializerWaitingForMigration",
               "sdkLoadStillPending",
               "migrationWaitEnteredAndPending",
               "migrationStateMissing",
               "migrationStateShapeMismatch",
               "serviceWorkerMigrationWriteMissing",
               "serviceWorkerStorageWriteNotMirrored",
               "storageSnapshotNotImported",
               "storageOnChangedDeliveryFailure",
               "appInitializerWaitingForI18n",
               "appInitializerWaitingForViewCache",
               "appInitializerWaitingForPopupSize",
               "appInitializerWaitingForTheme",
               "loginRouteNotActivatedBecauseInitializerPending",
               "appInitializerUnknownAwait",
               "migrationWaitStillPending",
               "migrationStateMissing",
               "routerNotStarted",
               "redirectGuardNotRun",
               "loginRouteNotActivated",
               "routerStartedNoVisibleRoute",
               "componentMountedButHidden",
               "firstVisibleComponentWaiting",
               "viewCacheWaitingBeforeFirstPaint",
               "extensionLocalRenderState",
               "cssOrLayoutHidesFirstUI",
           ].contains(firstVisibleUIGate.firstVisibleUIGateCategory)
        {
            return "extensionLocalRenderState"
        }
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
            if let firstVisibleUIGate,
               firstVisibleUIGate.appInitializerGateCategory
                   != "appInitializerComplete"
            {
                return "extensionLocalRenderState"
            }
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
        let harness = harnessListenerCounts(from: snapshot)
        return serviceWorkerListenerCounts(
            from: snapshot.sanitizedBridgeRouteRecords,
            harnessOnMessageListenerCount: harness.onMessage,
            harnessOnConnectListenerCount: harness.onConnect
        )
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

        if trace.classification == "serviceWorkerStorageWriteNotMirrored" {
            return "serviceWorkerStorageWriteNotMirrored"
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
        routeEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = [],
        routeRecords:
            [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = [],
        harnessOnConnectCount: Int = 0,
        harnessOnMessageCount: Int = 0,
        firstVisibleUIGate: ChromeMV3FirstVisibleUIGateDiagnostics? = nil
    ) -> ChromeMV3LivePopupFailureClassifier {
        let trace = reconcileTraceWithStagedSnapshots(trace)
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

        let bootstrapClassifier = classifyBootstrapFailure(
            trace: trace,
            routeEvents: routeEvents,
            routeRecords: routeRecords,
            harnessOnConnectCount: harnessOnConnectCount,
            harnessOnMessageCount: harnessOnMessageCount
        )
        if let bootstrapClassifier,
           bootstrapClassifier != .popupAppRootPresentButEmpty,
           bootstrapClassifier != .popupAppRootMountedButNoVisibleText
        {
            return bootstrapClassifier
        }

        if let portClassifier = classifyPortDeliveryFailure(
            trace: trace,
            routeEvents: routeEvents
        ),
            portClassifier == .runtimePortEnvelopeMismatch
                || portClassifier == .portConnectedNoSwOutbox
        {
            return portClassifier
        }

        if let appStateClassifier = classifyAppStateBootstrapGap(
            trace: trace,
            firstVisibleUIGate: firstVisibleUIGate
        ) {
            return appStateClassifier
        }

        if let bootstrapClassifier,
           bootstrapClassifier == .popupAppRootPresentButEmpty
            || bootstrapClassifier == .popupAppRootMountedButNoVisibleText
        {
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

        if trace.extensionClassifier == "extensionLocalRenderState"
            || firstVisibleUIGate?.firstVisibleUIGateCategory
                == "extensionLocalRenderState"
        {
            return .extensionLocalRenderState
        }
        if trace.extensionClassifier == "extensionLocalAppState" {
            return .extensionLocalAppState
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
                } else if api.contains("nativemessaging.")
                    || api.contains("runtime.connectnative")
                    || api.contains("runtime.sendnativemessage")
                {
                    capture(stage: "onNativeMessagingRoute")
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
            let routeRecords =
                bridgeSnapshot?.sanitizedBridgeRouteRecords ?? []
            let harnessCounts =
                ChromeMV3LivePopupProductPathTraceBuilder.harnessListenerCounts(
                    from: bridgeSnapshot
                )
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
                navigationFinished: self.navigationFinished || navigation.finished,
                routeRecords: routeRecords,
                harnessOnMessageListenerCount: harnessCounts.onMessage,
                harnessOnConnectListenerCount: harnessCounts.onConnect
            )
            if self.snapshots.contains(where: { $0.stage == stage }) == false {
                self.snapshots.append(snapshot)
            }
        }
    }
}

#endif
