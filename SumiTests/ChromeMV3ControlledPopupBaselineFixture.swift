import Foundation

@testable import Sumi

enum ChromeMV3ControlledPopupBaselineLayer: String, CaseIterable, Sendable {
    case controlledPopupHost = "controlledPopupHost"
    case popupBridge = "popupBridge"
    case serviceWorkerRuntimeStorageTabsScripting =
        "serviceWorkerRuntimeStorageTabsScripting"
    case realExtensionAppSpecific = "realExtensionAppSpecific"
}

enum ChromeMV3ControlledPopupBaselineOutcome: String, CaseIterable, Sendable {
    case usableUI
    case staticPopupHostFailure
    case popupLocalScriptFailure
    case popupUnhandledException
    case popupUnhandledRejection
    case resourceLoadFailure
    case moduleScriptFailure
    case CSPFailure
    case popupBridgeFailure
    case popupBridgeBootstrapFailure
    case storageFailure
    case storageLocalFailure
    case storageSessionFailure
    case storageSyncFailure
    case storageOnChangedFailure
    case runtimeSendMessageFailure
    case runtimeConnectFailure
    case tabsQueryFailure
    case tabsSendMessageFailure
    case scriptingExecuteScriptFailure
    case serviceWorkerLifecycleFailure
    case contentScriptAttachFailure
    case nativeMessagingRequired
    case moduleWorkerUnsupported
    case missingNarrowChromeAPI
    case authOrNetworkRequired
    case extensionLocalAppState
    case extensionLocalRenderState
    case unknown
    case unknownButStop

    static let catalog: Set<String> = Set(
        allCases.map(\.rawValue)
    )
}

enum ChromeMV3ControlledPopupPostResourceBlocker: String, CaseIterable, Sendable {
    case popupLocalScriptFailure
    case popupUnhandledException
    case popupUnhandledRejection
    case popupBridgeBootstrapFailure
    case missingNarrowChromeAPI
    case runtimeSendMessageFailure
    case runtimeConnectFailure
    case serviceWorkerLifecycleFailure
    case storageLocalFailure
    case storageSessionFailure
    case storageSyncFailure
    case storageOnChangedFailure
    case tabsQueryFailure
    case tabsSendMessageFailure
    case scriptingExecuteScriptFailure
    case nativeMessagingRequired
    case authOrNetworkRequired
    case extensionLocalAppState
    case extensionLocalRenderState
    case usableUI
    case unknownButStop

    var baselineOutcome: ChromeMV3ControlledPopupBaselineOutcome {
        switch self {
        case .popupLocalScriptFailure: .popupLocalScriptFailure
        case .popupUnhandledException: .popupUnhandledException
        case .popupUnhandledRejection: .popupUnhandledRejection
        case .popupBridgeBootstrapFailure: .popupBridgeBootstrapFailure
        case .missingNarrowChromeAPI: .missingNarrowChromeAPI
        case .runtimeSendMessageFailure: .runtimeSendMessageFailure
        case .runtimeConnectFailure: .runtimeConnectFailure
        case .serviceWorkerLifecycleFailure: .serviceWorkerLifecycleFailure
        case .storageLocalFailure: .storageLocalFailure
        case .storageSessionFailure: .storageSessionFailure
        case .storageSyncFailure: .storageSyncFailure
        case .storageOnChangedFailure: .storageOnChangedFailure
        case .tabsQueryFailure: .tabsQueryFailure
        case .tabsSendMessageFailure: .tabsSendMessageFailure
        case .scriptingExecuteScriptFailure: .scriptingExecuteScriptFailure
        case .nativeMessagingRequired: .nativeMessagingRequired
        case .authOrNetworkRequired: .authOrNetworkRequired
        case .extensionLocalAppState: .extensionLocalAppState
        case .extensionLocalRenderState: .extensionLocalRenderState
        case .usableUI: .usableUI
        case .unknownButStop: .unknownButStop
        }
    }
}

enum ChromeMV3ControlledPopupBaselineFixtureID: String, CaseIterable, Sendable {
    case minimalStatic = "minimal-static"
    case minimalStorageLocal = "minimal-storage-local"
    case minimalRuntimeSendMessage = "minimal-runtime-sendMessage"
    case minimalRuntimeConnect = "minimal-runtime-connect"
    case minimalTabsQuery = "minimal-tabs-query"
    case minimalTabsSendMessage = "minimal-tabs-sendMessage"
    case minimalScriptingExecuteScript = "minimal-scripting-executeScript"
}

