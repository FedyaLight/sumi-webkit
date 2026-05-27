//
//  ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift
//  Sumi
//
//  DEBUG/internal WebKit-executed synthetic JS harness for the Prompt 54
//  sidePanel/offscreen/identity compatibility layer. It creates only a hidden
//  synthetic WKWebView for tests, installs only the gated synthetic shim, and
//  never attaches to product BrowserConfiguration, product tabs, product side
//  panel UI, product offscreen runtime, identity network, or token storage.
//

import Foundation

#if DEBUG
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3SidePanelOffscreenIdentityJSScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3SidePanelOffscreenIdentityJSBridgeHandler

    init(handler: ChromeMV3SidePanelOffscreenIdentityJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        let response = handler.handle(message.body)
        return (response.foundationObject, nil)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3SidePanelOffscreenIdentityNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation:
        CheckedContinuation<Result<Void, Error>, Never>?

    func wait() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        _ = navigation
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

struct ChromeMV3SidePanelOffscreenIdentityJSSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3SidePanelOffscreenIdentityCompatibilityReport
    var webKitSyntheticJSExecutionSummary:
        ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
    var sidePanelBehaviorSummary:
        ChromeMV3SidePanelBehavior
    var offscreenLifecycleSummary:
        ChromeMV3OffscreenLifecycleSummary
    var offscreenLifecycleSummaryAfterTeardown:
        ChromeMV3OffscreenLifecycleSummary
    var handledRequestCount: Int
    var rejectedRequestCount: Int
    var userScriptCountBeforeTeardown: Int
    var userScriptCountAfterTeardown: Int
    var scriptMessageHandlerCount: Int
    var scriptMessageHandlerRemoved: Bool
    var syntheticWebViewCreated: Bool
    var sidePanelAvailableInProduct: Bool
    var offscreenAvailableInProduct: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
enum ChromeMV3SidePanelOffscreenIdentityJSSyntheticHarness {
    static var fullFixtureVerificationScript: String {
        """
        const sidePanelMethodsExecuted = [];
        const offscreenMethodsExecuted = [];
        const identityMethodsExecuted = [];
        const callbackExecutedMethodKeys = [];
        const promiseExecutedMethodKeys = [];
        const lastErrorVerifiedMethodKeys = [];
        const successLastErrorAbsent = [];
        const scopedLastErrorAbsent = [];
        const blockedMessages = [];

        function record(namespace, method, mode) {
          const key = namespace + "." + method;
          if (namespace === "sidePanel") {
            sidePanelMethodsExecuted.push(method);
          } else if (namespace === "offscreen") {
            offscreenMethodsExecuted.push(method);
          } else if (namespace === "identity") {
            identityMethodsExecuted.push(method);
          }
          if (mode === "callback") {
            callbackExecutedMethodKeys.push(key);
          } else if (mode === "promise") {
            promiseExecutedMethodKeys.push(key);
          }
        }

        function lastErrorMessage() {
          return chrome.runtime.lastError
            ? chrome.runtime.lastError.message
            : null;
        }

        await new Promise((resolve) => {
          chrome.sidePanel.setOptions(
            { tabId: 7, path: "tab.html", enabled: false },
            () => {
              record("sidePanel", "setOptions", "callback");
              successLastErrorAbsent.push(lastErrorMessage() === null);
              resolve();
            }
          );
        });
        scopedLastErrorAbsent.push(lastErrorMessage() === null);

        const options = await chrome.sidePanel.getOptions({ tabId: 7 });
        record("sidePanel", "getOptions", "promise");
        successLastErrorAbsent.push(lastErrorMessage() === null);

        await chrome.sidePanel.setPanelBehavior({
          openPanelOnActionClick: true
        });
        record("sidePanel", "setPanelBehavior", "promise");

        let openCallbackError = null;
        await new Promise((resolve) => {
          chrome.sidePanel.open({ tabId: 7 }, () => {
            record("sidePanel", "open", "callback");
            openCallbackError = lastErrorMessage();
            lastErrorVerifiedMethodKeys.push("sidePanel.open");
            resolve();
          });
        });
        scopedLastErrorAbsent.push(lastErrorMessage() === null);
        blockedMessages.push(openCallbackError);

        let openPromiseRejected = false;
        try {
          await chrome.sidePanel.open({ windowId: 1 });
        } catch (error) {
          record("sidePanel", "open", "promise");
          lastErrorVerifiedMethodKeys.push("sidePanel.open");
          openPromiseRejected = error.message.includes("product UI");
          scopedLastErrorAbsent.push(lastErrorMessage() === null);
          blockedMessages.push(error.message);
        }

        await chrome.offscreen.createDocument({
          url: "offscreen.html",
          reasons: ["TESTING"],
          justification: "fixture validation"
        });
        record("offscreen", "createDocument", "promise");

        let hasDocument = false;
        await new Promise((resolve) => {
          chrome.offscreen.hasDocument((value) => {
            record("offscreen", "hasDocument", "callback");
            hasDocument = value === true;
            successLastErrorAbsent.push(lastErrorMessage() === null);
            resolve();
          });
        });
        scopedLastErrorAbsent.push(lastErrorMessage() === null);

        await chrome.offscreen.closeDocument();
        record("offscreen", "closeDocument", "promise");

        let invalidOffscreenError = null;
        await new Promise((resolve) => {
          chrome.offscreen.createDocument(
            {
              url: "offscreen.html",
              reasons: ["NOT_A_REASON"],
              justification: "fixture validation"
            },
            () => {
              record("offscreen", "createDocument", "callback");
              invalidOffscreenError = lastErrorMessage();
              lastErrorVerifiedMethodKeys.push("offscreen.createDocument");
              resolve();
            }
          );
        });
        scopedLastErrorAbsent.push(lastErrorMessage() === null);
        blockedMessages.push(invalidOffscreenError);

        const redirectURL = chrome.identity.getRedirectURL("callback");
        record("identity", "getRedirectURL", "sync");

        const authFlowURL = await chrome.identity.launchWebAuthFlow({
          url: "https://provider.example/auth",
          interactive: true
        });
        record("identity", "launchWebAuthFlow", "promise");

        let tokenCallbackOK = false;
        await new Promise((resolve) => {
          chrome.identity.getAuthToken({ scopes: ["email"] }, (result) => {
            record("identity", "getAuthToken", "callback");
            tokenCallbackOK =
              !!result
              && typeof result.token === "string"
              && Array.isArray(result.grantedScopes)
              && result.grantedScopes.includes("email");
            successLastErrorAbsent.push(lastErrorMessage() === null);
            resolve();
          });
        });
        scopedLastErrorAbsent.push(lastErrorMessage() === null);

        await chrome.identity.clearAllCachedAuthTokens();
        record("identity", "clearAllCachedAuthTokens", "promise");

        let tokenAfterClearRejected = false;
        try {
          await chrome.identity.getAuthToken({ scopes: ["email"] });
        } catch (error) {
          record("identity", "getAuthToken", "promise");
          lastErrorVerifiedMethodKeys.push("identity.getAuthToken");
          tokenAfterClearRejected =
            error.message.includes("synthetic fixture")
            || error.message.includes("unavailable");
          scopedLastErrorAbsent.push(lastErrorMessage() === null);
          blockedMessages.push(error.message);
        }

        await new Promise((resolve) => {
          chrome.identity.removeCachedAuthToken(
            { token: "synthetic-token" },
            () => {
              record("identity", "removeCachedAuthToken", "callback");
              successLastErrorAbsent.push(lastErrorMessage() === null);
              resolve();
            }
          );
        });
        scopedLastErrorAbsent.push(lastErrorMessage() === null);

        return {
          sidePanelMethodsExecuted,
          offscreenMethodsExecuted,
          identityMethodsExecuted,
          callbackExecutedMethodKeys,
          promiseExecutedMethodKeys,
          lastErrorVerifiedMethodKeys,
          callbackModeExecuted: callbackExecutedMethodKeys.length > 0,
          promiseModeExecuted: promiseExecutedMethodKeys.length > 0,
          lastErrorScopedOK:
            successLastErrorAbsent.every(Boolean)
            && scopedLastErrorAbsent.every(Boolean),
          blockedDiagnosticsOK:
            openPromiseRejected
            && invalidOffscreenError !== null
            && tokenAfterClearRejected
            && blockedMessages.every((message) =>
              typeof message === "string" && message.length > 0
            ),
          sidePanelOptionsOK:
            options.path === "tab.html"
            && options.enabled === false
            && options.tabId === 7,
          offscreenModelOK: hasDocument === true,
          redirectURLOK:
            redirectURL
            === "https://sidepanel-offscreen-identity-extension.chromiumapp.org/callback",
          syntheticIdentityFixtureResponseUsed:
            authFlowURL
              === "https://sidepanel-offscreen-identity-extension.chromiumapp.org/callback#ok"
            && tokenCallbackOK,
          productFlagsOK:
            chrome.runtime.lastError === undefined
        };
        """
    }

    static var blockedIdentityVerificationScript: String {
        """
        const identityMethodsExecuted = [];
        const callbackExecutedMethodKeys = [];
        const promiseExecutedMethodKeys = [];
        const lastErrorVerifiedMethodKeys = [];
        function record(method, mode) {
          identityMethodsExecuted.push(method);
          if (mode === "callback") {
            callbackExecutedMethodKeys.push("identity." + method);
          } else if (mode === "promise") {
            promiseExecutedMethodKeys.push("identity." + method);
          }
        }
        function lastErrorMessage() {
          return chrome.runtime.lastError
            ? chrome.runtime.lastError.message
            : null;
        }

        const redirectURL = chrome.identity.getRedirectURL("callback");
        record("getRedirectURL", "sync");

        let authFlowCallbackError = null;
        await new Promise((resolve) => {
          chrome.identity.launchWebAuthFlow(
            { url: "https://provider.example/auth", interactive: true },
            () => {
              record("launchWebAuthFlow", "callback");
              authFlowCallbackError = lastErrorMessage();
              lastErrorVerifiedMethodKeys.push("identity.launchWebAuthFlow");
              resolve();
            }
          );
        });
        const authFlowLastErrorCleared = lastErrorMessage() === null;

        let tokenPromiseRejected = false;
        try {
          await chrome.identity.getAuthToken({ scopes: ["email"] });
        } catch (error) {
          record("getAuthToken", "promise");
          lastErrorVerifiedMethodKeys.push("identity.getAuthToken");
          tokenPromiseRejected =
            error.message.includes("synthetic fixture")
            || error.message.includes("unavailable");
        }

        return {
          identityMethodsExecuted,
          callbackExecutedMethodKeys,
          promiseExecutedMethodKeys,
          lastErrorVerifiedMethodKeys,
          callbackModeExecuted: callbackExecutedMethodKeys.length > 0,
          promiseModeExecuted: promiseExecutedMethodKeys.length > 0,
          lastErrorScopedOK:
            authFlowCallbackError !== null
            && authFlowLastErrorCleared
            && chrome.runtime.lastError === undefined,
          blockedDiagnosticsOK:
            tokenPromiseRejected
            && typeof authFlowCallbackError === "string"
            && authFlowCallbackError.length > 0,
          redirectURLOK:
            redirectURL
            === "https://sidepanel-offscreen-identity-extension.chromiumapp.org/callback",
          syntheticIdentityFixtureResponseUsed: false
        };
        """
    }

    static var removeCachedTokenVerificationScript: String {
        """
        const identityMethodsExecuted = [];
        const callbackExecutedMethodKeys = [];
        const promiseExecutedMethodKeys = [];
        const lastErrorVerifiedMethodKeys = [];
        function record(method, mode) {
          identityMethodsExecuted.push(method);
          if (mode === "callback") {
            callbackExecutedMethodKeys.push("identity." + method);
          } else if (mode === "promise") {
            promiseExecutedMethodKeys.push("identity." + method);
          }
        }

        const tokenResult = await chrome.identity.getAuthToken({
          scopes: ["email"]
        });
        record("getAuthToken", "promise");

        await new Promise((resolve) => {
          chrome.identity.removeCachedAuthToken(
            { token: "synthetic-token" },
            () => {
              record("removeCachedAuthToken", "callback");
              resolve();
            }
          );
        });

        let rejectedAfterRemove = false;
        try {
          await chrome.identity.getAuthToken({ scopes: ["email"] });
        } catch (error) {
          record("getAuthToken", "promise");
          lastErrorVerifiedMethodKeys.push("identity.getAuthToken");
          rejectedAfterRemove =
            error.message.includes("synthetic fixture")
            || error.message.includes("unavailable");
        }

        return {
          identityMethodsExecuted,
          callbackExecutedMethodKeys,
          promiseExecutedMethodKeys,
          lastErrorVerifiedMethodKeys,
          callbackModeExecuted: callbackExecutedMethodKeys.length > 0,
          promiseModeExecuted: promiseExecutedMethodKeys.length > 0,
          lastErrorScopedOK: chrome.runtime.lastError === undefined,
          blockedDiagnosticsOK: rejectedAfterRemove,
          removeCachedAuthTokenClearedSyntheticCache:
            tokenResult
            && typeof tokenResult.token === "string"
            && rejectedAfterRemove,
          syntheticIdentityFixtureResponseUsed:
            tokenResult && typeof tokenResult.token === "string"
        };
        """
    }

    @MainActor
    static func run(
        scriptBody: String,
        configuration:
            ChromeMV3SidePanelOffscreenIdentityConfiguration =
            .syntheticHarness(),
        manifest: ChromeMV3Manifest? = nil,
        generatedBundleRootURL rootURL: URL? = nil,
        html: String =
            "<!doctype html><meta charset='utf-8'><title>sidePanel/offscreen/identity JS</title>"
    ) async -> ChromeMV3SidePanelOffscreenIdentityJSSyntheticHarnessResult {
        let rootURL = (
            rootURL
                ?? configuration.generatedBundleRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                }
                ?? FileManager.default.temporaryDirectory
        ).standardizedFileURL
        let skippedDiagnostics = [
            "Synthetic WebKit harness did not create a WKWebView because the module or explicit internal bridge gate is disabled.",
            "No product BrowserConfiguration, normal tab, sidePanel UI, offscreen runtime, or identity network was touched.",
        ]
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalCompatibilityBridgeAllowed
        else {
            let report =
                ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
                .makeReport(
                    manifest: manifest,
                    generatedBundleRootURL: rootURL,
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    moduleState: configuration.moduleState,
                    syntheticIdentityFixture:
                        configuration.syntheticIdentityFixture,
                    webKitSyntheticJSExecutionSummary: .notRun
                )
            let owner =
                ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner(
                    configuration: configuration
                )
            return ChromeMV3SidePanelOffscreenIdentityJSSyntheticHarnessResult(
                scriptEvaluationSucceeded: false,
                scriptResultJSON: nil,
                report: report,
                webKitSyntheticJSExecutionSummary: .notRun,
                sidePanelBehaviorSummary: owner.sidePanelBehaviorSummary,
                offscreenLifecycleSummary: owner.offscreenLifecycleSummary,
                offscreenLifecycleSummaryAfterTeardown:
                    owner.offscreenLifecycleSummary,
                handledRequestCount: 0,
                rejectedRequestCount: 0,
                userScriptCountBeforeTeardown: 0,
                userScriptCountAfterTeardown: 0,
                scriptMessageHandlerCount: 0,
                scriptMessageHandlerRemoved: true,
                syntheticWebViewCreated: false,
                sidePanelAvailableInProduct: false,
                offscreenAvailableInProduct: false,
                identityAvailableInProduct: false,
                identityExternalAuthNetworkAllowed: false,
                normalTabRuntimeBridgeAvailable: false,
                runtimeLoadable: false,
                productRuntimeExposed: false,
                diagnostics: skippedDiagnostics
            )
        }

        let bridgeHandler = ChromeMV3SidePanelOffscreenIdentityJSBridgeHandler(
            configuration: configuration
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let scriptHandler =
            ChromeMV3SidePanelOffscreenIdentityJSScriptMessageHandler(
                handler: bridgeHandler
            )
        webViewConfiguration.userContentController.addScriptMessageHandler(
            scriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3SidePanelOffscreenIdentityJSShimSource
                .bridgeMessageHandlerName
        )
        let userScript = WKUserScript(
            source:
                ChromeMV3SidePanelOffscreenIdentityJSShimSource.source(
                    configuration: configuration
                ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webViewConfiguration.userContentController.addUserScript(userScript)

        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3SidePanelOffscreenIdentityNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics = [
            "Synthetic WKWebView is hidden and is not registered as a product tab.",
            "sidePanel/offscreen/identity shim is installed as a WKUserScript only on this controlled synthetic harness configuration.",
            "sidePanel/offscreen/identity bridge handler is installed only on the synthetic harness WKUserContentController.",
        ]
        if case .failure(let error) = navigationResult {
            diagnostics.append(error.localizedDescription)
        }

        var scriptSucceeded = false
        var resultJSON: String?
        if case .success = navigationResult {
            do {
                let result = try await webView.callAsyncJavaScript(
                    scriptBody,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                resultJSON =
                    ChromeMV3SidePanelOffscreenIdentityJSSyntheticHarness
                    .canonicalJSON(from: result ?? NSNull())
                scriptSucceeded = resultJSON != nil
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }

        let webKitSummary =
            ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
            .fromWebKitScriptResult(
                json: resultJSON,
                scriptEvaluationSucceeded: scriptSucceeded,
                responses: bridgeHandler.handledResponses,
                syntheticIdentityFixture:
                    configuration.syntheticIdentityFixture,
                diagnostics: diagnostics
            )
        let report =
            ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(
                manifest: manifest,
                generatedBundleRootURL: rootURL,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                moduleState: configuration.moduleState,
                syntheticIdentityFixture:
                    configuration.syntheticIdentityFixture,
                webKitSyntheticJSExecutionSummary: webKitSummary
            )
        let behaviorSummary =
            bridgeHandler.runtimeStateOwner.sidePanelBehaviorSummary
        let lifecycleSummary =
            bridgeHandler.runtimeStateOwner.offscreenLifecycleSummary
        let handledRequestCount = bridgeHandler.handledRequestCount
        let rejectedRequestCount = bridgeHandler.rejectedRequestCount
        let userScriptCountBeforeTeardown =
            webViewConfiguration.userContentController.userScripts.count

        webView.navigationDelegate = nil
        webViewConfiguration.userContentController
            .removeScriptMessageHandler(
                forName:
                    ChromeMV3SidePanelOffscreenIdentityJSShimSource
                    .bridgeMessageHandlerName,
                contentWorld: .page
            )
        webViewConfiguration.userContentController.removeAllUserScripts()
        _ = bridgeHandler.tearDown()
        let lifecycleSummaryAfterTeardown =
            bridgeHandler.runtimeStateOwner.offscreenLifecycleSummary
        let userScriptCountAfterTeardown =
            webViewConfiguration.userContentController.userScripts.count

        return ChromeMV3SidePanelOffscreenIdentityJSSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            webKitSyntheticJSExecutionSummary: webKitSummary,
            sidePanelBehaviorSummary: behaviorSummary,
            offscreenLifecycleSummary: lifecycleSummary,
            offscreenLifecycleSummaryAfterTeardown:
                lifecycleSummaryAfterTeardown,
            handledRequestCount: handledRequestCount,
            rejectedRequestCount: rejectedRequestCount,
            userScriptCountBeforeTeardown: userScriptCountBeforeTeardown,
            userScriptCountAfterTeardown: userScriptCountAfterTeardown,
            scriptMessageHandlerCount: 1,
            scriptMessageHandlerRemoved: true,
            syntheticWebViewCreated: true,
            sidePanelAvailableInProduct: false,
            offscreenAvailableInProduct: false,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            diagnostics: uniqueSortedSOIHarness(
                diagnostics + webKitSummary.diagnostics
            )
        )
    }

    private static func canonicalJSON(from value: Any) -> String? {
        ChromeMV3StorageValue(sidePanelOffscreenIdentityHarnessValue: value)
            .flatMap { try? $0.canonicalJSONString() }
    }
}

private extension ChromeMV3StorageValue {
    init?(sidePanelOffscreenIdentityHarnessValue value: Any) {
        if value is NSNull {
            self = .null
            return
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                let double = number.doubleValue
                guard double.isFinite else { return nil }
                self = .number(double)
            }
            return
        }
        if let string = value as? String {
            self = .string(string)
            return
        }
        if let array = value as? [Any] {
            var values: [ChromeMV3StorageValue] = []
            for item in array {
                guard let value = ChromeMV3StorageValue(
                    sidePanelOffscreenIdentityHarnessValue: item
                ) else {
                    return nil
                }
                values.append(value)
            }
            self = .array(values)
            return
        }
        if let object = value as? [String: Any] {
            var values: [String: ChromeMV3StorageValue] = [:]
            for (key, item) in object {
                guard let value = ChromeMV3StorageValue(
                    sidePanelOffscreenIdentityHarnessValue: item
                ) else {
                    return nil
                }
                values[key] = value
            }
            self = .object(values)
            return
        }
        return nil
    }
}

private func uniqueSortedSOIHarness<T: Hashable & Comparable>(
    _ values: [T]
) -> [T] {
    Array(Set(values)).sorted()
}
#endif