enum ChromeMV3ControlledPopupBaselineExtensionID: String, CaseIterable, Sendable {
    case bitwarden = "bitwarden"
    case raindropReference = "raindrop-reference"
    case protonPass = "proton-pass"
    case onePassword = "1password"
    case sumiUsablePopup = "sumi-usable-popup"
}

struct ChromeMV3ControlledPopupBaselineMatrixRow: Sendable {
    var rowID: String
    var layer: ChromeMV3ControlledPopupBaselineLayer
    var outcome: ChromeMV3ControlledPopupBaselineOutcome
    var ranLivePopup: Bool
    var notes: String
}

enum ChromeMV3ControlledPopupBaselineFixtureFactory {
    static let baselinePopupHTML = """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Baseline Fixture</title></head>
        <body>
        <button id="baseline-button" type="button">Baseline</button>
        <p id="baseline-status" data-outcome="pending">pending</p>
        <script src="popup.js"></script>
        </body>
        </html>
        """

    static func manifest(
        name: String,
        permissions: [String],
        hostPermissions: [String] = [],
        contentScripts: [[String: Any]]? = nil,
        backgroundServiceWorker: String? = "background.js"
    ) -> [String: Any] {
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0.0",
            "action": [
                "default_title": name,
                "default_popup": "popup.html",
            ],
        ]
        if permissions.isEmpty == false {
            manifest["permissions"] = permissions
        }
        if hostPermissions.isEmpty == false {
            manifest["host_permissions"] = hostPermissions
        }
        if let contentScripts {
            manifest["content_scripts"] = contentScripts
        }
        if let backgroundServiceWorker {
            manifest["background"] = [
                "service_worker": backgroundServiceWorker,
            ]
        }
        return manifest
    }

    static func files(
        for fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) -> [String: String] {
        switch fixtureID {
        case .minimalStatic:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      const button = document.getElementById('baseline-button');
                      button.addEventListener('click', function () {
                        status.textContent = 'clicked';
                        status.dataset.outcome = 'ok';
                      });
                      status.textContent = 'Baseline OK';
                      status.dataset.outcome = 'ok';
                    })();
                    """,
            ]
        case .minimalStorageLocal:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      chrome.storage.local.set({ baselineFixture: 'ok' }, function () {
                        chrome.storage.local.get('baselineFixture', function (items) {
                          if (items && items.baselineFixture === 'ok') {
                            status.textContent = 'Baseline OK';
                            status.dataset.outcome = 'ok';
                          } else {
                            status.textContent = 'storage-fail';
                            status.dataset.outcome = 'fail';
                          }
                        });
                      });
                    })();
                    """,
                "background.js": "chrome.runtime.onInstalled.addListener(function () {});",
            ]
        case .minimalRuntimeSendMessage:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      chrome.runtime.sendMessage({ type: 'baseline-ping' }, function (response) {
                        if (response && response.type === 'baseline-pong') {
                          status.textContent = 'Baseline OK';
                          status.dataset.outcome = 'ok';
                        } else {
                          status.textContent = 'runtime-fail';
                          status.dataset.outcome = 'fail';
                        }
                      });
                    })();
                    """,
                "background.js": """
                    chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
                      if (message && message.type === 'baseline-ping') {
                        sendResponse({ type: 'baseline-pong' });
                        return true;
                      }
                    });
                    """,
            ]
        case .minimalRuntimeConnect:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      const port = chrome.runtime.connect({ name: 'baseline-port' });
                      port.onMessage.addListener(function (message) {
                        if (message && message.type === 'baseline-pong') {
                          status.textContent = 'Baseline OK';
                          status.dataset.outcome = 'ok';
                        } else {
                          status.textContent = 'runtime-fail';
                          status.dataset.outcome = 'fail';
                        }
                      });
                      port.postMessage({ type: 'baseline-ping' });
                    })();
                    """,
                "background.js": """
                    chrome.runtime.onConnect.addListener(function (port) {
                      if (port.name !== 'baseline-port') {
                        return;
                      }
                      port.onMessage.addListener(function (message) {
                        if (message && message.type === 'baseline-ping') {
                          port.postMessage({ type: 'baseline-pong' });
                        }
                      });
                    });
                    """,
            ]
        case .minimalTabsQuery:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
                        if (Array.isArray(tabs) && tabs.length > 0 && typeof tabs[0].id === 'number') {
                          status.textContent = 'Baseline OK';
                          status.dataset.outcome = 'ok';
                        } else {
                          status.textContent = 'tabs-fail';
                          status.dataset.outcome = 'fail';
                        }
                      });
                    })();
                    """,
                "background.js": "chrome.runtime.onInstalled.addListener(function () {});",
            ]
        case .minimalTabsSendMessage:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      const complete = function (response) {
                        if (response && response.type === 'baseline-pong') {
                          status.textContent = 'Baseline OK';
                          status.dataset.outcome = 'ok';
                        } else {
                          status.textContent = 'tabs-send-fail';
                          status.dataset.outcome = 'fail';
                        }
                      };
                      const send = function () {
                        chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
                          if (!tabs || !tabs[0] || tabs[0].id == null) {
                            status.textContent = 'tabs-fail';
                            status.dataset.outcome = 'fail';
                            return;
                          }
                          chrome.tabs.sendMessage(
                            tabs[0].id,
                            { type: 'baseline-ping' },
                            complete
                          );
                        });
                      };
                      if (document.readyState === 'complete') {
                        send();
                      } else {
                        window.addEventListener('load', send, { once: true });
                      }
                    })();
                    """,
                "content.js": """
                    chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
                      if (message && message.type === 'baseline-ping') {
                        sendResponse({ type: 'baseline-pong' });
                        return true;
                      }
                    });
                    """,
                "background.js": "chrome.runtime.onInstalled.addListener(function () {});",
            ]
        case .minimalScriptingExecuteScript:
            return [
                "popup.html": baselinePopupHTML,
                "popup.js": """
                    (function () {
                      const status = document.getElementById('baseline-status');
                      chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
                        if (!tabs || !tabs[0] || tabs[0].id == null) {
                          status.textContent = 'tabs-fail';
                          status.dataset.outcome = 'fail';
                          return;
                        }
                        chrome.scripting.executeScript({
                          target: { tabId: tabs[0].id },
                          files: ['assets/baseline-executor.js'],
                        }, function (results) {
                          const value = results && results[0] ? results[0].result : null;
                          if (value === 42) {
                            status.textContent = 'Baseline OK';
                            status.dataset.outcome = 'ok';
                          } else {
                            status.textContent = 'scripting-fail';
                            status.dataset.outcome = 'fail';
                          }
                        });
                      });
                    })();
                    """,
                "assets/baseline-executor.js": "42",
                "background.js": "chrome.runtime.onInstalled.addListener(function () {});",
            ]
        }
    }

    static func manifest(
        for fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) -> [String: Any] {
        switch fixtureID {
        case .minimalStatic:
            return manifest(
                name: "Baseline Static Popup",
                permissions: ["activeTab"],
                backgroundServiceWorker: nil
            )
        case .minimalStorageLocal:
            return manifest(
                name: "Baseline Storage Popup",
                permissions: ["activeTab", "storage"]
            )
        case .minimalRuntimeSendMessage, .minimalRuntimeConnect:
            return manifest(
                name: "Baseline Runtime Popup",
                permissions: ["activeTab"]
            )
        case .minimalTabsQuery:
            return manifest(
                name: "Baseline Tabs Query Popup",
                permissions: ["activeTab", "tabs"]
            )
        case .minimalTabsSendMessage:
            return manifest(
                name: "Baseline Tabs SendMessage Popup",
                permissions: ["activeTab", "tabs"],
                hostPermissions: ["https://*/*"],
                contentScripts: [
                    [
                        "matches": ["https://*/*"],
                        "js": ["content.js"],
                        "run_at": "document_idle",
                    ],
                ]
            )
        case .minimalScriptingExecuteScript:
            return manifest(
                name: "Baseline Scripting Popup",
                permissions: ["activeTab", "scripting", "tabs"]
            )
        }
    }

    static func layer(
        for fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) -> ChromeMV3ControlledPopupBaselineLayer {
        switch fixtureID {
        case .minimalStatic:
            return .controlledPopupHost
        case .minimalStorageLocal:
            return .serviceWorkerRuntimeStorageTabsScripting
        case .minimalRuntimeSendMessage, .minimalRuntimeConnect:
            return .serviceWorkerRuntimeStorageTabsScripting
        case .minimalTabsQuery, .minimalTabsSendMessage,
            .minimalScriptingExecuteScript:
            return .serviceWorkerRuntimeStorageTabsScripting
        }
    }

    static func requiresMaterializedTab(
        _ fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) -> Bool {
        switch fixtureID {
        case .minimalTabsSendMessage, .minimalScriptingExecuteScript:
            return true
        default:
            return false
        }
    }

    static func primaryAPIFailureOutcome(
        for fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        switch fixtureID {
        case .minimalStatic:
            return .staticPopupHostFailure
        case .minimalStorageLocal:
            return .storageFailure
        case .minimalRuntimeSendMessage:
            return .runtimeSendMessageFailure
        case .minimalRuntimeConnect:
            return .runtimeConnectFailure
        case .minimalTabsQuery:
            return .tabsQueryFailure
        case .minimalTabsSendMessage:
            return .tabsSendMessageFailure
        case .minimalScriptingExecuteScript:
            return .scriptingExecuteScriptFailure
        }
    }
}

struct ChromeMV3ControlledPopupBaselineDOMProbe: Sendable {
    var outcome: String
    var hasButton: Bool
    var visibleTextLength: Int
    var controlCount: Int
    var coarseUsable: Bool
}

enum ChromeMV3ControlledPopupBaselineClassifier {
    static func classifyMinimalFixture(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID,
        opened: Bool,
        preflightBlocker: BrowserExtensionActionPopupBlocker?,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        if let preflightBlocker {
            switch preflightBlocker {
            case .moduleWorkerUnsupported:
                return .moduleWorkerUnsupported
            default:
                break
            }
        }

        guard opened else {
            if preflightBlocker == .contextUnavailable {
                return .staticPopupHostFailure
            }
            return fixturePrimaryOrHostFailure(
                fixtureID: fixtureID,
                domProbe: domProbe,
                snapshot: snapshot
            )
        }

        if let domProbe, domProbe.coarseUsable {
            return .usableUI
        }

        if let domProbe, domProbe.outcome == "fail" {
            return ChromeMV3ControlledPopupBaselineFixtureFactory
                .primaryAPIFailureOutcome(for: fixtureID)
        }

        if let snapshot {
            if let hostOutcome = classifyPopupHostBootstrapFailure(snapshot) {
                return hostOutcome
            }
            if let bridgeOutcome = classifyBridgeLayerFailure(
                fixtureID: fixtureID,
                snapshot: snapshot
            ) {
                return bridgeOutcome
            }
        }

        return fixturePrimaryOrHostFailure(
            fixtureID: fixtureID,
            domProbe: domProbe,
            snapshot: snapshot
        )
    }

    static func classifyBitwarden(
        opened: Bool,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        guard opened else { return .unknown }
        guard let snapshot else { return .unknown }
        let trace = snapshot.appStateDependencyTrace.correlationSummary
        if trace.classification == "appStateWaitWithNoWriter" {
            return .extensionLocalAppState
        }
        if trace.networkOrAuthDependencyObserved {
            return .authOrNetworkRequired
        }
        if trace.classification == "usableOnboardingOrLoginUIReached"
            || trace.popupReachedUsableOnboardingOrLoginUI
        {
            return .usableUI
        }
        return .extensionLocalAppState
    }

    static func classifyProtonPass(
        opened: Bool,
        preflightBlocker: BrowserExtensionActionPopupBlocker?,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        if let preflightBlocker {
            switch preflightBlocker {
            case .moduleWorkerUnsupported:
                return .moduleWorkerUnsupported
            default:
                break
            }
        }
        guard opened else {
            return preflightBlocker == .contextUnavailable
                ? .resourceLoadFailure
                : .unknown
        }
        if let domProbe, domProbe.coarseUsable {
            return .usableUI
        }
        if let snapshot {
            if let hostOutcome = classifyPopupHostBootstrapFailure(snapshot) {
                return hostOutcome
            }
            return ChromeMV3ControlledPopupPostResourceClassifier
                .classify(snapshot: snapshot, domProbe: domProbe)
                .baselineOutcome
        }
        return .unknownButStop
    }

    static func classifyOnePasswordPreflight(
        blocker: BrowserExtensionActionPopupBlocker?
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        blocker == .moduleWorkerUnsupported
            ? .moduleWorkerUnsupported
            : .unknown
    }

    static func classifyRealPackageUsablePopup(
        opened: Bool,
        preflightBlocker: BrowserExtensionActionPopupBlocker?,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        if let preflightBlocker {
            switch preflightBlocker {
            case .moduleWorkerUnsupported:
                return .moduleWorkerUnsupported
            default:
                break
            }
        }
        guard opened else {
            if preflightBlocker == .contextUnavailable {
                return .staticPopupHostFailure
            }
            return .unknown
        }
        if let domProbe, domProbe.coarseUsable {
            return .usableUI
        }
        if let snapshot {
            if let hostOutcome = classifyPopupHostBootstrapFailure(snapshot) {
                return hostOutcome
            }
            return ChromeMV3ControlledPopupPostResourceClassifier
                .classify(snapshot: snapshot, domProbe: domProbe)
                .baselineOutcome
        }
        return .unknownButStop
    }

    private static func fixturePrimaryOrHostFailure(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
    ) -> ChromeMV3ControlledPopupBaselineOutcome {
        if let snapshot,
           let hostOutcome = classifyPopupHostBootstrapFailure(snapshot)
        {
            return hostOutcome
        }
        if domProbe?.outcome == "fail" {
            return ChromeMV3ControlledPopupBaselineFixtureFactory
                .primaryAPIFailureOutcome(for: fixtureID)
        }
        return ChromeMV3ControlledPopupBaselineFixtureFactory
            .primaryAPIFailureOutcome(for: fixtureID)
    }

    private static func classifyPopupHostBootstrapFailure(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> ChromeMV3ControlledPopupBaselineOutcome? {
        let events = snapshot.jsDebugRouteEvents
        if events.contains(where: { $0.eventKind == "hostNavigationFailure" }) {
            return .staticPopupHostFailure
        }
        if events.contains(where: {
            $0.eventKind == "resourceLoadError"
                && ($0.apiName == "host.popupLoad"
                    || $0.apiName == "customScheme.resource")
                && ChromeMV3PopupOptionsHostResourceLoadDiagnostics
                    .isOptionalSourceMapProbeEvent($0) == false
        }) {
            return .resourceLoadFailure
        }
        if events.contains(where: { $0.eventKind == "cspViolation" }) {
            return .CSPFailure
        }
        if events.contains(where: { $0.eventKind == "scriptError" }) {
            return .popupLocalScriptFailure
        }
        if events.contains(where: {
            $0.resultClassifier == "service worker not waking"
        }) {
            return .serviceWorkerLifecycleFailure
        }
        return nil
    }

    private static func classifyBridgeLayerFailure(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> ChromeMV3ControlledPopupBaselineOutcome? {
        let routes = snapshot.sanitizedBridgeRouteRecords
        let pending = snapshot.pendingUnresolvedJSDebugRoutes

        switch fixtureID {
        case .minimalStorageLocal:
            if routes.contains(where: {
                $0.apiName.hasPrefix("storage.local")
                    && ($0.resultClassifier == "permissionDenied"
                        || $0.resultClassifier == "blocked")
            }) || pending.contains(where: { $0.apiName.hasPrefix("storage") })
            {
                return .storageFailure
            }
        case .minimalRuntimeSendMessage:
            if routes.contains(where: {
                $0.apiName == "runtime.sendMessage"
                    && ["noReceivingEnd", "noListener", "blocked", "permissionDenied"]
                        .contains($0.resultClassifier)
            }) {
                return .runtimeSendMessageFailure
            }
            if pending.contains(where: { $0.apiName == "runtime.sendMessage" }) {
                return .runtimeSendMessageFailure
            }
        case .minimalRuntimeConnect:
            if routes.contains(where: {
                $0.apiName == "runtime.connect"
                    && [
                        "Port message not delivered",
                        "Port response not delivered",
                        "blocked",
                    ].contains($0.resultClassifier ?? "")
            }) || pending.contains(where: { $0.apiName == "runtime.connect" })
            {
                return .runtimeConnectFailure
            }
        case .minimalTabsQuery:
            if routes.contains(where: {
                $0.apiName == "tabs.query"
                    && ["permissionDenied", "blocked", "noEligibleTab"]
                        .contains($0.resultClassifier)
            }) {
                return .tabsQueryFailure
            }
        case .minimalTabsSendMessage:
            if snapshot.contentScriptEndpointSummary?
                .messageListenerEndpointCount == 0
            {
                return .contentScriptAttachFailure
            }
            if routes.contains(where: {
                $0.apiName == "tabs.sendMessage"
                    && ["noReceivingEnd", "noListener", "blocked"]
                        .contains($0.resultClassifier)
            }) {
                return .tabsSendMessageFailure
            }
        case .minimalScriptingExecuteScript:
            if let record = snapshot.callRecords.last(where: {
                $0.namespace == "scripting" && $0.methodName == "executeScript"
            }), record.succeeded == false {
                return .scriptingExecuteScriptFailure
            }
        case .minimalStatic:
            if snapshot.blockedAPIs.isEmpty == false
                && snapshot.observedMethods.isEmpty
            {
                return .popupBridgeFailure
            }
        }
        return nil
    }
}

enum ChromeMV3ControlledPopupPostResourceClassifier {
    struct SanitizedSummary: Sendable {
        var blocker: ChromeMV3ControlledPopupPostResourceBlocker
        var scriptsExecuted: Bool
        var bridgeBootstrapSucceeded: Bool
        var lines: [String]
    }

    static func classify(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
    ) -> ChromeMV3ControlledPopupPostResourceBlocker {
        classifyWithSummary(snapshot: snapshot, domProbe: domProbe).blocker
    }

    static func classifyWithSummary(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
    ) -> SanitizedSummary {
        let events = postResourceEvents(in: snapshot)
        let routes = postResourceRoutes(in: snapshot)
        let pending = snapshot.pendingUnresolvedJSDebugRoutes
        let trace = snapshot.appStateDependencyTrace.correlationSummary
        let bridgeInstalled =
            snapshot.observedMethods.isEmpty == false
                || snapshot.blockedAPIs.isEmpty == false
        let scriptsExecuted =
            events.contains { $0.apiName == "runtime.getManifest" }
                && events.contains { $0.eventKind == "postBootstrapCheckpoint" }
        let lines = sanitizedLines(
            events: events,
            routes: routes,
            pending: pending,
            trace: trace,
            domProbe: domProbe,
            bridgeInstalled: bridgeInstalled,
            scriptsExecuted: scriptsExecuted
        )

        if domProbe?.coarseUsable == true
            || trace.popupReachedUsableOnboardingOrLoginUI
        {
            return SanitizedSummary(
                blocker: .usableUI,
                scriptsExecuted: scriptsExecuted,
                bridgeBootstrapSucceeded: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyScriptFailure(events) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if bridgeInstalled == false {
            return summary(
                .popupBridgeBootstrapFailure,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyMissingAPI(events, routes: routes, trace: trace) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyNativeMessaging(events, routes: routes) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyRuntimeFailure(
            events: events,
            routes: routes,
            pending: pending
        ) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyServiceWorkerFailure(events) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyStorageFailure(
            events: events,
            routes: routes,
            pending: pending,
            trace: trace
        ) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyTabsFailure(routes: routes, pending: pending) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let record = snapshot.callRecords.last(where: {
            $0.namespace == "scripting" && $0.methodName == "executeScript"
        }), record.succeeded == false {
            return summary(
                .scriptingExecuteScriptFailure,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if trace.networkOrAuthDependencyObserved {
            return summary(
                .authOrNetworkRequired,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        if let blocker = classifyExtensionLocalState(
            trace: trace,
            domProbe: domProbe,
            events: events
        ) {
            return summary(
                blocker,
                scriptsExecuted: scriptsExecuted,
                bridgeInstalled: bridgeInstalled,
                lines: lines
            )
        }

        return summary(
            .unknownButStop,
            scriptsExecuted: scriptsExecuted,
            bridgeInstalled: bridgeInstalled,
            lines: lines
        )
    }

    private static func summary(
        _ blocker: ChromeMV3ControlledPopupPostResourceBlocker,
        scriptsExecuted: Bool,
        bridgeInstalled: Bool,
        lines: [String]
    ) -> SanitizedSummary {
        SanitizedSummary(
            blocker: blocker,
            scriptsExecuted: scriptsExecuted,
            bridgeBootstrapSucceeded: bridgeInstalled,
            lines: lines
        )
    }

    private static func postResourceManifestSequence(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Int? {
        snapshot.jsDebugRouteEvents
            .filter {
                $0.apiName == "runtime.getManifest"
                    && $0.resultClassifier == "manifestReturned"
            }
            .map(\.sequence)
            .min()
    }

    private static func postResourceEvents(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsJSDebugRouteEventRecord] {
        guard let manifestSequence = postResourceManifestSequence(snapshot)
        else {
            return snapshot.jsDebugRouteEvents
        }
        return snapshot.jsDebugRouteEvents.filter {
            $0.sequence > manifestSequence
                && ChromeMV3PopupOptionsHostResourceLoadDiagnostics
                    .isOptionalSourceMapProbeEvent($0) == false
        }
    }

    private static func postResourceRoutes(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] {
        snapshot.sanitizedBridgeRouteRecords
    }

    private static func classifyScriptFailure(
        _ events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        if events.contains(where: { $0.eventKind == "scriptError" }) {
            return .popupLocalScriptFailure
        }
        if events.contains(where: {
            $0.resultClassifier == "popupContinuationException"
                || $0.resultClassifier == "crashed after script error"
        }) {
            return .popupUnhandledException
        }
        if events.contains(where: { $0.eventKind == "unhandledRejection" }) {
            return .popupUnhandledRejection
        }
        if events.contains(where: {
            $0.resultClassifier == "popupContinuationUnhandledRejection"
                || $0.resultClassifier == "Promise rejection"
        }) {
            return .popupUnhandledRejection
        }
        return nil
    }

    private static func classifyMissingAPI(
        _ events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        trace: ChromeMV3AppStateDependencyCorrelationSummary
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        if events.contains(where: { $0.eventKind == "missingAPIAccess" }) {
            return missingAPIBlocker(from: events)
        }
        if trace.missingAPIsObserved.isEmpty == false {
            return missingAPIBlocker(from: events, trace: trace)
        }
        if routes.contains(where: {
            ($0.resultClassifier ?? "").hasPrefix("missing ")
        }) {
            return missingAPIBlocker(from: events)
        }
        return nil
    }

    private static func missingAPIBlocker(
        from events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        trace: ChromeMV3AppStateDependencyCorrelationSummary? = nil
    ) -> ChromeMV3ControlledPopupPostResourceBlocker {
        let labels =
            events.compactMap(\.apiName)
            + events.compactMap(\.resultClassifier)
            + (trace?.missingAPIsObserved ?? [])
        if labels.contains(where: { $0.contains("storage.session") }) {
            return .storageSessionFailure
        }
        if labels.contains(where: { $0.contains("storage.sync") }) {
            return .storageSyncFailure
        }
        return .missingNarrowChromeAPI
    }

    private static func classifyNativeMessaging(
        _ events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord]
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        let nativeLabels = events.compactMap(\.apiName)
            + routes.map(\.apiName)
            + events.compactMap(\.resultClassifier)
        if nativeLabels.contains(where: {
            $0.contains("nativeMessaging")
                || $0.contains("connectNative")
                || $0.contains("sendNativeMessage")
        }) {
            return .nativeMessagingRequired
        }
        return nil
    }

    private static func classifyRuntimeFailure(
        events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        pending: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        if routes.contains(where: {
            $0.apiName == "runtime.sendMessage"
                && [
                    "noReceivingEnd",
                    "noListener",
                    "blocked",
                    "permissionDenied",
                ].contains($0.resultClassifier)
        }) || pending.contains(where: { $0.apiName == "runtime.sendMessage" }) {
            return .runtimeSendMessageFailure
        }
        if routes.contains(where: {
            $0.apiName == "runtime.connect"
                && [
                    "Port message not delivered",
                    "Port response not delivered",
                    "blocked",
                ].contains($0.resultClassifier ?? "")
        }) || pending.contains(where: { $0.apiName == "runtime.connect" })
            || events.contains(where: {
                [
                    "Port message not delivered",
                    "Port response not delivered",
                    "unknown pending promise",
                ].contains($0.resultClassifier ?? "")
            })
        {
            return .runtimeConnectFailure
        }
        return nil
    }

    private static func classifyServiceWorkerFailure(
        _ events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        if events.contains(where: {
            $0.resultClassifier == "service worker not waking"
        }) {
            return .serviceWorkerLifecycleFailure
        }
        return nil
    }

    private static func classifyStorageFailure(
        events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        pending: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        trace: ChromeMV3AppStateDependencyCorrelationSummary
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        if trace.writtenKeyHashesWithoutObservedOnChangedDelivery.isEmpty
            == false
        {
            return .storageOnChangedFailure
        }
        if routes.contains(where: {
            $0.apiName.hasPrefix("storage.local")
                && ["permissionDenied", "blocked"].contains($0.resultClassifier)
        }) || pending.contains(where: { $0.apiName.hasPrefix("storage.local") })
        {
            return .storageLocalFailure
        }
        if routes.contains(where: {
            $0.apiName.hasPrefix("storage.session")
                && ["permissionDenied", "blocked", "missing storage.session"]
                    .contains($0.resultClassifier)
        }) {
            return .storageSessionFailure
        }
        if routes.contains(where: {
            $0.apiName.hasPrefix("storage.sync")
                && ["permissionDenied", "blocked", "missing storage.sync"]
                    .contains($0.resultClassifier)
        }) {
            return .storageSyncFailure
        }
        if trace.classification == "appStateWaitWithSuppressedEvent" {
            return .storageOnChangedFailure
        }
        if trace.classification == "appStateWaitWithNoWriter"
            || trace.repeatedEmptyReadKeyHashes.isEmpty == false
        {
            return .storageLocalFailure
        }
        return nil
    }

    private static func classifyTabsFailure(
        routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        pending: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        if routes.contains(where: {
            $0.apiName == "tabs.query"
                && ["permissionDenied", "blocked", "noEligibleTab"]
                    .contains($0.resultClassifier)
        }) {
            return .tabsQueryFailure
        }
        if routes.contains(where: {
            $0.apiName == "tabs.sendMessage"
                && ["noReceivingEnd", "noListener", "blocked"]
                    .contains($0.resultClassifier)
        }) || pending.contains(where: { $0.apiName == "tabs.sendMessage" }) {
            return .tabsSendMessageFailure
        }
        return nil
    }

    private static func classifyExtensionLocalState(
        trace: ChromeMV3AppStateDependencyCorrelationSummary,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?,
        events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> ChromeMV3ControlledPopupPostResourceBlocker? {
        let finalCheckpoint = events.last(where: {
            $0.eventKind == "postBootstrapCheckpoint"
                && $0.diagnostics.contains("phase=final")
        })
        let coarseStatus = finalCheckpoint?.resultClassifier ?? ""
        let domBlank =
            domProbe.map {
                $0.visibleTextLength == 0 && $0.controlCount == 0
            } ?? false
        if coarseStatus == "blank"
            || coarseStatus == "spinner/loading"
            || domBlank
        {
            return .extensionLocalRenderState
        }
        if trace.classification == "appStateWaitWithNoWriter"
            || trace.classification == "appStateWaitWithNoObservableDependency"
            || trace.classification == "appStateWaitWithUnresolvedBridgeRoute"
            || trace.classification == "appStateWaitWithDelayedWriter"
            || coarseStatus == "waits on app state"
            || coarseStatus == "waits on unresolved bridge call"
        {
            return .extensionLocalAppState
        }
        return nil
    }

    private static func sanitizedLines(
        events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        routes: [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord],
        pending: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        trace: ChromeMV3AppStateDependencyCorrelationSummary,
        domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?,
        bridgeInstalled: Bool,
        scriptsExecuted: Bool
    ) -> [String] {
        var lines: [String] = [
            "scriptsExecuted=\(scriptsExecuted)",
            "bridgeBootstrapSucceeded=\(bridgeInstalled)",
            "postResourceEventCount=\(events.count)",
            "postResourceRouteCount=\(routes.count)",
            "pendingRouteCount=\(pending.count)",
            "appStateClassification=\(trace.classification)",
            "networkOrAuthDependencyObserved=\(trace.networkOrAuthDependencyObserved)",
            "missingAPIsObserved=\(trace.missingAPIsObserved.joined(separator: ","))",
            "popupReadNeverWrittenCount=\(trace.popupReadKeyHashesNeverWritten.count)",
            "storageOnChangedReachedListeners=\(trace.storageOnChangedReachedRegisteredListeners)",
        ]
        if let domProbe {
            lines.append("domOutcome=\(domProbe.outcome)")
            lines.append("domVisibleTextLength=\(domProbe.visibleTextLength)")
            lines.append("domControlCount=\(domProbe.controlCount)")
            lines.append("domCoarseUsable=\(domProbe.coarseUsable)")
        }
        for event in events.suffix(24) {
            lines.append(
                [
                    "event",
                    "kind=\(event.eventKind)",
                    "api=\(event.apiName)",
                    "target=\(event.targetContext ?? "unknown")",
                    "classifier=\(event.resultClassifier ?? "none")",
                    "firstError=\(event.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                ].joined(separator: " ")
            )
        }
        return lines
    }
}
