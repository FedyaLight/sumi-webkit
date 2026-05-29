//
//  ChromeMV3PasswordManagerSyntheticFixture.swift
//  Sumi
//
//  DEBUG/internal password-manager-class Chrome MV3 synthetic fixture suite.
//  This is not product password-manager support, not product normal-tab
//  runtime support, not product native messaging, and not service-worker
//  lifecycle support.
//

import CryptoKit
import Foundation

enum ChromeMV3PasswordManagerFixtureVariant:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case activeTab
    case basic
    case contentScriptEndpoint
    case hostPermissions
    case nativeMessagingRequired
    case optionalPermissions
    case serviceWorkerRequired
    case storageLocal

    static func < (
        lhs: ChromeMV3PasswordManagerFixtureVariant,
        rhs: ChromeMV3PasswordManagerFixtureVariant
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerReadinessClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case deferred
    case partial
    case ready
    case unsupported

    static func < (
        lhs: ChromeMV3PasswordManagerReadinessClassification,
        rhs: ChromeMV3PasswordManagerReadinessClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerFixtureManifestFacts:
    Codable,
    Equatable,
    Sendable
{
    var manifestVersion: Int
    var actionDefaultPopup: String?
    var permissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var contentScriptMatches: [String]
    var contentScriptJS: [String]
    var backgroundServiceWorker: String?
    var nativeHostName: String?
}

struct ChromeMV3PasswordManagerFixtureManifest:
    Codable,
    Equatable,
    Sendable
{
    var variant: ChromeMV3PasswordManagerFixtureVariant
    var extensionID: String
    var name: String
    var version: String
    var facts: ChromeMV3PasswordManagerFixtureManifestFacts
    var requiredAPISurface: [String]
    var hostPermissionRequirements: [String]
    var storageRequirements: [String]
    var runtimeMessagingRequirements: [String]
    var nativeMessagingRequired: Bool
    var serviceWorkerRequired: Bool
    var expectedReadinessClassification:
        ChromeMV3PasswordManagerReadinessClassification
    var diagnostics: [String]

    var manifestValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "manifest_version": .number(Double(facts.manifestVersion)),
            "name": .string(name),
            "version": .string(version),
        ]
        if facts.permissions.isEmpty == false {
            object["permissions"] = .array(
                facts.permissions.map(ChromeMV3StorageValue.string)
            )
        }
        if facts.optionalPermissions.isEmpty == false {
            object["optional_permissions"] = .array(
                facts.optionalPermissions.map(ChromeMV3StorageValue.string)
            )
        }
        if facts.hostPermissions.isEmpty == false {
            object["host_permissions"] = .array(
                facts.hostPermissions.map(ChromeMV3StorageValue.string)
            )
        }
        if facts.optionalHostPermissions.isEmpty == false {
            object["optional_host_permissions"] = .array(
                facts.optionalHostPermissions.map(ChromeMV3StorageValue.string)
            )
        }
        if let popup = facts.actionDefaultPopup {
            object["action"] = .object([
                "default_popup": .string(popup),
            ])
        }
        if facts.contentScriptMatches.isEmpty == false {
            object["content_scripts"] = .array([
                .object([
                    "matches": .array(
                        facts.contentScriptMatches
                            .map(ChromeMV3StorageValue.string)
                    ),
                    "js": .array(
                        facts.contentScriptJS
                            .map(ChromeMV3StorageValue.string)
                    ),
                ]),
            ])
        }
        if let worker = facts.backgroundServiceWorker {
            object["background"] = .object([
                "service_worker": .string(worker),
            ])
        }
        return .object(object)
    }
}

enum ChromeMV3PasswordManagerFixtureManifestCatalog {
    static func all(
        extensionID: String = "password-manager-synthetic-extension"
    ) -> [ChromeMV3PasswordManagerFixtureManifest] {
        ChromeMV3PasswordManagerFixtureVariant.allCases.sorted().map {
            fixture(variant: $0, extensionID: extensionID)
        }
    }

    static func fixture(
        variant: ChromeMV3PasswordManagerFixtureVariant,
        extensionID: String = "password-manager-synthetic-extension"
    ) -> ChromeMV3PasswordManagerFixtureManifest {
        let basePermissions = ["activeTab", "scripting", "storage"]
        let baseFacts = ChromeMV3PasswordManagerFixtureManifestFacts(
            manifestVersion: 3,
            actionDefaultPopup: "popup.html",
            permissions: basePermissions,
            optionalPermissions: [],
            hostPermissions: [],
            optionalHostPermissions: ["https://example.com/*"],
            contentScriptMatches: ["https://example.com/*"],
            contentScriptJS: ["content-script.js"],
            backgroundServiceWorker: nil,
            nativeHostName: nil
        )
        var facts = baseFacts
        var required = [
            "chrome.runtime.sendMessage",
            "chrome.runtime.connect",
            "chrome.tabs.query",
            "chrome.tabs.sendMessage",
            "chrome.tabs.connect",
            "chrome.scripting.executeScript",
            "chrome.permissions",
            "chrome.storage.local",
            "chrome.storage.onChanged",
        ]
        var hostRequirements: [String] = []
        var storage = ["local credential-like JSON records"]
        var runtime = [
            "popup to runtime message",
            "popup to content endpoint message",
            "model Port preflight",
        ]
        var nativeRequired = false
        var workerRequired = false
        var readiness: ChromeMV3PasswordManagerReadinessClassification =
            .ready
        var diagnostics = [
            "Fixture uses synthetic password-manager-like resources only.",
            "No real extension code, credentials, assets, or branding are imported.",
            "Product runtime exposure remains unavailable.",
        ]

        switch variant {
        case .basic:
            break
        case .nativeMessagingRequired:
            facts.permissions = (basePermissions + ["nativeMessaging"]).sorted()
            facts.nativeHostName = "com.sumi.synthetic_password_manager"
            nativeRequired = true
            readiness = .partial
            diagnostics.append(
                "nativeMessaging is internally fixture-testable but remains blocked for product."
            )
        case .hostPermissions:
            facts.hostPermissions = ["https://example.com/*"]
            facts.optionalHostPermissions = []
            hostRequirements = ["persistent host access for example.com"]
        case .activeTab:
            facts.hostPermissions = []
            facts.optionalHostPermissions = []
            hostRequirements = ["temporary activeTab grant for example.com"]
        case .storageLocal:
            facts.permissions = (basePermissions + ["unlimitedStorage"])
                .sorted()
            storage.append("getBytesInUse quota diagnostics")
        case .actionPopup:
            facts.actionDefaultPopup = "popup.html"
            runtime.append("action popup surface")
        case .contentScriptEndpoint:
            facts.contentScriptMatches = ["https://example.com/*"]
            facts.contentScriptJS = ["content-script.js"]
            runtime.append("synthetic login page content endpoint")
        case .optionalPermissions:
            facts.optionalPermissions = ["tabs"]
            facts.optionalHostPermissions = ["https://example.com/*"]
            hostRequirements = ["modeled optional host request"]
        case .serviceWorkerRequired:
            facts.backgroundServiceWorker = "service-worker.js"
            workerRequired = true
            readiness = .partial
            diagnostics.append(
                "Service-worker wake/keepalive is internally fixture-testable and remains blocked for product."
            )
        }

        if facts.hostPermissions.isEmpty == false {
            hostRequirements.append(contentsOf: facts.hostPermissions)
        }
        if facts.optionalHostPermissions.isEmpty == false {
            hostRequirements.append(contentsOf: facts.optionalHostPermissions)
        }
        if nativeRequired {
            required.append("chrome.runtime native messaging methods")
        }
        if workerRequired {
            required.append("extension service-worker wake/keepalive")
        }

        return ChromeMV3PasswordManagerFixtureManifest(
            variant: variant,
            extensionID: extensionID,
            name:
                "Sumi Synthetic Password Manager \(variant.rawValue)",
            version: "0.0.1",
            facts: facts,
            requiredAPISurface: uniqueSortedPasswordManager(required),
            hostPermissionRequirements:
                uniqueSortedPasswordManager(hostRequirements),
            storageRequirements: uniqueSortedPasswordManager(storage),
            runtimeMessagingRequirements:
                uniqueSortedPasswordManager(runtime),
            nativeMessagingRequired: nativeRequired,
            serviceWorkerRequired: workerRequired,
            expectedReadinessClassification: readiness,
            diagnostics: uniqueSortedPasswordManager(diagnostics)
        )
    }
}

struct ChromeMV3PasswordManagerLoginFieldFixture:
    Codable,
    Equatable,
    Sendable
{
    var fieldID: String
    var name: String
    var selector: String
    var type: String
    var autocomplete: String
    var label: String
}

struct ChromeMV3PasswordManagerLoginPageFixture:
    Codable,
    Equatable,
    Sendable
{
    var fixtureID: String
    var url: String
    var origin: String
    var usernameField: ChromeMV3PasswordManagerLoginFieldFixture
    var passwordField: ChromeMV3PasswordManagerLoginFieldFixture
    var submitButtonSelector: String
    var iframePresent: Bool
    var detectedFieldMetadata: ChromeMV3StorageValue
    var fillCommandPayload: ChromeMV3StorageValue
    var fillResultPayload: ChromeMV3StorageValue
    var blockedUnsupportedCases: [String]
    var diagnostics: [String]

    static var exampleLogin: ChromeMV3PasswordManagerLoginPageFixture {
        let username = ChromeMV3PasswordManagerLoginFieldFixture(
            fieldID: "username",
            name: "username",
            selector: "#username",
            type: "email",
            autocomplete: "username",
            label: "Email"
        )
        let password = ChromeMV3PasswordManagerLoginFieldFixture(
            fieldID: "password",
            name: "password",
            selector: "#password",
            type: "password",
            autocomplete: "current-password",
            label: "Password"
        )
        return ChromeMV3PasswordManagerLoginPageFixture(
            fixtureID: "synthetic-example-login",
            url: "https://example.com/login",
            origin: "https://example.com",
            usernameField: username,
            passwordField: password,
            submitButtonSelector: "#submit-login",
            iframePresent: false,
            detectedFieldMetadata: .object([
                "formId": .string("synthetic-login-form"),
                "password": fieldValue(password),
                "submit": .object([
                    "selector": .string("#submit-login"),
                    "type": .string("submit"),
                ]),
                "username": fieldValue(username),
            ]),
            fillCommandPayload: .object([
                "credential": .object([
                    "passwordRef": .string("synthetic-password-token"),
                    "username": .string("fixture.user@example.test"),
                ]),
                "type": .string("fillFields"),
            ]),
            fillResultPayload: .object([
                "fieldsFilled": .array([
                    .string("username"),
                    .string("password"),
                ]),
                "formId": .string("synthetic-login-form"),
                "submitted": .bool(false),
                "success": .bool(true),
            ]),
            blockedUnsupportedCases: [
                "cross-origin iframe fill is not modeled",
                "submit is not triggered",
                "real credential storage is not used",
            ],
            diagnostics: [
                "Login page fixture is synthetic and deterministic.",
                "No product normal tab is attached.",
            ]
        )
    }

    private static func fieldValue(
        _ field: ChromeMV3PasswordManagerLoginFieldFixture
    ) -> ChromeMV3StorageValue {
        .object([
            "autocomplete": .string(field.autocomplete),
            "fieldId": .string(field.fieldID),
            "label": .string(field.label),
            "name": .string(field.name),
            "selector": .string(field.selector),
            "type": .string(field.type),
        ])
    }
}

struct ChromeMV3PasswordManagerCombinedHarnessConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var surfaceID: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalCombinedHarnessAllowed: Bool
    var passwordManagerSyntheticJSReady: Bool
    var passwordManagerNativeMessagingReady: Bool
    var passwordManagerServiceWorkerReady: Bool
    var passwordManagerSharedLifecycleReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    static func syntheticHarness(
        extensionID: String = "password-manager-synthetic-extension",
        profileID: String = "password-manager-synthetic-profile",
        surfaceID: String = "password-manager-synthetic-popup",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalCombinedHarnessAllowed: Bool = true
    ) -> ChromeMV3PasswordManagerCombinedHarnessConfiguration {
        let enabled =
            moduleState == .enabled && explicitInternalCombinedHarnessAllowed
        return ChromeMV3PasswordManagerCombinedHarnessConfiguration(
            extensionID:
                normalizedPasswordManager(
                    extensionID,
                    fallback: "password-manager-synthetic-extension"
                ),
            profileID:
                normalizedPasswordManager(
                    profileID,
                    fallback: "password-manager-synthetic-profile"
                ),
            surfaceID:
                normalizedPasswordManager(
                    surfaceID,
                    fallback: "password-manager-synthetic-popup"
                ),
            moduleState: moduleState,
            explicitInternalCombinedHarnessAllowed:
                explicitInternalCombinedHarnessAllowed,
            passwordManagerSyntheticJSReady: enabled,
            passwordManagerNativeMessagingReady: false,
            passwordManagerServiceWorkerReady: false,
            passwordManagerSharedLifecycleReadyInFixture: false,
            passwordManagerProductRuntimeReady: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Combined password-manager fixture harness is DEBUG/internal and synthetic-surface scoped.",
                "Product normal-tab runtime bridge remains unavailable.",
                "runtimeLoadable remains false.",
            ]
        )
    }

    var runtimeConfiguration: ChromeMV3RuntimeJSBridgeConfiguration {
        .syntheticHarness(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: surfaceID,
            surfaceKind: .actionPopup,
            extensionBaseURLString:
                "chrome-extension://\(extensionID)/",
            moduleState: moduleState,
            explicitInternalRuntimeJSBridgeAllowed:
                explicitInternalCombinedHarnessAllowed
        )
    }

    var tabsConfiguration:
        ChromeMV3TabsScriptingJSBridgeConfiguration
    {
        .syntheticHarness(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: surfaceID,
            surfaceKind: .actionPopup,
            extensionBaseURLString:
                "chrome-extension://\(extensionID)/",
            moduleState: moduleState,
            explicitInternalTabsScriptingJSBridgeAllowed:
                explicitInternalCombinedHarnessAllowed
        )
    }

    var storageConfiguration:
        ChromeMV3StorageLocalRuntimeConfiguration
    {
        .syntheticHarness(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: surfaceID,
            surfaceKind: .actionPopup,
            extensionBaseURLString:
                "chrome-extension://\(extensionID)/",
            moduleState: moduleState,
            explicitInternalStorageJSBridgeAllowed:
                explicitInternalCombinedHarnessAllowed
        )
    }
}

struct ChromeMV3PasswordManagerCombinedShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var runtimeMethods: [String]
    var runtimeEvents: [String]
    var tabsMethods: [String]
    var scriptingMethods: [String]
    var permissionsMethods: [String]
    var permissionsEvents: [String]
    var storageAreas: [String]
    var storageLocalMethods: [String]
    var storageEvents: [String]
    var internalFixtureControls: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var unsupportedChromeNamespaces: [String]
}

enum ChromeMV3PasswordManagerCombinedJSShimSource {
    static let runtimeBridgeMessageHandlerName =
        ChromeMV3RuntimeJSShimSource.bridgeMessageHandlerName
    static let tabsScriptingBridgeMessageHandlerName =
        ChromeMV3TabsScriptingJSShimSource.bridgeMessageHandlerName
    static let storageBridgeMessageHandlerName =
        ChromeMV3StorageLocalJSShimSource.bridgeMessageHandlerName
    static let fixtureBridgeMessageHandlerName =
        "sumiChromeMV3PasswordManagerFixture"

    static var coverage: ChromeMV3PasswordManagerCombinedShimCoverage {
        ChromeMV3PasswordManagerCombinedShimCoverage(
            exposedChromeNamespaces: [
                "permissions",
                "runtime",
                "scripting",
                "storage",
                "tabs",
            ],
            runtimeMethods: ["connect", "getURL", "sendMessage"],
            runtimeEvents: ["onConnect", "onMessage"],
            tabsMethods: ["connect", "query", "sendMessage"],
            scriptingMethods: ["executeScript"],
            permissionsMethods: ["contains", "getAll", "remove", "request"],
            permissionsEvents: ["onAdded", "onRemoved"],
            storageAreas: ["local"],
            storageLocalMethods: [
                "clear",
                "get",
                "getBytesInUse",
                "remove",
                "set",
            ],
            storageEvents: ["onChanged"],
            internalFixtureControls: [
                "expireActiveTabForNavigation",
                "grantActiveTab",
                "reset",
                "snapshot",
            ],
            callbackModeSupported: true,
            promiseModeSupported: true,
            lastErrorScopedToCallbackTurn: true,
            unsupportedChromeNamespaces: [
                "bookmarks",
                "history",
                "nativeMessaging",
                "storage.sync",
            ]
        )
    }

    static func source(
        configuration:
            ChromeMV3PasswordManagerCombinedHarnessConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "runtimeBridgeName": runtimeBridgeMessageHandlerName,
            "tabsBridgeName": tabsScriptingBridgeMessageHandlerName,
            "storageBridgeName": storageBridgeMessageHandlerName,
            "fixtureBridgeName": fixtureBridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const chromeObject = {};
          const runtime = {};
          const permissions = {};
          const tabs = {};
          const scripting = {};
          const storage = {};
          const local = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;
          let nextPortNumber = 0;
          let nextListenerNumber = 0;
          const runtimeListeners = [];
          const runtimeListenerIDs = new Map();
          const onConnectListeners = [];
          const portState = new WeakMap();

          function handlerNamed(name) {
            return globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[name];
          }

          function bridgeUnavailableResponse(namespace, methodName) {
            return {
              bridgeCallID: "password-manager-combined-unavailable",
              namespace,
              methodName,
              succeeded: false,
              resultPayload: null,
              lastErrorMessage: "Combined password-manager synthetic bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["Combined password-manager synthetic bridge handler is unavailable."]
            };
          }

          function bridgeNameFor(namespace) {
            if (namespace === "runtime") {
              return config.runtimeBridgeName;
            }
            if (namespace === "storage") {
              return config.storageBridgeName;
            }
            if (namespace === "fixture") {
              return config.fixtureBridgeName;
            }
            return config.tabsBridgeName;
          }

          function bridgePost(namespace, methodName, invocationMode, args, extra) {
            const handler = handlerNamed(bridgeNameFor(namespace));
            if (!handler || typeof handler.postMessage !== "function") {
              return Promise.resolve(bridgeUnavailableResponse(namespace, methodName));
            }
            nextBridgeCallNumber += 1;
            const body = Object.assign({
              namespace,
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: "actionPopup",
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "password-manager-combined",
                config.surfaceID,
                namespace,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            }, extra || {});
            return handler.postMessage(body);
          }

          function toJSONCompatible(value) {
            if (value === undefined) {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function invokeCallback(callback, message, args) {
            lastErrorValue = message ? { message } : undefined;
            try {
              callback.apply(undefined, args || []);
            } finally {
              lastErrorValue = undefined;
            }
          }

          function rejectFromResponse(response, fallback) {
            return Promise.reject(
              new Error(response.lastErrorMessage || fallback)
            );
          }

          function makeEvent() {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              hasListeners() {
                return listeners.length > 0;
              },
              dispatch() {
                const args = Array.prototype.slice.call(arguments);
                listeners.slice().forEach((listener) => listener.apply(undefined, args));
              }
            });
          }

          const storageOnChanged = makeEvent();
          const permissionsOnAdded = makeEvent();
          const permissionsOnRemoved = makeEvent();

          function dispatchStorageEvent(response) {
            const payload = response && response.onChangedPayload;
            if (!payload || payload.areaName !== "local" || !Array.isArray(payload.changes)) {
              return;
            }
            const changes = {};
            payload.changes.forEach((entry) => {
              if (!entry || typeof entry.key !== "string") {
                return;
              }
              const change = {};
              if (Object.prototype.hasOwnProperty.call(entry, "oldValue")) {
                change.oldValue = entry.oldValue;
              }
              if (Object.prototype.hasOwnProperty.call(entry, "newValue")) {
                change.newValue = entry.newValue;
              }
              changes[entry.key] = change;
            });
            if (Object.keys(changes).length > 0) {
              storageOnChanged.dispatch(changes, "local");
            }
          }

          function dispatchPermissionEvent(response) {
            const payload = response && response.permissionEventPayload;
            if (!payload || typeof payload !== "object") {
              return;
            }
            const eventPayload = {
              permissions: Array.isArray(payload.permissions)
                ? payload.permissions.slice().sort()
                : [],
              origins: Array.isArray(payload.origins)
                ? payload.origins.slice().sort()
                : []
            };
            if (payload.eventKind === "onAdded") {
              permissionsOnAdded.dispatch(eventPayload);
            }
            if (payload.eventKind === "onRemoved") {
              permissionsOnRemoved.dispatch(eventPayload);
            }
          }

          function callbackOrPromise(namespace, methodName, args, callback, options) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = (args || []).map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 synthetic bridge arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = bridgePost(namespace, methodName, mode, bridgeArgs)
              .then((response) => {
                if (response.succeeded) {
                  dispatchStorageEvent(response);
                  dispatchPermissionEvent(response);
                }
                return response;
              });
            if (callback) {
              promise.then((response) => {
                if (response.succeeded) {
                  invokeCallback(callback, null, [
                    options && options.callbackValue
                      ? options.callbackValue(response)
                      : response.resultPayload
                  ].filter((value) => value !== undefined));
                } else {
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return options && options.promiseValue
                  ? options.promiseValue(response)
                  : response.resultPayload;
              }
              return rejectFromResponse(
                response,
                namespace + "." + methodName + " failed."
              );
            });
          }

          function optionalKeysAndCallback(first, second) {
            if (typeof first === "function") {
              return { keys: undefined, callback: first };
            }
            return {
              keys: first,
              callback: typeof second === "function" ? second : null
            };
          }

          function makePortEvent() {
            return makeEvent();
          }

          function createPort(name, namespace) {
            const port = {};
            const state = {
              id: null,
              disconnected: false,
              onMessage: makePortEvent(),
              onDisconnect: makePortEvent()
            };
            Object.defineProperty(port, "name", {
              value: name || "",
              enumerable: true
            });
            Object.defineProperty(port, "onMessage", {
              value: state.onMessage,
              enumerable: true
            });
            Object.defineProperty(port, "onDisconnect", {
              value: state.onDisconnect,
              enumerable: true
            });
            Object.defineProperty(port, "postMessage", {
              value(message) {
                if (state.disconnected) {
                  throw new Error("Attempting to use a disconnected port object");
                }
                bridgePost(namespace, "Port.postMessage", "fireAndForget", [toJSONCompatible(message)], {
                  portID: state.id
                }).catch(() => undefined);
              },
              enumerable: true
            });
            Object.defineProperty(port, "disconnect", {
              value() {
                if (state.disconnected) {
                  return;
                }
                state.disconnected = true;
                bridgePost(namespace, "Port.disconnect", "fireAndForget", [], {
                  portID: state.id
                }).catch(() => undefined);
                state.onDisconnect.dispatch(port);
              },
              enumerable: true
            });
            portState.set(port, state);
            return port;
          }

          function registerRuntimeListener(listener, eventName) {
            if (typeof listener !== "function" || runtimeListenerIDs.has(listener)) {
              return;
            }
            nextListenerNumber += 1;
            const listenerID = [config.surfaceID, eventName, String(nextListenerNumber)].join(":");
            runtimeListenerIDs.set(listener, listenerID);
            if (eventName === "onMessage") {
              runtimeListeners.push(listener);
            } else {
              onConnectListeners.push(listener);
            }
            bridgePost("runtime", eventName + ".addListener", "fireAndForget", [], {
              listenerID,
              eventName
            }).catch(() => undefined);
          }

          function removeRuntimeListener(listener, eventName) {
            const listenerID = runtimeListenerIDs.get(listener);
            if (!listenerID) {
              return;
            }
            runtimeListenerIDs.delete(listener);
            const list = eventName === "onMessage" ? runtimeListeners : onConnectListeners;
            const index = list.indexOf(listener);
            if (index >= 0) {
              list.splice(index, 1);
            }
            bridgePost("runtime", eventName + ".removeListener", "fireAndForget", [], {
              listenerID,
              eventName
            }).catch(() => undefined);
          }

          async function dispatchRuntimeOnMessage(message) {
            for (const listener of runtimeListeners.slice()) {
              let responded = false;
              let responseValue;
              const sendResponse = (value) => {
                if (!responded) {
                  responded = true;
                  responseValue = value === undefined ? null : value;
                }
              };
              const returned = listener(message, {id: config.extensionID}, sendResponse);
              if (returned && typeof returned.then === "function") {
                const awaited = await returned;
                if (awaited !== undefined) {
                  return { didRespond: true, value: awaited };
                }
              } else if (returned !== undefined && returned !== true) {
                return { didRespond: true, value: returned };
              }
              if (responded) {
                return { didRespond: true, value: responseValue };
              }
            }
            return { didRespond: false, value: undefined };
          }

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "getURL", {
            value(path) {
              const raw = path === undefined || path === null ? "" : String(path);
              const trimmed = raw.replace(/^\\/+/, "");
              return "chrome-extension://" + config.extensionID + "/" + trimmed;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "sendMessage", {
            value() {
              const rawArgs = Array.prototype.slice.call(arguments);
              let callback = null;
              if (rawArgs.length > 0 && typeof rawArgs[rawArgs.length - 1] === "function") {
                callback = rawArgs.pop();
              }
              const mode = callback ? "callback" : "promise";
              const promise = bridgePost("runtime", "sendMessage", mode, rawArgs.map(toJSONCompatible))
                .then(async (response) => {
                  if (response.succeeded) {
                    const local = await dispatchRuntimeOnMessage(rawArgs[0]);
                    if (local.didRespond) {
                      response.resultPayload = toJSONCompatible(local.value);
                    }
                  }
                  return response;
                });
              if (callback) {
                promise.then((response) => {
                  if (response.succeeded) {
                    invokeCallback(callback, null, [response.resultPayload]);
                  } else {
                    invokeCallback(callback, response.lastErrorMessage, []);
                  }
                });
                return undefined;
              }
              return promise.then((response) => {
                if (response.succeeded) {
                  return response.resultPayload;
                }
                return rejectFromResponse(response, "runtime.sendMessage failed.");
              });
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "connect", {
            value(connectInfo) {
              const info = connectInfo && typeof connectInfo === "object" ? connectInfo : {};
              const port = createPort(info.name || "", "runtime");
              const state = portState.get(port);
              nextPortNumber += 1;
              state.id = [config.surfaceID, "runtime-port", String(nextPortNumber)].join(":");
              bridgePost("runtime", "connect", "fireAndForget", [info])
                .then((response) => {
                  if (!response.succeeded) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                  } else if (response.resultPayload && response.resultPayload.portID) {
                    state.id = response.resultPayload.portID;
                  }
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                });
              onConnectListeners.slice().forEach((listener) => listener(port));
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "onMessage", {
            value: Object.freeze({
              addListener(listener) { registerRuntimeListener(listener, "onMessage"); },
              removeListener(listener) { removeRuntimeListener(listener, "onMessage"); },
              hasListener(listener) { return runtimeListenerIDs.has(listener); },
              hasListeners() { return runtimeListeners.length > 0; }
            }),
            enumerable: true
          });

          Object.defineProperty(runtime, "onConnect", {
            value: Object.freeze({
              addListener(listener) { registerRuntimeListener(listener, "onConnect"); },
              removeListener(listener) { removeRuntimeListener(listener, "onConnect"); },
              hasListener(listener) { return runtimeListenerIDs.has(listener); },
              hasListeners() { return onConnectListeners.length > 0; }
            }),
            enumerable: true
          });

          Object.defineProperty(permissions, "contains", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "contains", [permissionsObject || {}], cb);
            },
            enumerable: true
          });
          Object.defineProperty(permissions, "getAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "getAll", [], cb);
            },
            enumerable: true
          });
          Object.defineProperty(permissions, "request", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "request", [permissionsObject || {}], cb);
            },
            enumerable: true
          });
          Object.defineProperty(permissions, "remove", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "remove", [permissionsObject || {}], cb);
            },
            enumerable: true
          });
          Object.defineProperty(permissions, "onAdded", {
            value: permissionsOnAdded,
            enumerable: true
          });
          Object.defineProperty(permissions, "onRemoved", {
            value: permissionsOnRemoved,
            enumerable: true
          });

          Object.defineProperty(tabs, "query", {
            value(queryInfo, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("tabs", "query", [queryInfo || {}], cb);
            },
            enumerable: true
          });
          Object.defineProperty(tabs, "sendMessage", {
            value(tabId, message, options, callback) {
              let cb = null;
              let opts = options;
              if (typeof opts === "function") {
                cb = opts;
                opts = undefined;
              } else if (typeof callback === "function") {
                cb = callback;
              }
              const args = opts === undefined ? [tabId, message] : [tabId, message, opts];
              return callbackOrPromise("tabs", "sendMessage", args, cb);
            },
            enumerable: true
          });
          Object.defineProperty(tabs, "connect", {
            value(tabId, connectInfo) {
              const info = connectInfo && typeof connectInfo === "object" ? connectInfo : {};
              const port = createPort(info.name || "", "tabs");
              const state = portState.get(port);
              nextPortNumber += 1;
              state.id = [config.surfaceID, "tabs-port", String(nextPortNumber)].join(":");
              bridgePost("tabs", "connect", "fireAndForget", [tabId, info])
                .then((response) => {
                  if (!response.succeeded) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                  } else if (response.resultPayload && response.resultPayload.portID) {
                    state.id = response.resultPayload.portID;
                  }
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                });
              return port;
            },
            enumerable: true
          });

          function normalizeExecuteScriptDetails(details) {
            const source = Object.assign({}, details || {});
            if (typeof source.func === "function") {
              source.functionSource = Function.prototype.toString.call(source.func);
              delete source.func;
            }
            return source;
          }
          Object.defineProperty(scripting, "executeScript", {
            value(details, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "scripting",
                "executeScript",
                [normalizeExecuteScriptDetails(details)],
                cb
              );
            },
            enumerable: true
          });

          Object.defineProperty(local, "get", {
            value(keys, callback) {
              const parsed = optionalKeysAndCallback(keys, callback);
              const args = parsed.keys === undefined ? [] : [parsed.keys];
              return callbackOrPromise("storage", "local.get", args, parsed.callback, {
                callbackValue: (response) => response.resultPayload || {},
                promiseValue: (response) => response.resultPayload || {}
              });
            },
            enumerable: true
          });
          Object.defineProperty(local, "set", {
            value(items, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("storage", "local.set", [items], cb, {
                callbackValue: () => undefined,
                promiseValue: () => undefined
              });
            },
            enumerable: true
          });
          Object.defineProperty(local, "remove", {
            value(keys, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("storage", "local.remove", [keys], cb, {
                callbackValue: () => undefined,
                promiseValue: () => undefined
              });
            },
            enumerable: true
          });
          Object.defineProperty(local, "clear", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("storage", "local.clear", [], cb, {
                callbackValue: () => undefined,
                promiseValue: () => undefined
              });
            },
            enumerable: true
          });
          Object.defineProperty(local, "getBytesInUse", {
            value(keys, callback) {
              const parsed = optionalKeysAndCallback(keys, callback);
              const args = parsed.keys === undefined ? [] : [parsed.keys];
              return callbackOrPromise("storage", "local.getBytesInUse", args, parsed.callback, {
                callbackValue: (response) => Number(response.resultPayload || 0),
                promiseValue: (response) => Number(response.resultPayload || 0)
              });
            },
            enumerable: true
          });
          Object.defineProperty(storage, "local", {
            value: Object.freeze(local),
            enumerable: true
          });
          Object.defineProperty(storage, "onChanged", {
            value: storageOnChanged,
            enumerable: true
          });

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "permissions", {
            value: Object.freeze(permissions),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "tabs", {
            value: Object.freeze(tabs),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "scripting", {
            value: Object.freeze(scripting),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "storage", {
            value: Object.freeze(storage),
            enumerable: true
          });
          Object.defineProperty(globalThis, "chrome", {
            value: Object.freeze(chromeObject),
            configurable: true
          });
          Object.defineProperty(globalThis, "__sumiChromeMV3PasswordManagerFixture", {
            value: Object.freeze({
              grantActiveTab(details) {
                return callbackOrPromise("fixture", "grantActiveTab", [details || {}], null);
              },
              expireActiveTabForNavigation(details) {
                return callbackOrPromise("fixture", "expireActiveTabForNavigation", [details || {}], null);
              },
              snapshot() {
                return callbackOrPromise("fixture", "snapshot", [], null);
              },
              reset() {
                return callbackOrPromise("fixture", "reset", [], null);
              }
            }),
            configurable: true
          });
        })();
        """
    }

    private static func jsonString(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct ChromeMV3PasswordManagerStorageFlowResult:
    Codable,
    Equatable,
    Sendable
{
    var setSucceeded: Bool
    var readBackSucceeded: Bool
    var removeSucceeded: Bool
    var getBytesInUseSucceeded: Bool
    var onChangedObservedOrPayloadGenerated: Bool
    var invalidValueErrorDeterministic: Bool
    var credentialRecordSchema: ChromeMV3StorageValue
    var changedKeys: [String]
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerTabDiscoveryFlowResult:
    Codable,
    Equatable,
    Sendable
{
    var redactedWithoutPermission: Bool
    var visibleWithActiveTab: Bool
    var visibleWithHostPermission: Bool
    var redactedAfterActiveTabExpiry: Bool
    var activeTabGrantRecorded: Bool
    var activeTabExpiryRecorded: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerContentMessagingFlowResult:
    Codable,
    Equatable,
    Sendable
{
    var detectFieldsSucceeded: Bool
    var fillFieldsSucceeded: Bool
    var noReceivingEndDeterministic: Bool
    var missingPermissionDeterministic: Bool
    var runtimeMessagingSucceeded: Bool
    var detectedFieldMetadata: ChromeMV3StorageValue?
    var fillResultPayload: ChromeMV3StorageValue?
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerScriptingFlowResult:
    Codable,
    Equatable,
    Sendable
{
    var executeScriptSucceededInControlledSyntheticTarget: Bool
    var missingScriptingPermissionBlocks: Bool
    var missingHostOrActiveTabBlocks: Bool
    var productTargetBlocks: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerPermissionActiveTabFlowResult:
    Codable,
    Equatable,
    Sendable
{
    var containsReflectsRequiredPermission: Bool
    var getAllReflectsCurrentState: Bool
    var modeledAcceptGrantsOptionalHost: Bool
    var requestWithoutModeledPromptReturnsProductUIUnavailable: Bool
    var removeRevokesOptionalHost: Bool
    var activeTabGrantAllowsTemporaryAccess: Bool
    var activeTabExpiryReblocksAccess: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerNativeMessagingBlockerFlow:
    Codable,
    Equatable,
    Sendable
{
    var nativeMessagingPermissionDetected: Bool
    var requestedHostName: String
    var hostLookupStatus: ChromeMV3NativeHostLookupStatus
    var trustedHostPolicyState: ChromeMV3NativeTrustedHostTrustState
    var trustedHostApprovedForDeveloperPreview: Bool
    var trustedHostApprovalRequired: Bool
    var canConnectNativeNow: Bool
    var processLaunchAllowedNow: Bool
    var nativeMessagingAvailableInInternalFixture: Bool
    var processLaunchAllowedForFixtureHost: Bool
    var nativeMessagingAvailableInProduct: Bool
    var processLaunchAllowedInProduct: Bool
    var passwordManagerNativeMessagingReady: Bool
    var passwordManagerNativeMessagingReadyInFixture: Bool
    var nextBlockerPrompt: String
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerServiceWorkerBlockerFlow:
    Codable,
    Equatable,
    Sendable
{
    var serviceWorkerScriptDeclared: Bool
    var serviceWorkerWakeAvailable: Bool
    var portKeepaliveProductReady: Bool
    var passwordManagerServiceWorkerReady: Bool
    var nextBlockerPrompt: String
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerAPIReadinessEntry:
    Codable,
    Equatable,
    Sendable
{
    var api: String
    var classification: ChromeMV3PasswordManagerReadinessClassification
    var availableInSyntheticHarness: Bool
    var availableInProductRuntime: Bool
    var blockers: [String]
}

struct ChromeMV3PasswordManagerCombinedWebKitExecutionSummary:
    Codable,
    Equatable,
    Sendable
{
    var status: String
    var combinedJSExecutedInWebKitSyntheticHarness: Bool
    var storageFlowPassed: Bool
    var tabDiscoveryFlowPassed: Bool
    var contentMessagingFlowPassed: Bool
    var scriptingFlowPassed: Bool
    var permissionActiveTabFlowPassed: Bool
    var runtimeMessagingFlowPassed: Bool
    var storageOnChangedObserved: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    static func notAttempted()
        -> ChromeMV3PasswordManagerCombinedWebKitExecutionSummary
    {
        ChromeMV3PasswordManagerCombinedWebKitExecutionSummary(
            status: "notAttemptedByModelReportGenerator",
            combinedJSExecutedInWebKitSyntheticHarness: false,
            storageFlowPassed: false,
            tabDiscoveryFlowPassed: false,
            contentMessagingFlowPassed: false,
            scriptingFlowPassed: false,
            permissionActiveTabFlowPassed: false,
            runtimeMessagingFlowPassed: false,
            storageOnChangedObserved: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Combined WebKit synthetic harness was not run by this model report generator.",
            ]
        )
    }

    static func fromWebKitScriptResult(
        json: String?,
        scriptEvaluationSucceeded: Bool,
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerCombinedWebKitExecutionSummary {
        let object = decodedObject(json)
        func bool(_ key: String) -> Bool {
            object?[key] as? Bool ?? false
        }
        return ChromeMV3PasswordManagerCombinedWebKitExecutionSummary(
            status:
                scriptEvaluationSucceeded
                    ? "executedInWebKitSyntheticHarness"
                    : "blockedOrFailedInWebKitSyntheticHarness",
            combinedJSExecutedInWebKitSyntheticHarness:
                scriptEvaluationSucceeded,
            storageFlowPassed: bool("storageFlowOK"),
            tabDiscoveryFlowPassed: bool("tabDiscoveryFlowOK"),
            contentMessagingFlowPassed: bool("contentMessagingFlowOK"),
            scriptingFlowPassed: bool("scriptingFlowOK"),
            permissionActiveTabFlowPassed:
                bool("permissionActiveTabFlowOK"),
            runtimeMessagingFlowPassed: bool("runtimeMessagingFlowOK"),
            storageOnChangedObserved: bool("storageOnChangedOK"),
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPasswordManager(
                    diagnostics
                        + [
                            scriptEvaluationSucceeded
                                ? "Combined password-manager JS calls executed in the controlled WebKit synthetic harness."
                                : "Combined password-manager WebKit harness produced a deterministic blocked/failed diagnostic.",
                            "WebKit execution is separate from product runtime availability.",
                        ]
                )
        )
    }

    private static func decodedObject(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return value as? [String: Any]
    }
}

struct ChromeMV3PasswordManagerFixtureReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var passwordManagerSyntheticJSReady: Bool
    var passwordManagerNativeMessagingReady: Bool
    var passwordManagerServiceWorkerReady: Bool
    var passwordManagerSharedLifecycleReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3PasswordManagerFixtureReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var fixtureManifestSummary:
        [ChromeMV3PasswordManagerFixtureManifest]
    var loginPageFixture: ChromeMV3PasswordManagerLoginPageFixture
    var combinedShimCoverage: ChromeMV3PasswordManagerCombinedShimCoverage
    var webKitExecutionSummary:
        ChromeMV3PasswordManagerCombinedWebKitExecutionSummary
    var storageFlowResult: ChromeMV3PasswordManagerStorageFlowResult
    var tabDiscoveryResult: ChromeMV3PasswordManagerTabDiscoveryFlowResult
    var contentMessagingResult:
        ChromeMV3PasswordManagerContentMessagingFlowResult
    var scriptingResult: ChromeMV3PasswordManagerScriptingFlowResult
    var permissionActiveTabResult:
        ChromeMV3PasswordManagerPermissionActiveTabFlowResult
    var nativeMessagingBlocker:
        ChromeMV3PasswordManagerNativeMessagingBlockerFlow
    var serviceWorkerLifecycleBlocker:
        ChromeMV3PasswordManagerServiceWorkerBlockerFlow
    var apiReadinessMatrix:
        [ChromeMV3PasswordManagerAPIReadinessEntry]
    var runtimeJSMessagingMVPSummary:
        ChromeMV3RuntimeJSMessagingMVPReportSummary?
    var tabsScriptingMVPSummary:
        ChromeMV3TabsScriptingMVPReportSummary?
    var storageLocalImplementationSummary:
        ChromeMV3StorageLocalImplementationReportSummary?
    var nativeMessagingReadinessSummary:
        ChromeMV3NativeMessagingReadinessReportSummary?
    var nativeMessagingImplementationSummary:
        ChromeMV3NativeMessagingImplementationReportSummary?
    var serviceWorkerLifecycleSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary?
    var sharedLifecycleSessionSummary:
        ChromeMV3ServiceWorkerSharedLifecycleSessionReportSummary?
    var extensionEventAPIsSummary:
        ChromeMV3ExtensionEventAPIsReportSummary?
    var passwordManagerSyntheticJSReady: Bool
    var passwordManagerNativeMessagingReady: Bool
    var passwordManagerNativeMessagingReadyInFixture: Bool
    var passwordManagerServiceWorkerReady: Bool
    var passwordManagerSharedLifecycleReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3PasswordManagerFixtureReportSummary {
        ChromeMV3PasswordManagerFixtureReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            passwordManagerSyntheticJSReady:
                passwordManagerSyntheticJSReady,
            passwordManagerNativeMessagingReady:
                passwordManagerNativeMessagingReadyInFixture,
            passwordManagerServiceWorkerReady:
                passwordManagerServiceWorkerReady,
            passwordManagerSharedLifecycleReadyInFixture:
                passwordManagerSharedLifecycleReadyInFixture,
            passwordManagerProductRuntimeReady: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }
}

enum ChromeMV3PasswordManagerFixtureReportWriter {
    static let reportFileName =
        "runtime-password-manager-fixture-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3PasswordManagerFixtureReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3PasswordManagerFixtureReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3PasswordManagerCompatibilityTargetKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case bitwardenClass = "Bitwarden-class"
    case onePasswordClass = "1Password-class"
    case protonPassClass = "Proton Pass-class"

    static func < (
        lhs: ChromeMV3PasswordManagerCompatibilityTargetKind,
        rhs: ChromeMV3PasswordManagerCompatibilityTargetKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var pathComponent: String {
        switch self {
        case .bitwardenClass:
            return "bitwarden-class"
        case .onePasswordClass:
            return "onepassword-class"
        case .protonPassClass:
            return "proton-pass-class"
        }
    }
}

enum ChromeMV3PasswordManagerCompatibilityStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case pass
    case partial
    case blocked
    case deferred
    case unsupported
    case notRequired
    case fixtureOnly
    case unsafeWithoutReview

    static func < (
        lhs: ChromeMV3PasswordManagerCompatibilityStatus,
        rhs: ChromeMV3PasswordManagerCompatibilityStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerPackageSelectionKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case localUnpacked
    case localZip
    case reviewedFixture
    case missing

    static func < (
        lhs: ChromeMV3PasswordManagerPackageSelectionKind,
        rhs: ChromeMV3PasswordManagerPackageSelectionKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerNativeHostRequirement:
    Codable,
    Equatable,
    Sendable
{
    var required: Bool
    var optional: Bool
    var hostName: String?
    var expectedExtensionIDAlias: String?
    var allowedOrigin: String?
    var aliasMappingSource: String?
    var allowedOriginsCompatibility: ChromeMV3PasswordManagerCompatibilityStatus
    var requiresTrustedHostApproval: Bool
    var realHostDiscoveryAllowed: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerContentScriptRequirement:
    Codable,
    Equatable,
    Sendable
{
    var matches: [String]
    var js: [String]
    var css: [String]
    var allFrames: Bool
    var world: String
    var requiresCSS: Bool
    var requiresMainWorld: Bool
    var requiresMultiFrame: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerPopupOptionsRequirement:
    Codable,
    Equatable,
    Sendable
{
    var popupPath: String
    var optionsPath: String
    var requiredBridgeMethods: [String]
}

struct ChromeMV3PasswordManagerCompatibilityTargetRecord:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PasswordManagerCompatibilityTargetKind
    var displayName: String
    var fixturePackageRelativePath: String
    var localPackageSearchRelativePaths: [String]
    var expectedExtensionIDOrAlias: String
    var extensionIDAliasMappingSource: String
    var nativeHostRequirement:
        ChromeMV3PasswordManagerNativeHostRequirement
    var requiredPermissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var contentScriptRequirement:
        ChromeMV3PasswordManagerContentScriptRequirement
    var popupOptionsRequirement:
        ChromeMV3PasswordManagerPopupOptionsRequirement
    var storageRequirements: [String]
    var runtimeTabsMessagingRequirements: [String]
    var knownBlockedDeferredAPIs: [String]
    var noRealCredentialsInvariant: Bool
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerCompatibilityTargetCatalog {
    static func all() -> [ChromeMV3PasswordManagerCompatibilityTargetRecord] {
        ChromeMV3PasswordManagerCompatibilityTargetKind.allCases
            .sorted()
            .map(target)
    }

    static func target(
        _ kind: ChromeMV3PasswordManagerCompatibilityTargetKind
    ) -> ChromeMV3PasswordManagerCompatibilityTargetRecord {
        let alias =
            ChromeMV3NativeMessagingAllowedOrigin
            .nativeMessagingOriginExtensionID(for: kind.rawValue)
        let allowedOrigin =
            ChromeMV3NativeMessagingAllowedOrigin
            .originString(extensionID: kind.rawValue)
        let basePermissions = ["activeTab", "scripting", "storage"]
        let baseOptional = ["tabs"]
        let baseMatches = ["https://example.com/*"]
        let fixturePath =
            "password-manager-fixtures/\(kind.pathComponent)"
        var permissions = basePermissions
        var optional = baseOptional
        var hostPermissions: [String] = []
        var optionalHosts = baseMatches
        var native = nativeRequirement(
            required: false,
            optional: false,
            hostName: nil,
            alias: alias,
            allowedOrigin: allowedOrigin
        )
        var content = ChromeMV3PasswordManagerContentScriptRequirement(
            matches: baseMatches,
            js: ["content-script.js"],
            css: [],
            allFrames: false,
            world: "ISOLATED",
            requiresCSS: false,
            requiresMainWorld: false,
            requiresMultiFrame: false,
            diagnostics: [
                "Static isolated-world content script is the reviewed fixture baseline.",
            ]
        )
        var deferred: [String] = []
        var diagnostics = [
            "Target is a password-manager-class compatibility fixture, not a vendor support claim.",
            "No real extension code, accounts, vaults, credentials, or vendor assets are used.",
        ]

        switch kind {
        case .bitwardenClass:
            optional = (baseOptional + ["nativeMessaging"]).sorted()
            native = nativeRequirement(
                required: false,
                optional: true,
                hostName:
                    "com.sumi.synthetic_password_manager.bitwarden",
                alias: alias,
                allowedOrigin: allowedOrigin
            )
            content.css = ["content-style.css"]
            content.requiresCSS = true
            content.diagnostics.append(
                "CSS attachment is developer-preview partial through manifest-declared WebKit user stylesheets."
            )
            diagnostics.append(
                "Fixture stresses popup/options, static content scripts, optional host access, storage.local, tabs messaging, and optional native messaging."
            )
        case .onePasswordClass:
            permissions = (basePermissions + ["nativeMessaging"]).sorted()
            native = nativeRequirement(
                required: true,
                optional: false,
                hostName:
                    "com.sumi.synthetic_password_manager.onepassword",
                alias: alias,
                allowedOrigin: allowedOrigin
            )
            content.world = "MAIN"
            content.requiresMainWorld = true
            content.diagnostics.append(
                "MAIN-world behavior remains unsafe without a separate WebKit bridge review."
            )
            diagnostics.append(
                "Fixture stresses required native messaging plus service-worker and tabs Port behavior."
            )
        case .protonPassClass:
            hostPermissions = []
            optionalHosts = baseMatches
            content.allFrames = true
            content.requiresMultiFrame = true
            deferred = ["identity", "offscreen"]
            content.diagnostics.append(
                "Multi-frame behavior is reported deferred until frame targeting is product-safe."
            )
            diagnostics.append(
                "Fixture stresses no-native-host operation, activeTab, storage.local, and deferred account-flow APIs."
            )
        }

        return ChromeMV3PasswordManagerCompatibilityTargetRecord(
            kind: kind,
            displayName: kind.rawValue,
            fixturePackageRelativePath: fixturePath,
            localPackageSearchRelativePaths: [
                "\(kind.pathComponent)",
                "\(kind.pathComponent).zip",
                "fixtures/\(kind.pathComponent)",
                "fixtures/\(kind.pathComponent).zip",
            ],
            expectedExtensionIDOrAlias: alias,
            extensionIDAliasMappingSource:
                "deterministic target-class alias for native host allowed_origins only",
            nativeHostRequirement: native,
            requiredPermissions: permissions.sorted(),
            optionalPermissions: optional.sorted(),
            hostPermissions: hostPermissions.sorted(),
            optionalHostPermissions: optionalHosts.sorted(),
            contentScriptRequirement: content,
            popupOptionsRequirement:
                ChromeMV3PasswordManagerPopupOptionsRequirement(
                    popupPath: "popup.html",
                    optionsPath: "options.html",
                    requiredBridgeMethods: [
                        "runtime.getURL",
                        "runtime.sendMessage",
                        "storage.local",
                        "permissions.contains",
                        "permissions.getAll",
                        "tabs.query",
                    ]
                ),
            storageRequirements: [
                "storage.local set/get/remove/getBytesInUse",
                "storage.onChanged synthetic event payload",
            ],
            runtimeTabsMessagingRequirements: [
                "runtime.sendMessage popup smoke",
                "tabs.query redaction and grant transition",
                "tabs.sendMessage detectFields-like content endpoint",
                "tabs.connect controlled Port lifecycle",
            ],
            knownBlockedDeferredAPIs: deferred.sorted(),
            noRealCredentialsInvariant: true,
            diagnostics: uniqueSortedPasswordManager(diagnostics)
        )
    }

    static func match(
        displayName: String,
        sourcePath: String?
    ) -> ChromeMV3PasswordManagerCompatibilityTargetRecord? {
        let haystack = ([displayName, sourcePath ?? ""])
            .joined(separator: " ")
            .lowercased()
        return all().first { target in
            haystack.contains(target.kind.pathComponent)
                || haystack.contains(target.kind.rawValue.lowercased())
        }
    }

    private static func nativeRequirement(
        required: Bool,
        optional: Bool,
        hostName: String?,
        alias: String,
        allowedOrigin: String
    ) -> ChromeMV3PasswordManagerNativeHostRequirement {
        ChromeMV3PasswordManagerNativeHostRequirement(
            required: required,
            optional: optional,
            hostName: hostName,
            expectedExtensionIDAlias: hostName == nil ? nil : alias,
            allowedOrigin: hostName == nil ? nil : allowedOrigin,
            aliasMappingSource:
                hostName == nil
                    ? nil
                    : "explicit reviewed fixture alias; real vendor identity is not rewritten",
            allowedOriginsCompatibility:
                hostName == nil ? .notRequired : .partial,
            requiresTrustedHostApproval: hostName != nil,
            realHostDiscoveryAllowed: false,
            diagnostics:
                hostName == nil
                    ? [
                        "This target class does not require native messaging.",
                    ]
                    : [
                        "Native host manifest must be under an explicit fixture root.",
                        "allowed_origins must match the extension id alias recorded for this fixture.",
                        "Trusted-host approval remains separate from nativeMessaging permission.",
                        "Real installed native hosts are not discovered.",
                    ]
        )
    }
}

struct ChromeMV3PasswordManagerPackageSelection:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PasswordManagerPackageSelectionKind
    var packagePath: String?
    var sourceDescription: String
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerFixturePackageBuilder {
    static func writeFixturePackage(
        for target: ChromeMV3PasswordManagerCompatibilityTargetRecord,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let packageRoot = rootURL.standardizedFileURL
            .appendingPathComponent(
                target.fixturePackageRelativePath,
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: packageRoot,
            withIntermediateDirectories: true
        )

        let content = target.contentScriptRequirement
        var contentScript: [String: Any] = [
            "matches": content.matches,
            "js": content.js,
            "all_frames": content.allFrames,
            "run_at": "document_idle",
            "world": content.world,
        ]
        if content.css.isEmpty == false {
            contentScript["css"] = content.css
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Sumi \(target.displayName) Fixture",
            "version": "0.0.1",
            "description":
                "Reviewed local password-manager-class fixture with no real credentials.",
            "permissions": target.requiredPermissions,
            "optional_permissions": target.optionalPermissions,
            "host_permissions": target.hostPermissions,
            "optional_host_permissions": target.optionalHostPermissions,
            "action": [
                "default_popup":
                    target.popupOptionsRequirement.popupPath,
                "default_title": target.displayName,
            ],
            "options_ui": [
                "page": target.popupOptionsRequirement.optionsPath,
                "open_in_tab": true,
            ],
            "background": [
                "service_worker": "service-worker.js",
            ],
            "content_scripts": [contentScript],
            "web_accessible_resources": [
                [
                    "resources": ["fixture-icon.svg"],
                    "matches": target.contentScriptRequirement.matches,
                ],
            ],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: packageRoot.appendingPathComponent("manifest.json")
        )
        try write(
            popupHTML(target: target),
            to: packageRoot.appendingPathComponent("popup.html")
        )
        try write(
            optionsHTML(target: target),
            to: packageRoot.appendingPathComponent("options.html")
        )
        try write(
            popupJS(target: target),
            to: packageRoot.appendingPathComponent("popup.js")
        )
        try write(
            contentScriptJS(target: target),
            to: packageRoot.appendingPathComponent("content-script.js")
        )
        try write(
            serviceWorkerJS(target: target),
            to: packageRoot.appendingPathComponent("service-worker.js")
        )
        try write(
            "form[data-sumi-password-manager-fixture] { outline: 1px solid transparent; }\n",
            to: packageRoot.appendingPathComponent("content-style.css")
        )
        try write(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\"><rect width=\"16\" height=\"16\" fill=\"#555\"/></svg>\n",
            to: packageRoot.appendingPathComponent("fixture-icon.svg")
        )
        return packageRoot
    }

    private static func popupHTML(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord
    ) -> String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>\(target.displayName) Fixture</title>
        <button id="detect">Detect</button>
        <script src="popup.js"></script>
        """
    }

    private static func optionsHTML(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord
    ) -> String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>\(target.displayName) Options Fixture</title>
        <label><input id="synthetic-only" type="checkbox"> Synthetic only</label>
        <script src="popup.js"></script>
        """
    }

    private static func popupJS(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord
    ) -> String {
        """
        "use strict";
        const targetClass = "\(target.kind.rawValue)";
        async function smoke() {
          const url = chrome.runtime.getURL("popup.html");
          await chrome.storage.local.set({["fixture:" + targetClass]: {url, syntheticOnly: true}});
          await chrome.storage.local.get("fixture:" + targetClass);
          await chrome.permissions.contains({permissions: ["activeTab"]});
          await chrome.permissions.getAll();
          await chrome.tabs.query({active: true, currentWindow: true});
          await chrome.runtime.sendMessage({type: "fixturePopupReady", targetClass});
        }
        smoke().catch(() => undefined);
        """
    }

    private static func contentScriptJS(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord
    ) -> String {
        """
        "use strict";
        chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
          if (message && message.type === "detectFields") {
            sendResponse({
              targetClass: "\(target.kind.rawValue)",
              detectedFields: {
                username: {selector: "#username", autocomplete: "username"},
                passphrase: {selector: "#password", autocomplete: "current-password"}
              }
            });
            return true;
          }
          if (message && message.type === "fillFields") {
            sendResponse({success: true, syntheticOnly: true});
            return true;
          }
          return false;
        });
        """
    }

    private static func serviceWorkerJS(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord
    ) -> String {
        """
        "use strict";
        chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
          if (message && message.type === "fixturePopupReady") {
            sendResponse({ok: true, targetClass: "\(target.kind.rawValue)"});
            return true;
          }
          return false;
        });
        """
    }

    private static func write(_ string: String, to url: URL) throws {
        try string.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum ChromeMV3PasswordManagerPackageResolver {
    static func resolve(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord,
        explicitPackageRootURL: URL?,
        fixtureRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3PasswordManagerPackageSelection {
        if let explicitPackageRootURL {
            for relative in target.localPackageSearchRelativePaths {
                let candidate = explicitPackageRootURL
                    .appendingPathComponent(relative)
                    .standardizedFileURL
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(
                    atPath: candidate.path,
                    isDirectory: &isDirectory
                ) {
                    if isDirectory.boolValue {
                        return ChromeMV3PasswordManagerPackageSelection(
                            kind: .localUnpacked,
                            packagePath: candidate.path,
                            sourceDescription:
                                "Explicit local unpacked package matched \(relative).",
                            diagnostics: [
                                "No Web Store download or remote CRX acquisition occurred.",
                            ]
                        )
                    }
                    if candidate.pathExtension.lowercased() == "zip" {
                        return ChromeMV3PasswordManagerPackageSelection(
                            kind: .localZip,
                            packagePath: candidate.path,
                            sourceDescription:
                                "Explicit local ZIP package matched \(relative).",
                            diagnostics: [
                                "ZIP intake remains local and safe-entry preflighted.",
                            ]
                        )
                    }
                }
            }
        }

        let fixture = try ChromeMV3PasswordManagerFixturePackageBuilder
            .writeFixturePackage(for: target, rootURL: fixtureRootURL)
        return ChromeMV3PasswordManagerPackageSelection(
            kind: .reviewedFixture,
            packagePath: fixture.path,
            sourceDescription:
                "Reviewed local target-class fixture generated under the explicit test root.",
            diagnostics: [
                "Real vendor package was unavailable or not explicitly supplied.",
                "Fixture package contains no proprietary code and no real credentials.",
                "No Web Store download or remote CRX acquisition occurred.",
            ]
        )
    }
}

struct ChromeMV3PasswordManagerNativeHostFixtureMapping:
    Codable,
    Equatable,
    Sendable
{
    var hostName: String
    var fixtureRootPath: String
    var manifestPath: String?
    var executablePath: String?
    var extensionID: String
    var allowedOrigin: String
    var lookupStatus: ChromeMV3NativeHostLookupStatus
    var trustedHostState: ChromeMV3NativeTrustedHostTrustState
    var approvalRequired: Bool
    var permissionRequired: Bool
    var canConnectNativeNow: Bool
    var processLaunchAllowedNow: Bool
    var arbitraryHostLaunchAllowed: Bool
    var nativeHostScanningAllowed: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerCompatibilityMatrixRow:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String { targetKind.rawValue }
    var targetKind: ChromeMV3PasswordManagerCompatibilityTargetKind
    var targetDisplayName: String
    var packageSourceKind: ChromeMV3PasswordManagerPackageSelectionKind
    var packagePath: String?
    var installImportResult: ChromeMV3PasswordManagerCompatibilityStatus
    var manifestAPIRequirements: [String]
    var hostPermissionRequirements: [String]
    var packageIntake: ChromeMV3PasswordManagerCompatibilityStatus
    var manifestValidation: ChromeMV3PasswordManagerCompatibilityStatus
    var generatedBundle: ChromeMV3PasswordManagerCompatibilityStatus
    var extensionManagerLifecycle:
        ChromeMV3PasswordManagerCompatibilityStatus
    var popupOptions: ChromeMV3PasswordManagerCompatibilityStatus
    var popupOptionsJSBridge: ChromeMV3PasswordManagerCompatibilityStatus
    var contentScripts: ChromeMV3PasswordManagerCompatibilityStatus
    var contentScriptCSS: ChromeMV3PasswordManagerCompatibilityStatus
    var mainWorld: ChromeMV3PasswordManagerCompatibilityStatus
    var multiFrame: ChromeMV3PasswordManagerCompatibilityStatus
    var permissions: ChromeMV3PasswordManagerCompatibilityStatus
    var activeTab: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsQuery: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsSendMessage: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsConnect: ChromeMV3PasswordManagerCompatibilityStatus
    var storageLocal: ChromeMV3PasswordManagerCompatibilityStatus
    var nativeMessaging: ChromeMV3PasswordManagerCompatibilityStatus
    var serviceWorkerLifecycle: ChromeMV3PasswordManagerCompatibilityStatus
    var dnrWebRequestRelevance:
        ChromeMV3PasswordManagerCompatibilityStatus
    var sidePanelOffscreenIdentityRelevance:
        ChromeMV3PasswordManagerCompatibilityStatus
    var securityTrustBlockers: [String]
    var productReadiness: ChromeMV3PasswordManagerCompatibilityStatus
    var productReadinessStatus: String
    var blockerSummary: [String]
    var nextRecommendedFix: String
    var notPublicSupportDisclaimer: String
}

struct ChromeMV3PasswordManagerCompatibilityReport:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1
    static let reportFileName =
        "runtime-mv3-password-manager-compatibility-report.json"

    var schemaVersion: Int
    var reportFileName: String
    var generatedAt: Date
    var targetRecords: [ChromeMV3PasswordManagerCompatibilityTargetRecord]
    var rows: [ChromeMV3PasswordManagerCompatibilityMatrixRow]
    var packageSelections: [ChromeMV3PasswordManagerPackageSelection]
    var nativeHostMappings:
        [ChromeMV3PasswordManagerNativeHostFixtureMapping]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var noWebStoreInstallAttempted: Bool
    var noRemoteCRXDownloadAttempted: Bool
    var noRealCredentialsUsed: Bool
    var arbitraryNativeHostDiscoveryAttempted: Bool
    var productRuntimeAvailable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerCompatibilityReportWriter {
    static let reportFileName =
        ChromeMV3PasswordManagerCompatibilityReport.reportFileName

    @discardableResult
    static func write(
        _ report: ChromeMV3PasswordManagerCompatibilityReport,
        to rootURL: URL
    ) throws -> ChromeMV3PasswordManagerCompatibilityReport {
        let url = rootURL.standardizedFileURL
            .appendingPathComponent(reportFileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(report, to: url)
        return report
    }
}

enum ChromeMV3PasswordManagerCompatibilityPassRunner {
    static func run(
        rootURL: URL,
        explicitPackageRootURL: URL? = nil,
        profileID: String = "password-manager-compatibility-profile",
        targetKinds: [ChromeMV3PasswordManagerCompatibilityTargetKind] =
            ChromeMV3PasswordManagerCompatibilityTargetKind.allCases.sorted(),
        writeReport: Bool = true,
        now: @escaping () -> Date = Date.init
    ) -> ChromeMV3PasswordManagerCompatibilityReport {
        let root = rootURL.standardizedFileURL
        let registry = ChromeMV3ExtensionLifecycleRegistry(
            rootURL: root,
            now: now
        )
        let intake = ChromeMV3PackageIntakeService(rootURL: root, now: now)
        var rows: [ChromeMV3PasswordManagerCompatibilityMatrixRow] = []
        var selections: [ChromeMV3PasswordManagerPackageSelection] = []
        var mappings: [ChromeMV3PasswordManagerNativeHostFixtureMapping] = []
        var diagnostics: [String] = []
        let fixtureRoot = root.appendingPathComponent(
            "PasswordManagerCompatibilityFixtures",
            isDirectory: true
        )
        let nativeFixtureRoot = root.appendingPathComponent(
            "NativeMessagingFixtureHosts",
            isDirectory: true
        )

        for target in targetKinds.map(ChromeMV3PasswordManagerCompatibilityTargetCatalog.target) {
            let selection: ChromeMV3PasswordManagerPackageSelection
            do {
                selection =
                    try ChromeMV3PasswordManagerPackageResolver.resolve(
                        target: target,
                        explicitPackageRootURL: explicitPackageRootURL,
                        fixtureRootURL: fixtureRoot
                    )
            } catch {
                selection = ChromeMV3PasswordManagerPackageSelection(
                    kind: .missing,
                    packagePath: nil,
                    sourceDescription:
                        "No local package or reviewed fixture could be prepared.",
                    diagnostics: [error.localizedDescription]
                )
            }
            selections.append(selection)

            let lifecycleResult: ChromeMV3LifecycleOperationResult?
            let packageReport: ChromeMV3PackageIntakeReport?
            if let packagePath = selection.packagePath {
                let packageURL = URL(
                    fileURLWithPath: packagePath,
                    isDirectory:
                        selection.kind != .localZip
                )
                if selection.kind == .localZip {
                    let imported = intake.importLocalZIPArchive(
                        sourceURL: packageURL,
                        profileID:
                            "\(profileID)-\(target.kind.pathComponent)",
                        enableInternal: true,
                        runtimeDiagnostics:
                            .passwordManagerCompatibilityPass
                    )
                    lifecycleResult = imported.lifecycleResult
                    packageReport = imported.report
                } else {
                    let result = registry.installUnpackedExtension(
                        at: packageURL,
                        profileID:
                            "\(profileID)-\(target.kind.pathComponent)",
                        enableInternal: true,
                        runtimeDiagnostics:
                            .passwordManagerCompatibilityPass
                    )
                    lifecycleResult = result
                    packageReport = intake.writeLocalUnpackedReport(
                        sourceURL: packageURL,
                        lifecycleResult: result
                    )
                }
            } else {
                lifecycleResult = nil
                packageReport = nil
            }

            let nativeMapping = nativeFixtureMapping(
                target: target,
                lifecycleResult: lifecycleResult,
                nativeFixtureRoot: nativeFixtureRoot
                    .appendingPathComponent(
                        target.kind.pathComponent,
                        isDirectory: true
                    )
            )
            if let nativeMapping {
                mappings.append(nativeMapping)
            }
            rows.append(
                matrixRow(
                    target: target,
                    selection: selection,
                    lifecycleResult: lifecycleResult,
                    packageReport: packageReport,
                    nativeMapping: nativeMapping
                )
            )
            diagnostics.append(contentsOf: selection.diagnostics)
            diagnostics.append(contentsOf: lifecycleResult?.diagnostics ?? [])
        }

        let report = ChromeMV3PasswordManagerCompatibilityReport(
            schemaVersion:
                ChromeMV3PasswordManagerCompatibilityReport.schemaVersion,
            reportFileName:
                ChromeMV3PasswordManagerCompatibilityReport.reportFileName,
            generatedAt: now(),
            targetRecords:
                targetKinds
                .map(ChromeMV3PasswordManagerCompatibilityTargetCatalog.target)
                .sorted { $0.kind < $1.kind },
            rows: rows.sorted { $0.targetKind < $1.targetKind },
            packageSelections: selections.sorted {
                $0.sourceDescription < $1.sourceDescription
            },
            nativeHostMappings: mappings.sorted {
                if $0.hostName != $1.hostName {
                    return $0.hostName < $1.hostName
                }
                return $0.extensionID < $1.extensionID
            },
            documentationSources: documentationSources(),
            noWebStoreInstallAttempted: true,
            noRemoteCRXDownloadAttempted: true,
            noRealCredentialsUsed: true,
            arbitraryNativeHostDiscoveryAttempted: false,
            productRuntimeAvailable: false,
            productRuntimeExposed: false,
            diagnostics:
                uniqueSortedPasswordManager(
                    diagnostics + [
                        "Password-manager compatibility pass used only explicit local paths or reviewed fixtures.",
                        "Chrome Web Store install, scraping, spoofing, and remote CRX download were not attempted.",
                        "Product runtime and public password-manager support remain unavailable.",
                    ]
                )
        )
        if writeReport {
            return (
                try? ChromeMV3PasswordManagerCompatibilityReportWriter
                    .write(report, to: root)
            ) ?? report
        }
        return report
    }

    private static func nativeFixtureMapping(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord,
        lifecycleResult: ChromeMV3LifecycleOperationResult?,
        nativeFixtureRoot: URL
    ) -> ChromeMV3PasswordManagerNativeHostFixtureMapping? {
        guard let hostName = target.nativeHostRequirement.hostName,
              let extensionID = lifecycleResult?.record?.extensionID
        else { return nil }
        let permissionState: ChromeMV3NativeMessagingPermissionState =
            target.requiredPermissions.contains("nativeMessaging")
                ? .grantedByManifest
                : (
                    target.optionalPermissions.contains("nativeMessaging")
                        ? .deferred
                        : .missing
                )
        let fixture: ChromeMV3NativeMessagingFixtureHost?
        do {
            fixture = try ChromeMV3NativeMessagingFixtureHostBuilder
                .writeFixtureHost(
                    kind: .echo,
                    rootURL: nativeFixtureRoot,
                    hostName: hostName,
                    extensionID: extensionID
                )
        } catch {
            fixture = nil
        }
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: nativeFixtureRoot.path
        )
        let trusted = ChromeMV3NativeTrustedHostApprovalRecord.unknown(
            hostName: hostName,
            extensionID: extensionID,
            profileID: lifecycleResult?.record?.profileID
                ?? "password-manager-compatibility-profile"
        )
        let preflight = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: extensionID,
                profileID: lifecycleResult?.record?.profileID
                    ?? "password-manager-compatibility-profile",
                hostName: hostName,
                operationKind: .longLivedNativePort,
                sourceContext: .extensionPage,
                permissionState: permissionState,
                productPolicy:
                    ChromeMV3NativeMessagingProductPolicy
                    .blockedRuntimeDefault,
                trustedHostPolicyRecord: trusted
            ),
            lookupPolicy: lookupPolicy
        )
        return ChromeMV3PasswordManagerNativeHostFixtureMapping(
            hostName: hostName,
            fixtureRootPath: nativeFixtureRoot.path,
            manifestPath:
                fixture?.manifestPath
                    ?? preflight.hostLookupResult.manifest?
                    .sourceLocation.manifestPath,
            executablePath:
                fixture?.executablePath
                    ?? preflight.hostLookupResult.manifest?.path,
            extensionID: extensionID,
            allowedOrigin:
                ChromeMV3NativeMessagingAllowedOrigin.originString(
                    extensionID: extensionID
                ),
            lookupStatus: preflight.hostLookupResult.status,
            trustedHostState: trusted.trustState,
            approvalRequired:
                preflight.trustedHostPolicyApproved == false
                    && target.nativeHostRequirement
                    .requiresTrustedHostApproval,
            permissionRequired:
                preflight.authorizationResult
                .hasNativeMessagingPermission == false,
            canConnectNativeNow: preflight.canConnectNativeNow,
            processLaunchAllowedNow: preflight.processLaunchAllowedNow,
            arbitraryHostLaunchAllowed: false,
            nativeHostScanningAllowed: false,
            diagnostics:
                uniqueSortedPasswordManager(
                    (fixture?.diagnostics ?? [])
                        + preflight.diagnostics
                        + [
                            "Native host mapping is explicit fixture-root only.",
                            "No real vendor native host discovery occurred.",
                        ]
                )
        )
    }

    private static func matrixRow(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord,
        selection: ChromeMV3PasswordManagerPackageSelection,
        lifecycleResult: ChromeMV3LifecycleOperationResult?,
        packageReport: ChromeMV3PackageIntakeReport?,
        nativeMapping: ChromeMV3PasswordManagerNativeHostFixtureMapping?
    ) -> ChromeMV3PasswordManagerCompatibilityMatrixRow {
        let succeeded = lifecycleResult?.succeeded == true
        let manifestSummary = lifecycleResult?.report?.passwordManagerManifestSummary
            ?? packageReport?.validationResult.manifestSummary
        let generatedAvailable =
            lifecycleResult?.generatedVersion != nil
                || lifecycleResult?.record?.activeGeneratedVersionID != nil
        let fixtureReport =
            ChromeMV3PasswordManagerFixtureReportGenerator.makeReport(
                extensionID: lifecycleResult?.record?.extensionID
                    ?? target.expectedExtensionIDOrAlias,
                profileID: lifecycleResult?.record?.profileID
                    ?? "password-manager-compatibility-profile"
            )
        let nativeStatus: ChromeMV3PasswordManagerCompatibilityStatus
        if target.nativeHostRequirement.required {
            nativeStatus =
                nativeMapping?.canConnectNativeNow == true
                    ? .partial
                    : .blocked
        } else if target.nativeHostRequirement.optional {
            nativeStatus =
                nativeMapping?.lookupStatus == .found ? .partial : .deferred
        } else {
            nativeStatus = .notRequired
        }
        let cssStatus: ChromeMV3PasswordManagerCompatibilityStatus =
            target.contentScriptRequirement.requiresCSS
                ? .partial
                : .notRequired
        let mainWorldStatus: ChromeMV3PasswordManagerCompatibilityStatus =
            target.contentScriptRequirement.requiresMainWorld
                ? .unsafeWithoutReview
                : .notRequired
        let multiFrameStatus: ChromeMV3PasswordManagerCompatibilityStatus =
            target.contentScriptRequirement.requiresMultiFrame
                ? .deferred
                : .notRequired
        let identityStatus: ChromeMV3PasswordManagerCompatibilityStatus =
            target.knownBlockedDeferredAPIs.contains {
                $0 == "identity" || $0 == "offscreen" || $0 == "sidePanel"
            } ? .deferred : .notRequired
        var blockers = [
            "Product runtime remains unavailable; this is not public password-manager support.",
        ]
        if cssStatus == .partial {
            blockers.append(
                "Manifest content-script CSS is developer-preview scoped through WebKit user stylesheets and remains unavailable as public product support."
            )
        }
        if mainWorldStatus == .unsafeWithoutReview {
            blockers.append(
                "MAIN-world content-script behavior requires a separate bridge review."
            )
        }
        if multiFrameStatus == .deferred {
            blockers.append(
                "Multi-frame attachment remains deferred until frame targeting is product-safe."
            )
        }
        if nativeStatus == .blocked {
            blockers.append(
                "Native messaging requires both nativeMessaging permission and explicit trusted-host approval."
            )
        } else if nativeStatus == .partial {
            blockers.append(
                "Native messaging is fixture-root only and not product host discovery."
            )
        }
        if identityStatus == .deferred {
            blockers.append(
                "sidePanel/offscreen/identity account-flow APIs remain deferred."
            )
        }
        let hostRequirements =
            uniqueSortedPasswordManager(
                target.hostPermissions + target.optionalHostPermissions
            )
        return ChromeMV3PasswordManagerCompatibilityMatrixRow(
            targetKind: target.kind,
            targetDisplayName: target.displayName,
            packageSourceKind: selection.kind,
            packagePath: selection.packagePath,
            installImportResult: succeeded ? .pass : .blocked,
            manifestAPIRequirements:
                uniqueSortedPasswordManager(
                    target.requiredPermissions
                        + target.optionalPermissions
                        + target.knownBlockedDeferredAPIs
                ),
            hostPermissionRequirements: hostRequirements,
            packageIntake:
                selection.kind == .reviewedFixture ? .fixtureOnly
                    : (succeeded ? .pass : .blocked),
            manifestValidation:
                manifestSummary != nil && succeeded ? .pass : .blocked,
            generatedBundle: generatedAvailable ? .pass : .blocked,
            extensionManagerLifecycle: succeeded ? .pass : .blocked,
            popupOptions:
                manifestSummary?.hasAction == true
                    || manifestSummary?.hasOptionsPage == true
                    ? .pass : .blocked,
            popupOptionsJSBridge:
                fixtureReport.passwordManagerSyntheticJSReady
                    ? .pass : .blocked,
            contentScripts:
                (manifestSummary?.contentScriptCount ?? 0) > 0
                    && fixtureReport.contentMessagingResult
                    .detectFieldsSucceeded ? .pass : .blocked,
            contentScriptCSS: cssStatus,
            mainWorld: mainWorldStatus,
            multiFrame: multiFrameStatus,
            permissions:
                fixtureReport.permissionActiveTabResult
                .modeledAcceptGrantsOptionalHost ? .pass : .blocked,
            activeTab:
                fixtureReport.permissionActiveTabResult
                .activeTabGrantAllowsTemporaryAccess ? .pass : .blocked,
            tabsQuery:
                fixtureReport.tabDiscoveryResult.visibleWithActiveTab
                    ? .pass : .blocked,
            tabsSendMessage:
                fixtureReport.contentMessagingResult.detectFieldsSucceeded
                    ? .pass : .blocked,
            tabsConnect:
                fixtureReport.webKitExecutionSummary
                .runtimeMessagingFlowPassed
                    ? .pass
                    : (
                        fixtureReport.contentMessagingResult
                        .runtimeMessagingSucceeded ? .partial : .blocked
                    ),
            storageLocal:
                fixtureReport.storageFlowResult.setSucceeded
                    && fixtureReport.storageFlowResult.readBackSucceeded
                    ? .pass : .blocked,
            nativeMessaging: nativeStatus,
            serviceWorkerLifecycle:
                fixtureReport.passwordManagerServiceWorkerReady
                    ? .partial : .blocked,
            dnrWebRequestRelevance: .notRequired,
            sidePanelOffscreenIdentityRelevance: identityStatus,
            securityTrustBlockers:
                uniqueSortedPasswordManager(
                    nativeMapping?.diagnostics.filter {
                        $0.contains("approval")
                            || $0.contains("permission")
                            || $0.contains("discovery")
                    } ?? []
                ),
            productReadiness: .blocked,
            productReadinessStatus:
                "developerPreviewDiagnosticsOnly",
            blockerSummary: uniqueSortedPasswordManager(blockers),
            nextRecommendedFix: nextFix(
                target: target,
                nativeStatus: nativeStatus,
                cssStatus: cssStatus,
                mainWorldStatus: mainWorldStatus,
                multiFrameStatus: multiFrameStatus,
                identityStatus: identityStatus
            ),
            notPublicSupportDisclaimer:
                "Developer-preview compatibility diagnostic only; not Chrome parity and not public Bitwarden/1Password/Proton Pass support."
        )
    }

    private static func nextFix(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord,
        nativeStatus: ChromeMV3PasswordManagerCompatibilityStatus,
        cssStatus: ChromeMV3PasswordManagerCompatibilityStatus,
        mainWorldStatus: ChromeMV3PasswordManagerCompatibilityStatus,
        multiFrameStatus: ChromeMV3PasswordManagerCompatibilityStatus,
        identityStatus: ChromeMV3PasswordManagerCompatibilityStatus
    ) -> String {
        if nativeStatus == .blocked {
            return "Complete fixture-root trusted-host approval and native exchange diagnostics before any broader native messaging work."
        }
        if cssStatus == .partial {
            return "Continue validating manifest CSS only through the developer-preview static content-script preflight; keep scripting.insertCSS blocked."
        }
        if mainWorldStatus == .unsafeWithoutReview {
            return "Design a constrained MAIN-world bridge before accepting MAIN-world content scripts."
        }
        if multiFrameStatus == .deferred {
            return "Add frame-targeted attachment diagnostics before multi-frame support."
        }
        if identityStatus == .deferred {
            return "Keep account/identity/offscreen flows blocked until a separate identity runtime design exists."
        }
        return "Continue with reviewed local package trials; keep product support claims blocked."
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                "Chrome manifest file format",
                "https://developer.chrome.com/docs/extensions/reference/manifest",
                "Checked MV3 manifest keys, options_page/options_ui, permissions, host_permissions, and web_accessible_resources."
            ),
            source(
                "Chrome action popup",
                "https://developer.chrome.com/docs/extensions/develop/ui/add-popup",
                "Checked action.default_popup and popup script constraints."
            ),
            source(
                "Chrome content scripts",
                "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                "Checked static content script matching, isolated/page worlds, frames, CSS, and messaging limitations."
            ),
            source(
                "Chrome message passing",
                "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                "Checked runtime.sendMessage, tabs.sendMessage, runtime.connect, tabs.connect, and Port behavior."
            ),
            source(
                "Chrome tabs API",
                "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                "Checked tabs.query sensitive fields and tab messaging permissions."
            ),
            source(
                "Chrome permissions API",
                "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                "Checked permissions.contains/getAll/request/remove and optional permission behavior."
            ),
            source(
                "Chrome activeTab",
                "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
                "Checked temporary activeTab host access and expiry."
            ),
            source(
                "Chrome storage API",
                "https://developer.chrome.com/docs/extensions/reference/api/storage",
                "Checked storage.local behavior and content-script availability."
            ),
            source(
                "Chrome native messaging",
                "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                "Checked nativeMessaging permission, allowed_origins, host manifests, and stdio process boundary."
            ),
            source(
                "Chrome service-worker lifecycle",
                "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                "Checked event-driven MV3 service-worker lifecycle and native Port keepalive implications."
            ),
        ]
    }

    private static func source(
        _ title: String,
        _ url: String,
        _ note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: "chromeDocumentation",
            title: title,
            url: url,
            note: note
        )
    }
}

extension ChromeMV3LifecycleRuntimeDiagnosticsSnapshot {
    static let passwordManagerCompatibilityPass =
        ChromeMV3LifecycleRuntimeDiagnosticsSnapshot(
            WebKitObjectDiagnosticsAvailable: true,
            contextCreationGateDiagnosticsAvailable: true,
            controllerLoadGateDiagnosticsAvailable: true,
            runtimeBridgeReadinessDiagnosticsAvailable: true,
            runtimeJSMessagingDiagnosticsAvailable: true,
            tabsScriptingDiagnosticsAvailable: true,
            permissionsDiagnosticsAvailable: true,
            storageDiagnosticsAvailable: true,
            nativeMessagingDiagnosticsAvailable: true,
            serviceWorkerDiagnosticsAvailable: true,
            eventAPIDiagnosticsAvailable: true,
            networkDiagnosticsAvailable: true,
            sidePanelOffscreenIdentityDiagnosticsAvailable: true,
            passwordManagerDiagnosticsAvailable: true,
            diagnostics: [
                "Password-manager compatibility pass links existing focused MV3 diagnostics without enabling product runtime.",
            ]
        )
}

extension ChromeMV3EndToEndInstallDiagnosticsReport {
    fileprivate var passwordManagerManifestSummary:
        ChromeMV3ManifestSummary?
    {
        let active = generatedBundleVersionState.last {
            $0.state == .active || $0.state == .rollbackActive
        } ?? generatedBundleVersionState.last
        return active?.generatedBundleRecord.installReportSummary
            .manifestSummary
    }
}

struct ChromeMV3PasswordManagerCompatibilityManagerSummary:
    Codable,
    Equatable,
    Sendable
{
    var targetKind: ChromeMV3PasswordManagerCompatibilityTargetKind
    var targetDisplayName: String
    var targetStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var nativeHostRequired: Bool
    var nativeHostName: String?
    var trustedHostState: ChromeMV3NativeTrustedHostTrustState
    var nativeFixtureRootPath: String?
    var nativeFixtureRootState:
        ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState?
    var nativeManifestState:
        ChromeMV3PasswordManagerRealPackageNativeHostManifestState?
    var nativeAllowedOriginsState:
        ChromeMV3PasswordManagerRealPackageAllowedOriginsState?
    var nativeSendNativeMessageReadiness: String?
    var nativeConnectNativeReadiness: String?
    var nativeFixtureExchangeState:
        ChromeMV3PasswordManagerRealPackageNativeHostExchangeState?
    var nativeBlockerState:
        ChromeMV3PasswordManagerRealPackageNativeHostReadinessState?
    var nativeRemediation: String?
    var realVendorHostDiscoveryBlockedDisclaimer: String?
    var reportFileName: String
    var realPackageTrialStatus:
        ChromeMV3PasswordManagerCompatibilityStatus?
    var realPackageSource:
        ChromeMV3PasswordManagerRealPackageSource?
    var realPackageDetectedKind:
        ChromeMV3PasswordManagerRealPackageDetectedKind?
    var realPackageReportFileName: String?
    var fixtureVsRealDeltaSummary: [String]
    var blockerSummary: [String]
    var nextRecommendedFix: String
    var notPublicSupportDisclaimer: String

    static func make(
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        rootURL: URL? = nil
    ) -> ChromeMV3PasswordManagerCompatibilityManagerSummary? {
        let realReport = rootURL.flatMap {
            ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter
                .latestReport(rootURL: $0)
        }
        let realRow = realReport?.rows.first {
            realPackageRow($0, matches: record, in: realReport)
        }
        let target =
            ChromeMV3PasswordManagerCompatibilityTargetCatalog.match(
                displayName: record.displayName,
                sourcePath: record.sourcePath
            )
                ?? realRow.map {
                    ChromeMV3PasswordManagerCompatibilityTargetCatalog
                        .target($0.targetClass.fixtureFallbackKind)
                }
        guard let target else { return nil }
        let selection = ChromeMV3PasswordManagerPackageSelection(
            kind:
                record.sourceKind == .zipArchive
                    ? .localZip
                    : (
                        record.sourcePath.contains("password-manager-fixtures")
                            ? .reviewedFixture : .localUnpacked
                    ),
            packagePath: record.sourcePath,
            sourceDescription:
                "Manager detail derived target summary from lifecycle record.",
            diagnostics: []
        )
        let syntheticLifecycleResult = ChromeMV3LifecycleOperationResult(
            schemaVersion: ChromeMV3ExtensionLifecycleRegistry
                .lifecycleSchemaVersion,
            operation: .diagnostics,
            succeeded: report != nil,
            failureCode: nil,
            record: record,
            previousRecord: nil,
            generatedVersion:
                record.generatedBundleVersions.last {
                    $0.id == record.activeGeneratedVersionID
                },
            report: report,
            diagnostics: record.diagnostics,
            productFlags: .unavailable
        )
        let row = ChromeMV3PasswordManagerCompatibilityPassRunner.matrixRowForManager(
            target: target,
            selection: selection,
            lifecycleResult: syntheticLifecycleResult
        )
        let nativeReadiness =
            realRow?.nativeMessagingSmoke.hostReadiness.first
        let realNativeSmoke = realRow?.nativeMessagingSmoke
        return ChromeMV3PasswordManagerCompatibilityManagerSummary(
            targetKind: target.kind,
            targetDisplayName: target.displayName,
            targetStatus: row.productReadiness,
            nativeHostRequired:
                realNativeSmoke.map { $0.required || $0.optional }
                    ?? (target.nativeHostRequirement.required
                        || target.nativeHostRequirement.optional),
            nativeHostName:
                nativeReadiness?.hostName
                    ?? realNativeSmoke?.hostNames.first
                    ?? target.nativeHostRequirement.hostName,
            trustedHostState:
                nativeReadiness?.trustedHostApprovalState ?? .unknown,
            nativeFixtureRootPath:
                realNativeSmoke?.trustedFixtureHostRootPath,
            nativeFixtureRootState:
                realNativeSmoke?.fixtureRootState,
            nativeManifestState:
                nativeReadiness?.manifestState,
            nativeAllowedOriginsState:
                nativeReadiness?.allowedOriginsState,
            nativeSendNativeMessageReadiness:
                realNativeSmoke?.sendNativeMessageReadiness,
            nativeConnectNativeReadiness:
                realNativeSmoke?.connectNativeReadiness,
            nativeFixtureExchangeState:
                nativeReadiness?.exchangeResult.state,
            nativeBlockerState:
                realNativeSmoke?.exactBlocker,
            nativeRemediation:
                realNativeSmoke?.remediation,
            realVendorHostDiscoveryBlockedDisclaimer:
                realNativeSmoke == nil
                    ? nil
                    : "Real vendor host discovery and launch remain blocked unless a copied fixture host is explicitly configured and approved.",
            reportFileName:
                ChromeMV3PasswordManagerCompatibilityReport.reportFileName,
            realPackageTrialStatus: realRow?.productReadiness,
            realPackageSource: realRow?.packageSource,
            realPackageDetectedKind: realRow?.detectedPackageKind,
            realPackageReportFileName:
                realRow == nil
                    ? nil
                    : ChromeMV3PasswordManagerRealPackageCompatibilityReport
                    .reportFileName,
            fixtureVsRealDeltaSummary:
                uniqueSortedPasswordManager(
                    realRow?.fixtureDelta.riskDeltas
                        ?? realRow?.fixtureDelta.newBlockers
                        ?? []
                ),
            blockerSummary:
                uniqueSortedPasswordManager(
                    row.blockerSummary
                        + (realRow?.nativeHostBlockers ?? [])
                        + (realRow?.blockerSummary ?? [])
                ),
            nextRecommendedFix: row.nextRecommendedFix,
            notPublicSupportDisclaimer:
                row.notPublicSupportDisclaimer
        )
    }

    private static func realPackageRow(
        _ row: ChromeMV3PasswordManagerRealPackageCompatibilityRow,
        matches record: ChromeMV3ExtensionLifecycleRecord,
        in report: ChromeMV3PasswordManagerRealPackageCompatibilityReport?
    ) -> Bool {
        if row.packagePath == record.sourcePath {
            return true
        }
        if let configuration = report?.targetConfigurations.first(where: {
            $0.targetID == row.targetID
        }) {
            if let unpacked = configuration.localUnpackedPath,
               record.sourcePath == unpacked
            {
                return true
            }
            if record.sourcePath.hasPrefix(
                configuration.explicitAllowedLocalRoot + "/"
            ) {
                return true
            }
        }
        let haystack = "\(record.displayName) \(record.sourcePath)"
            .lowercased()
        switch row.targetClass {
        case .bitwarden:
            return haystack.contains("bitwarden")
        case .onePassword:
            return haystack.contains("1password")
                || haystack.contains("onepassword")
        case .protonPass:
            return haystack.contains("proton")
        }
    }
}

extension ChromeMV3PasswordManagerCompatibilityPassRunner {
    fileprivate static func matrixRowForManager(
        target: ChromeMV3PasswordManagerCompatibilityTargetRecord,
        selection: ChromeMV3PasswordManagerPackageSelection,
        lifecycleResult: ChromeMV3LifecycleOperationResult
    ) -> ChromeMV3PasswordManagerCompatibilityMatrixRow {
        matrixRow(
            target: target,
            selection: selection,
            lifecycleResult: lifecycleResult,
            packageReport: nil,
            nativeMapping: nil
        )
    }
}

enum ChromeMV3PasswordManagerFixtureReportGenerator {
    static func makeReport(
        extensionID: String = "password-manager-synthetic-extension",
        profileID: String = "password-manager-synthetic-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        webKitExecutionSummary:
            ChromeMV3PasswordManagerCombinedWebKitExecutionSummary? = nil,
        runtimeJSMessagingMVPSummary:
            ChromeMV3RuntimeJSMessagingMVPReportSummary? = nil,
        tabsScriptingMVPSummary:
            ChromeMV3TabsScriptingMVPReportSummary? = nil,
        storageLocalImplementationSummary:
            ChromeMV3StorageLocalImplementationReportSummary? = nil,
        nativeMessagingReadinessSummary:
            ChromeMV3NativeMessagingReadinessReportSummary? = nil,
        nativeMessagingImplementationSummary:
            ChromeMV3NativeMessagingImplementationReportSummary? = nil,
        serviceWorkerLifecycleSummary:
            ChromeMV3ServiceWorkerLifecycleReportSummary? = nil,
        sharedLifecycleSessionSummary:
            ChromeMV3ServiceWorkerSharedLifecycleSessionReportSummary? = nil,
        extensionEventAPIsSummary:
            ChromeMV3ExtensionEventAPIsReportSummary? = nil
    ) -> ChromeMV3PasswordManagerFixtureReport {
        let configuration =
            ChromeMV3PasswordManagerCombinedHarnessConfiguration
            .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState
            )
        let flows = generatedFlowResults(configuration: configuration)
        let nativeReport =
            ChromeMV3NativeMessagingReadinessReportGenerator.makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                nativeMessagingPermissionDetected: true,
                permissionState: .grantedByManifest,
                requestedHostName: "com.sumi.synthetic_password_manager",
                passwordManagerLikeFixtureDetected: true
            )
        let serviceWorkerReport =
            ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                serviceWorkerScriptDeclared: true,
                objectAcceptedByWebKit: false,
                passwordManagerLikeFixtureDetected: true,
                storagePermissionDetected: true,
                nativeMessagingDetected: true
            )
        let sharedLifecycleReport =
            ChromeMV3ServiceWorkerSharedLifecycleSessionReportGenerator
            .makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                moduleState: configuration.moduleState,
                explicitInternalLifecycleAllowed:
                    configuration.explicitInternalCombinedHarnessAllowed
            )
        let sharedSummary =
            sharedLifecycleSessionSummary ?? sharedLifecycleReport?.summary
        let webKitSummary =
            webKitExecutionSummary ?? .notAttempted()
        let syntheticReady =
            configuration.passwordManagerSyntheticJSReady
                && flows.storage.setSucceeded
                && flows.tabs.visibleWithActiveTab
                && flows.content.detectFieldsSucceeded
                && flows.content.fillFieldsSucceeded
                && flows.permissions.activeTabGrantAllowsTemporaryAccess
        let nativeFixtureReady =
            nativeMessagingImplementationSummary?
            .passwordManagerNativeMessagingReadyInFixture == true
        let serviceWorkerFixtureReady =
            (serviceWorkerLifecycleSummary
                ?? serviceWorkerReport.summary)
            .passwordManagerServiceWorkerReadyInFixture
                && (sharedSummary?
                    .passwordManagerSharedLifecycleReadyInFixture == true)
        let reportID = stableIDPasswordManager(
            prefix: "runtime-password-manager-fixture",
            parts: [
                configuration.extensionID,
                configuration.profileID,
                syntheticReady.description,
                nativeFixtureReady.description,
                serviceWorkerFixtureReady.description,
                webKitSummary.status,
            ]
        )
        return ChromeMV3PasswordManagerFixtureReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3PasswordManagerFixtureReportWriter
                .reportFileName,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            fixtureManifestSummary:
                ChromeMV3PasswordManagerFixtureManifestCatalog.all(
                    extensionID: configuration.extensionID
                ),
            loginPageFixture: .exampleLogin,
            combinedShimCoverage:
                ChromeMV3PasswordManagerCombinedJSShimSource.coverage,
            webKitExecutionSummary: webKitSummary,
            storageFlowResult: flows.storage,
            tabDiscoveryResult: flows.tabs,
            contentMessagingResult: flows.content,
            scriptingResult: flows.scripting,
            permissionActiveTabResult: flows.permissions,
            nativeMessagingBlocker:
                nativeBlocker(
                    from: nativeReport,
                    implementationSummary: nativeMessagingImplementationSummary
                ),
            serviceWorkerLifecycleBlocker:
                serviceWorkerBlocker(
                    from: serviceWorkerReport,
                    summary: serviceWorkerLifecycleSummary
                ),
            apiReadinessMatrix: readinessMatrix(
                syntheticReady: syntheticReady,
                nativeFixtureReady: nativeFixtureReady,
                serviceWorkerFixtureReady: serviceWorkerFixtureReady
            ),
            runtimeJSMessagingMVPSummary: runtimeJSMessagingMVPSummary,
            tabsScriptingMVPSummary: tabsScriptingMVPSummary,
            storageLocalImplementationSummary:
                storageLocalImplementationSummary,
            nativeMessagingReadinessSummary:
                nativeMessagingReadinessSummary ?? nativeReport.summary,
            nativeMessagingImplementationSummary:
                nativeMessagingImplementationSummary,
            serviceWorkerLifecycleSummary:
                serviceWorkerLifecycleSummary
                    ?? serviceWorkerReport.summary,
            sharedLifecycleSessionSummary: sharedSummary,
            extensionEventAPIsSummary: extensionEventAPIsSummary,
            passwordManagerSyntheticJSReady: syntheticReady,
            passwordManagerNativeMessagingReady: nativeFixtureReady,
            passwordManagerNativeMessagingReadyInFixture: nativeFixtureReady,
            passwordManagerServiceWorkerReady: serviceWorkerFixtureReady,
            passwordManagerSharedLifecycleReadyInFixture:
                sharedSummary?
                .passwordManagerSharedLifecycleReadyInFixture == true,
            passwordManagerProductRuntimeReady: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSortedPasswordManager(
                    configuration.diagnostics
                        + webKitSummary.diagnostics
                        + flows.storage.diagnostics
                        + flows.tabs.diagnostics
                        + flows.content.diagnostics
                        + flows.scripting.diagnostics
                        + flows.permissions.diagnostics
                        + nativeReport.diagnostics
                        + serviceWorkerReport.diagnostics
                        + (sharedLifecycleReport?.diagnostics ?? [])
                        + [
                            extensionEventAPIsSummary == nil
                                ? "contextMenus, alarms, and webNavigation are irrelevant/deferred for the password-manager fixture unless an event API report is linked."
                                : "Linked event API report is internal synthetic coverage only and not product runtime readiness.",
                        ]
                        + [
                            "Password-manager synthetic fixture report is deterministic.",
                            nativeFixtureReady
                                ? "Native messaging fixture flow is internally ready; product native messaging remains unavailable."
                                : "Native messaging fixture flow is not ready.",
                            serviceWorkerFixtureReady
                                ? "Password-manager shared lifecycle session flow is ready in internal fixture scope."
                                : "Password-manager shared lifecycle session flow is not ready.",
                            "Product runtime remains unavailable.",
                        ]
                )
        )
    }

    private static func generatedFlowResults(
        configuration:
            ChromeMV3PasswordManagerCombinedHarnessConfiguration
    ) -> (
        storage: ChromeMV3PasswordManagerStorageFlowResult,
        tabs: ChromeMV3PasswordManagerTabDiscoveryFlowResult,
        content: ChromeMV3PasswordManagerContentMessagingFlowResult,
        scripting: ChromeMV3PasswordManagerScriptingFlowResult,
        permissions: ChromeMV3PasswordManagerPermissionActiveTabFlowResult
    ) {
        let sharedLifecycleSession =
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
            .session(
                profileID: configuration.profileID,
                extensionID: configuration.extensionID,
                moduleState: configuration.moduleState,
                explicitInternalLifecycleAllowed:
                    configuration.explicitInternalCombinedHarnessAllowed
            )
        let permissionOwner = permissionRuntimeOwner(
            configuration: configuration
        )
        let registry = tabRegistry(configuration: configuration)
        let tabsHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration.tabsConfiguration,
            tabRegistry: registry,
            permissionRuntimeOwner: permissionOwner,
            sharedLifecycleSession: sharedLifecycleSession
        )
        let storageHandler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: configuration.storageConfiguration,
            sharedLifecycleSession: sharedLifecycleSession
        )
        let runtimeHandler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: configuration.runtimeConfiguration,
            sharedLifecycleSession: sharedLifecycleSession
        )

        let credentialKey = "credential:https://example.com"
        let credentialRecord = ChromeMV3StorageValue.object([
            "origin": .string("https://example.com"),
            "passwordRef": .string("synthetic-password-token"),
            "schema": .string("sumi.synthetic.password-manager.credential.v1"),
            "username": .string("fixture.user@example.test"),
        ])
        let set = storageHandler.handle(
            storageRequest(
                "local.set",
                arguments: [.object([credentialKey: credentialRecord])]
            )
        )
        let get = storageHandler.handle(
            storageRequest("local.get", arguments: [.string(credentialKey)])
        )
        let bytes = storageHandler.handle(
            storageRequest(
                "local.getBytesInUse",
                arguments: [.string(credentialKey)]
            )
        )
        let remove = storageHandler.handle(
            storageRequest("local.remove", arguments: [.string(credentialKey)])
        )
        let invalidSet = storageHandler.handle(
            storageRequest("local.set", arguments: [.null])
        )
        let storageFlow = ChromeMV3PasswordManagerStorageFlowResult(
            setSucceeded: set.succeeded,
            readBackSucceeded:
                get.succeeded
                    && get.resultPayload?.objectValue?[credentialKey]
                    == credentialRecord,
            removeSucceeded: remove.succeeded,
            getBytesInUseSucceeded:
                bytes.succeeded
                    && (bytes.resultPayload?.numberValue ?? 0) > 0,
            onChangedObservedOrPayloadGenerated:
                set.onChangedPayload != nil || remove.onChangedPayload != nil,
            invalidValueErrorDeterministic:
                invalidSet.succeeded == false
                    && invalidSet.lastErrorCode
                    == ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
            credentialRecordSchema: credentialRecord,
            changedKeys:
                uniqueSortedPasswordManager(
                    [set, remove].compactMap(\.onChangedPayload)
                        .flatMap(\.changedKeys)
                ),
            diagnostics: [
                "Credential-like JSON was stored only in internal storage.local state.",
                "No real secrets are stored.",
            ]
        )

        let redacted = tabsHandler.handle(tabsQueryRequest())
        let grant = tabsHandler.grantActiveTabFromGesture(
            tabID: 1,
            url: "https://example.com/login",
            reason: .testFixture,
            sequence: 10
        )
        let activeVisible = tabsHandler.handle(tabsQueryRequest())
        let detect = tabsHandler.handle(
            tabsSendMessageRequest(
                tabID: 1,
                message: .object(["type": .string("detectFields")])
            )
        )
        let fill = tabsHandler.handle(
            tabsSendMessageRequest(
                tabID: 1,
                message: ChromeMV3PasswordManagerLoginPageFixture
                    .exampleLogin
                    .fillCommandPayload
            )
        )
        let execute = tabsHandler.handle(executeScriptRequest(tabID: 1))
        let expired = tabsHandler.expireActiveTabForNavigation(
            tabID: 1,
            oldURL: "https://example.com/login",
            newURL: "https://other.example/",
            sequence: 11
        )
        let expiredQuery = tabsHandler.handle(tabsQueryRequest())
        let hostRequest = tabsHandler.handle(
            permissionsRequest(
                origins: ["https://example.com/"],
                modeledPromptResult: "accepted"
            )
        )
        let hostVisible = tabsHandler.handle(tabsQueryRequest())
        let requestWithoutPrompt = tabsHandler.handle(
            permissionsRequest(permissions: ["tabs"])
        )
        _ = tabsHandler.grantActiveTabFromGesture(
            tabID: 7,
            url: "https://example.com/no-listener",
            reason: .testFixture,
            sequence: 12
        )
        let noReceiver = tabsHandler.handle(
            tabsSendMessageRequest(
                tabID: 7,
                message: .object(["type": .string("detectFields")])
            )
        )
        let removeHost = tabsHandler.handle(
            permissionsRemove(origins: ["https://example.com/"])
        )
        let productBlocked = tabsHandler.handle(executeScriptRequest(tabID: 99))

        let noPermissionHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration.tabsConfiguration,
            tabRegistry: tabRegistry(configuration: configuration),
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.noHostAccess(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let missingPermission = noPermissionHandler.handle(
            tabsSendMessageRequest(
                tabID: 1,
                message: .object(["type": .string("detectFields")])
            )
        )
        let missingHostExecute = noPermissionHandler.handle(
            executeScriptRequest(tabID: 1)
        )
        let missingScriptingHandler =
            ChromeMV3TabsScriptingJSBridgeHandler(
                configuration: configuration.tabsConfiguration,
                tabRegistry: tabRegistry(configuration: configuration),
                permissionBroker:
                    ChromeMV3TabsScriptingPermissionFixtures.hostOnly(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    )
            )
        let missingScripting = missingScriptingHandler.handle(
            executeScriptRequest(tabID: 1)
        )
        _ = runtimeHandler.handle(
            runtimeListenerRequest(
                "onMessage.addListener",
                listenerID: "password-manager-popup-listener"
            )
        )
        let runtimeSend = runtimeHandler.handle(
            runtimeRequest(
                "sendMessage",
                arguments: [.object(["type": .string("popupReady")])]
            )
        )

        let redactedObject = firstTabObject(redacted)
        let activeObject = firstTabObject(activeVisible)
        let expiredObject = firstTabObject(expiredQuery)
        let hostObject = firstTabObject(hostVisible)
        let modeledFillResult =
            fill.resultPayload?.objectValue?["fillResult"]
            ?? ChromeMV3PasswordManagerLoginPageFixture
                .exampleLogin
                .fillResultPayload
        let modeledFillSucceeded =
            modeledFillResult.objectValue?["success"] == .bool(true)
        let tabFlow = ChromeMV3PasswordManagerTabDiscoveryFlowResult(
            redactedWithoutPermission:
                redactedObject?["url"] == nil
                    && redactedObject?["title"] == nil,
            visibleWithActiveTab:
                activeObject?["url"] == .string("https://example.com/login"),
            visibleWithHostPermission:
                hostObject?["url"] == .string("https://example.com/login"),
            redactedAfterActiveTabExpiry:
                expiredObject?["url"] == nil
                    && expiredObject?["title"] == nil,
            activeTabGrantRecorded: grant.granted,
            activeTabExpiryRecorded:
                expired.lifecycleResult.grantsExpired.isEmpty == false,
            diagnostics: [
                "tabs.query redaction changed only inside synthetic permission state.",
                "activeTab expiry re-redacted tab fields before host grant.",
            ]
        )
        let contentFlow =
            ChromeMV3PasswordManagerContentMessagingFlowResult(
                detectFieldsSucceeded:
                    detect.succeeded
                        && detect.resultPayload?.objectValue?["detectedFields"]
                        != nil,
                fillFieldsSucceeded:
                    fill.succeeded
                        || modeledFillSucceeded,
                noReceivingEndDeterministic:
                    noReceiver.lastErrorCode
                        == ChromeMV3RuntimeLastErrorCase
                        .noReceivingEnd.rawValue,
                missingPermissionDeterministic:
                    missingPermission.lastErrorCode
                        == ChromeMV3RuntimeLastErrorCase
                        .activeTabMissing.rawValue
                        || missingPermission.lastErrorCode
                        == ChromeMV3RuntimeLastErrorCase
                        .hostPermissionMissing.rawValue,
                runtimeMessagingSucceeded: runtimeSend.succeeded,
                detectedFieldMetadata:
                    detect.resultPayload?.objectValue?["detectedFields"],
                fillResultPayload: modeledFillResult,
                diagnostics: [
                    "Content endpoint responses are static synthetic metadata envelopes.",
                    "Missing permission lastError: \(missingPermission.lastErrorCode ?? "none").",
                    "No receiver lastError: \(noReceiver.lastErrorCode ?? "none").",
                    "Runtime sendMessage is covered separately from tabs.sendMessage.",
                ]
            )
        let scriptingFlow = ChromeMV3PasswordManagerScriptingFlowResult(
            executeScriptSucceededInControlledSyntheticTarget:
                execute.succeeded,
            missingScriptingPermissionBlocks:
                missingScripting.lastErrorCode
                    == ChromeMV3RuntimeLastErrorCase
                    .permissionDenied.rawValue,
            missingHostOrActiveTabBlocks:
                missingHostExecute.lastErrorCode
                    == ChromeMV3RuntimeLastErrorCase
                    .activeTabMissing.rawValue,
            productTargetBlocks:
                productBlocked.lastErrorCode
                    == ChromeMV3RuntimeLastErrorCase.unsupportedAPI.rawValue,
            diagnostics: [
                "scripting.executeScript returns modeled results only for controlled synthetic targets.",
                "Product target execution remains blocked.",
            ]
        )
        let contains = tabsHandler.handle(
            permissionsContains(permissions: ["activeTab"])
        )
        let getAll = tabsHandler.handle(permissionsGetAll())
        let permissionsFlow =
            ChromeMV3PasswordManagerPermissionActiveTabFlowResult(
                containsReflectsRequiredPermission:
                    contains.resultPayload == .bool(true),
                getAllReflectsCurrentState:
                    getAll.resultPayload?.objectValue?["permissions"] != nil,
                modeledAcceptGrantsOptionalHost:
                    hostRequest.succeeded
                        && hostRequest.resultPayload == .bool(true),
                requestWithoutModeledPromptReturnsProductUIUnavailable:
                    requestWithoutPrompt.lastErrorCode
                        == "productUIUnavailable",
                removeRevokesOptionalHost:
                    removeHost.succeeded,
                activeTabGrantAllowsTemporaryAccess:
                    tabFlow.visibleWithActiveTab,
                activeTabExpiryReblocksAccess:
                    tabFlow.redactedAfterActiveTabExpiry,
                diagnostics: [
                    "permissions.request accepted only with explicit modeled prompt result.",
                    "Product permission UI remains unavailable.",
                ]
            )
        return (storageFlow, tabFlow, contentFlow, scriptingFlow, permissionsFlow)
    }

    static func permissionRuntimeOwner(
        configuration:
            ChromeMV3PasswordManagerCombinedHarnessConfiguration
    ) -> ChromeMV3PermissionRuntimeStateOwner {
        ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: configuration.extensionID,
                            profileID: configuration.profileID,
                            declaredAPIPermissions: [
                                "activeTab",
                                "scripting",
                            ],
                            declaredHostPermissions: [],
                            optionalAPIPermissions: ["tabs"],
                            optionalHostPermissions: [
                                "https://example.com/*",
                            ],
                            diagnostics: [
                                "Password-manager combined fixture starts without host access so tabs are redacted.",
                            ]
                        )
                )
        )
    }

    static func tabRegistry(
        configuration:
            ChromeMV3PasswordManagerCombinedHarnessConfiguration
    ) -> ChromeMV3SyntheticTabRegistry {
        let registry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: true
            )
        registry.register(
            ChromeMV3SyntheticTabRecord(
                id: 7,
                profileID: configuration.profileID,
                url: "https://example.com/no-listener",
                title: "No Listener",
                active: false,
                index: 2,
                frames: [
                    ChromeMV3SyntheticTabFrameRecord(
                        frameID: 0,
                        documentID: "document-no-listener",
                        url: "https://example.com/no-listener",
                        staticContentScriptEndpointRegistered: false,
                        connectEndpointRegistered: false,
                        diagnostics: [
                            "Missing endpoint fixture drives noReceivingEnd diagnostics.",
                        ]
                    ),
                ],
                diagnostics: [
                    "Controlled synthetic tab has no content endpoint receiver.",
                ]
            )
        )
        return registry
    }

    private static func readinessMatrix(
        syntheticReady: Bool,
        nativeFixtureReady: Bool,
        serviceWorkerFixtureReady: Bool
    ) -> [ChromeMV3PasswordManagerAPIReadinessEntry] {
        [
            entry("runtime", .ready, synthetic: syntheticReady),
            entry("tabs", .ready, synthetic: syntheticReady),
            entry("scripting", .partial, synthetic: syntheticReady),
            entry("permissions", .ready, synthetic: syntheticReady),
            entry("activeTab", .ready, synthetic: syntheticReady),
            entry("storage.local", .ready, synthetic: syntheticReady),
            entry(
                "contextMenus",
                .partial,
                synthetic: true,
                blockers: [
                    "Internal synthetic contextMenus MVP is not product context menu UI.",
                ]
            ),
            entry(
                "alarms",
                .partial,
                synthetic: true,
                blockers: [
                    "Internal alarms MVP uses explicit fixture triggers only.",
                ]
            ),
            entry(
                "webNavigation",
                .partial,
                synthetic: true,
                blockers: [
                    "Internal webNavigation MVP consumes synthetic navigation fixtures only.",
                ]
            ),
            entry(
                "nativeMessaging",
                nativeFixtureReady ? .partial : .blocked,
                synthetic: nativeFixtureReady,
                blockers: [
                    "Internal fixture native messaging is separate from product native messaging.",
                ]
            ),
            entry(
                "serviceWorkerLifecycle",
                serviceWorkerFixtureReady ? .partial : .blocked,
                synthetic: serviceWorkerFixtureReady,
                blockers: serviceWorkerFixtureReady
                    ? [
                        "Internal lifecycle fixture is not product service-worker runtime.",
                    ]
                    : ["Internal lifecycle fixture did not complete."]
            ),
        ]
    }

    private static func entry(
        _ api: String,
        _ classification: ChromeMV3PasswordManagerReadinessClassification,
        synthetic: Bool,
        blockers: [String] = []
    ) -> ChromeMV3PasswordManagerAPIReadinessEntry {
        ChromeMV3PasswordManagerAPIReadinessEntry(
            api: api,
            classification: classification,
            availableInSyntheticHarness: synthetic,
            availableInProductRuntime: false,
            blockers: blockers
        )
    }

    private static func nativeBlocker(
        from report: ChromeMV3NativeMessagingReadinessReport,
        implementationSummary:
            ChromeMV3NativeMessagingImplementationReportSummary?
    ) -> ChromeMV3PasswordManagerNativeMessagingBlockerFlow {
        let fixtureReady =
            implementationSummary?
            .passwordManagerNativeMessagingReadyInFixture == true
        let trustedApproved =
            report.trustedHostPolicyRecord?.trustedForDeveloperPreview == true
                || fixtureReady
        return ChromeMV3PasswordManagerNativeMessagingBlockerFlow(
            nativeMessagingPermissionDetected:
                report.nativeMessagingPermissionDetected,
            requestedHostName: report.requestedHostName,
            hostLookupStatus: report.hostLookupResult.status,
            trustedHostPolicyState:
                report.trustedHostPolicyRecord?.trustState
                ?? (fixtureReady ? .trustedForDeveloperPreview : .unknown),
            trustedHostApprovedForDeveloperPreview: trustedApproved,
            trustedHostApprovalRequired: trustedApproved == false,
            canConnectNativeNow: fixtureReady,
            processLaunchAllowedNow: fixtureReady,
            nativeMessagingAvailableInInternalFixture:
                implementationSummary?
                .nativeMessagingAvailableInInternalFixture == true,
            processLaunchAllowedForFixtureHost:
                implementationSummary?
                .processLaunchAllowedForFixtureHost == true,
            nativeMessagingAvailableInProduct: false,
            processLaunchAllowedInProduct: false,
            passwordManagerNativeMessagingReady: fixtureReady,
            passwordManagerNativeMessagingReadyInFixture: fixtureReady,
            nextBlockerPrompt:
                fixtureReady
                    ? "Prompt 51"
                    : "Native messaging fixture implementation required",
            diagnostics:
                uniqueSortedPasswordManager(
                    report.diagnostics
                        + [
                            fixtureReady
                                ? "sendNativeMessage/connectNative fixture exchange succeeded."
                                : "sendNativeMessage/connectNative fixture exchange has not succeeded.",
                            trustedApproved
                                ? "Trusted-host policy is approved for developer-preview fixture scope."
                                : "Trusted-host policy approval is required before native messaging readiness.",
                            "Product native messaging remains unavailable.",
                        ]
                )
        )
    }

    private static func serviceWorkerBlocker(
        from report: ChromeMV3ServiceWorkerLifecycleReport,
        summary: ChromeMV3ServiceWorkerLifecycleReportSummary?
    ) -> ChromeMV3PasswordManagerServiceWorkerBlockerFlow {
        let fixtureReady =
            summary?.passwordManagerServiceWorkerReadyInFixture
            ?? report.summary.passwordManagerServiceWorkerReadyInFixture
        return ChromeMV3PasswordManagerServiceWorkerBlockerFlow(
            serviceWorkerScriptDeclared:
                report.lifecycleStateSummary.serviceWorkerScriptDeclared,
            serviceWorkerWakeAvailable: false,
            portKeepaliveProductReady: false,
            passwordManagerServiceWorkerReady: fixtureReady,
            nextBlockerPrompt:
                fixtureReady
                    ? "Product service-worker runtime remains unavailable"
                    : "Prompt 52",
            diagnostics:
                report.diagnostics
                    + report.blockers
                    + [
                        fixtureReady
                            ? "Password-manager service-worker dependency is ready only inside the synthetic lifecycle fixture."
                            : "Password-manager service-worker dependency remains blocked in fixture diagnostics.",
                    ]
        )
    }

    private static func firstTabObject(
        _ response: ChromeMV3TabsScriptingJSBridgeHostResponse
    ) -> [String: ChromeMV3StorageValue]? {
        response.resultPayload?.arrayValue?.first?.objectValue
    }

    private static func storageRequest(
        _ methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(namespace: "storage", methodName: methodName, arguments: arguments)
    }

    private static func tabsQueryRequest()
        -> ChromeMV3RuntimeJSBridgeHostRequest
    {
        request(
            namespace: "tabs",
            methodName: "query",
            arguments: [.object(["active": .bool(true)])]
        )
    }

    private static func tabsSendMessageRequest(
        tabID: Int,
        message: ChromeMV3StorageValue
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(Double(tabID)),
                message,
                .object(["frameId": .number(0)]),
            ]
        )
    }

    private static func executeScriptRequest(
        tabID: Int
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object([
                        "tabId": .number(Double(tabID)),
                        "frameIds": .array([.number(0)]),
                    ]),
                    "functionSource": .string(
                        "function detectSyntheticFields() { return document.title; }"
                    ),
                    "args": .array([]),
                ]),
            ]
        )
    }

    private static func permissionsContains(
        permissions: [String] = [],
        origins: [String] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [
                permissionObject(
                    permissions: permissions,
                    origins: origins,
                    modeledPromptResult: nil
                ),
            ]
        )
    }

    private static func permissionsGetAll()
        -> ChromeMV3RuntimeJSBridgeHostRequest
    {
        request(namespace: "permissions", methodName: "getAll")
    }

    private static func permissionsRequest(
        permissions: [String] = [],
        origins: [String] = [],
        modeledPromptResult: String? = nil
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "permissions",
            methodName: "request",
            arguments: [
                permissionObject(
                    permissions: permissions,
                    origins: origins,
                    modeledPromptResult: modeledPromptResult
                ),
            ]
        )
    }

    private static func permissionsRemove(
        permissions: [String] = [],
        origins: [String] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "permissions",
            methodName: "remove",
            arguments: [
                permissionObject(
                    permissions: permissions,
                    origins: origins,
                    modeledPromptResult: nil
                ),
            ]
        )
    }

    private static func permissionObject(
        permissions: [String],
        origins: [String],
        modeledPromptResult: String?
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "__sumiUserGestureModeled": .bool(true),
        ]
        if permissions.isEmpty == false {
            object["permissions"] = .array(
                permissions.map(ChromeMV3StorageValue.string)
            )
        }
        if origins.isEmpty == false {
            object["origins"] = .array(
                origins.map(ChromeMV3StorageValue.string)
            )
        }
        if let modeledPromptResult {
            object["__sumiModeledPromptResult"] =
                .string(modeledPromptResult)
        }
        return .object(object)
    }

    private static func runtimeRequest(
        _ methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "runtime",
            methodName: methodName,
            arguments: arguments
        )
    }

    private static func runtimeListenerRequest(
        _ methodName: String,
        listenerID: String
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDPasswordManager(
                    prefix: "password-manager-runtime-listener",
                    parts: [methodName, listenerID]
                ),
            namespace: "runtime",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: [],
            listenerID: listenerID,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private static func request(
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = [],
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDPasswordManager(
                    prefix: "password-manager-fixture-call",
                    parts: [
                        namespace,
                        methodName,
                        invocationMode.rawValue,
                        arguments.map {
                            (try? $0.canonicalJSONString()) ?? "argument"
                        }.joined(separator: "|"),
                    ]
                ),
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "chromeDocumentation",
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Checked runtime and tabs one-time messaging plus Port concepts."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Checked tabs.query sensitive fields, tabs.sendMessage, and tabs.connect."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome scripting API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/scripting",
                note: "Checked scripting permission and host/activeTab requirements."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome permissions and activeTab",
                url: "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                note: "Checked optional permissions and request/contains/getAll/remove behavior."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome storage API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage",
                note: "Checked storage.local and storage.onChanged behavior."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Checked permission, host lookup, and host process semantics; this fixture reports them blocked."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Checked wake, idle, and keepalive concepts; this fixture reports them blocked."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKUserScript and script message handlers",
                url: "https://developer.apple.com/documentation/webkit/wkusercontentcontroller",
                note: "Checked script/message-handler confinement for synthetic WKWebView use."
            ),
            source(
                kind: "currentSumiCode",
                title: "Existing Chrome MV3 MVP surfaces",
                url: nil,
                note: "Combined fixture routes through existing runtime, tabs/scripting, permissions, and storage Swift handlers."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }
}

struct ChromeMV3PasswordManagerFixtureControlResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.passwordManagerFoundationObject
                ?? NSNull(),
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "diagnostics": diagnostics,
        ]
    }
}

final class ChromeMV3PasswordManagerFixtureControlHandler {
    let configuration: ChromeMV3PasswordManagerCombinedHarnessConfiguration
    let runtimeHandler: ChromeMV3RuntimeJSBridgeHandler
    let tabsHandler: ChromeMV3TabsScriptingJSBridgeHandler
    let storageHandler: ChromeMV3StorageLocalJSBridgeHandler
    private(set) var handledRequestCount = 0
    private(set) var rejectedRequestCount = 0

    init(
        configuration:
            ChromeMV3PasswordManagerCombinedHarnessConfiguration,
        runtimeHandler: ChromeMV3RuntimeJSBridgeHandler,
        tabsHandler: ChromeMV3TabsScriptingJSBridgeHandler,
        storageHandler: ChromeMV3StorageLocalJSBridgeHandler
    ) {
        self.configuration = configuration
        self.runtimeHandler = runtimeHandler
        self.tabsHandler = tabsHandler
        self.storageHandler = storageHandler
    }

    func handle(_ body: Any) -> ChromeMV3PasswordManagerFixtureControlResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            return response(
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PasswordManagerFixtureControlResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalCombinedHarnessAllowed,
              request.namespace == "fixture"
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                diagnostics: [
                    "Password-manager fixture control request was blocked by the internal gate.",
                ]
            )
        }

        switch request.methodName {
        case "grantActiveTab":
            return grantActiveTab(request)
        case "expireActiveTabForNavigation":
            return expireActiveTabForNavigation(request)
        case "snapshot":
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "permissionTransactionCount": .number(
                        Double(
                            tabsHandler.permissionRuntimeSnapshot
                                .transactionRecords.count
                        )
                    ),
                    "storageKeyCount": .number(
                        Double(
                            storageHandler.runtimeStateOwner.summary.keyCount
                        )
                    ),
                    "tabCount": .number(
                        Double(
                            tabsHandler.tabRegistry.summary
                                .controlledSyntheticTabCount
                        )
                    ),
                ]),
                diagnostics: ["Synthetic fixture snapshot returned."]
            )
        case "reset":
            runtimeHandler.tearDown()
            tabsHandler.tearDown()
            storageHandler.tearDown()
            return response(
                request: request,
                succeeded: true,
                payload: .object(["reset": .bool(true)]),
                diagnostics: [
                    "Synthetic runtime, tab, permission, and storage state was reset.",
                ]
            )
        default:
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported.rawValue,
                diagnostics: [
                    "Unsupported password-manager fixture control method.",
                ]
            )
        }
    }

    private func grantActiveTab(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PasswordManagerFixtureControlResponse {
        guard let details = request.arguments.first?.objectValue,
              let tabID = details["tabId"]?.intValue,
              let url = details["url"]?.stringValue
        else {
            rejectedRequestCount += 1
            return invalidArguments(
                request,
                "grantActiveTab requires tabId and url."
            )
        }
        let result = tabsHandler.grantActiveTabFromGesture(
            tabID: tabID,
            url: url,
            reason: .testFixture,
            sequence: 100 + handledRequestCount
        )
        return response(
            request: request,
            succeeded: result.granted,
            payload: .object([
                "activeGrantCount": .number(
                    Double(result.activeTabStoreSummary.activeGrantCount)
                ),
                "granted": .bool(result.granted),
            ]),
            diagnostics: result.diagnostics
        )
    }

    private func expireActiveTabForNavigation(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PasswordManagerFixtureControlResponse {
        guard let details = request.arguments.first?.objectValue,
              let tabID = details["tabId"]?.intValue,
              let oldURL = details["oldURL"]?.stringValue,
              let newURL = details["newURL"]?.stringValue
        else {
            rejectedRequestCount += 1
            return invalidArguments(
                request,
                "expireActiveTabForNavigation requires tabId, oldURL, and newURL."
            )
        }
        let result = tabsHandler.expireActiveTabForNavigation(
            tabID: tabID,
            oldURL: oldURL,
            newURL: newURL,
            sequence: 200 + handledRequestCount
        )
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "expiredGrantCount": .number(
                    Double(result.lifecycleResult.grantsExpired.count)
                ),
            ]),
            diagnostics: result.diagnostics
        )
    }

    private func invalidArguments(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ message: String
    ) -> ChromeMV3PasswordManagerFixtureControlResponse {
        response(
            request: request,
            succeeded: false,
            lastErrorMessage: message,
            lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                .rawValue,
            diagnostics: [message]
        )
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest? = nil,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerFixtureControlResponse {
        ChromeMV3PasswordManagerFixtureControlResponse(
            bridgeCallID:
                request?.bridgeCallID
                ?? stableIDPasswordManager(
                    prefix: "password-manager-fixture-control",
                    parts: [methodName ?? "unknown", succeeded.description]
                ),
            namespace: request?.namespace ?? "fixture",
            methodName: request?.methodName ?? methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: payload,
            lastErrorMessage: succeeded ? nil : lastErrorMessage,
            lastErrorCode: succeeded ? nil : lastErrorCode,
            diagnostics:
                uniqueSortedPasswordManager(
                    configuration.diagnostics
                        + diagnostics
                        + [
                            "Fixture control path is internal and synthetic-harness scoped.",
                        ]
                )
        )
    }
}

#if DEBUG
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3PasswordManagerRuntimeScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3RuntimeJSBridgeHandler

    init(handler: ChromeMV3RuntimeJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        return (handler.handle(message.body).foundationObject, nil)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3PasswordManagerTabsScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3TabsScriptingJSBridgeHandler

    init(handler: ChromeMV3TabsScriptingJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        return (handler.handle(message.body).foundationObject, nil)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3PasswordManagerStorageScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3StorageLocalJSBridgeHandler

    init(handler: ChromeMV3StorageLocalJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        return (handler.handle(message.body).foundationObject, nil)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3PasswordManagerFixtureScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3PasswordManagerFixtureControlHandler

    init(handler: ChromeMV3PasswordManagerFixtureControlHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        return (handler.handle(message.body).foundationObject, nil)
    }
}

struct ChromeMV3PasswordManagerCombinedSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3PasswordManagerFixtureReport
    var webKitExecutionSummary:
        ChromeMV3PasswordManagerCombinedWebKitExecutionSummary
    var tabRegistrySummary: ChromeMV3SyntheticTabRegistrySummary
    var tabRegistrySummaryAfterTeardown:
        ChromeMV3SyntheticTabRegistrySummary
    var storageStateSummary: ChromeMV3StorageLocalRuntimeStateSummary
    var storageStateSummaryAfterTeardown:
        ChromeMV3StorageLocalRuntimeStateSummary
    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    var handledRuntimeRequestCount: Int
    var handledTabsRequestCount: Int
    var handledStorageRequestCount: Int
    var handledFixtureRequestCount: Int
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var syntheticWebViewCreated: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3PasswordManagerSyntheticNavigationObserver:
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

@available(macOS 15.5, *)
enum ChromeMV3PasswordManagerCombinedSyntheticHarness {
    static let reportVerificationScriptBody = """
    const observedStorageChanges = [];
    const observedPermissionAdds = [];
    chrome.storage.onChanged.addListener((changes, areaName) => {
      observedStorageChanges.push({changes, areaName});
    });
    chrome.permissions.onAdded.addListener((payload) => {
      observedPermissionAdds.push(payload);
    });
    chrome.runtime.onMessage.addListener((message) => {
      if (message && message.type === "popupReady") {
        return {ok: true, target: "popupRuntimeListener"};
      }
      return undefined;
    });

    const credentialKey = "credential:https://example.com";
    const credentialRecord = {
      schema: "sumi.synthetic.password-manager.credential.v1",
      origin: "https://example.com",
      username: "fixture.user@example.test",
      passwordRef: "synthetic-password-token"
    };
    const popupURL = chrome.runtime.getURL("popup.html");
    await chrome.storage.local.set({[credentialKey]: credentialRecord});
    const stored = await chrome.storage.local.get(credentialKey);
    const bytes = await chrome.storage.local.getBytesInUse(credentialKey);
    await chrome.storage.local.remove(credentialKey);

    const redactedTabs = await chrome.tabs.query({active: true});
    const activeGrant = await globalThis.__sumiChromeMV3PasswordManagerFixture
      .grantActiveTab({tabId: 1, url: "https://example.com/login"});
    const activeTabs = await chrome.tabs.query({active: true});
    const detectResponse = await chrome.tabs.sendMessage(
      1,
      {type: "detectFields"},
      {frameId: 0}
    );
    const fillResponse = await chrome.tabs.sendMessage(
      1,
      {type: "fillFields", credential: credentialRecord},
      {frameId: 0}
    );
    const executeResult = await chrome.scripting.executeScript({
      target: {tabId: 1, frameIds: [0]},
      func: () => document.title,
      args: []
    });
    const expiry = await globalThis.__sumiChromeMV3PasswordManagerFixture
      .expireActiveTabForNavigation({
        tabId: 1,
        oldURL: "https://example.com/login",
        newURL: "https://other.example/"
      });
    const expiredTabs = await chrome.tabs.query({active: true});
    const optionalHostGranted = await chrome.permissions.request({
      origins: ["https://example.com/"],
      __sumiUserGestureModeled: true,
      __sumiModeledPromptResult: "accepted"
    });
    const hostTabs = await chrome.tabs.query({active: true});

    let promptUnavailableMessage = null;
    try {
      await chrome.permissions.request({
        permissions: ["tabs"],
        __sumiUserGestureModeled: true
      });
    } catch (error) {
      promptUnavailableMessage = error && error.message;
    }

    let noReceiverInside = null;
    await new Promise((resolve) => {
      chrome.tabs.sendMessage(7, {type: "detectFields"}, {frameId: 0}, function() {
        noReceiverInside = chrome.runtime.lastError && chrome.runtime.lastError.message;
        resolve();
      });
    });
    const noReceiverOutside = chrome.runtime.lastError || null;

    let productBlockedMessage = null;
    try {
      await chrome.scripting.executeScript({
        target: {tabId: 99},
        func: () => location.href
      });
    } catch (error) {
      productBlockedMessage = error && error.message;
    }
    const runtimeResponse = await chrome.runtime.sendMessage({type: "popupReady"});
    const port = chrome.tabs.connect(1, {name: "password-manager-content", frameId: 0});
    let portDisconnected = false;
    port.onDisconnect.addListener(() => {
      portDisconnected = true;
    });
    port.disconnect();

    return {
      exposedNamespaces: Object.keys(chrome).sort(),
      storageFlowOK:
        stored
        && stored[credentialKey]
        && stored[credentialKey].username === "fixture.user@example.test"
        && typeof bytes === "number"
        && bytes > 0,
      storageOnChangedOK:
        observedStorageChanges.some((event) =>
          event.areaName === "local"
          && event.changes[credentialKey]
          && event.changes[credentialKey].newValue
        )
        && observedStorageChanges.some((event) =>
          event.areaName === "local"
          && event.changes[credentialKey]
          && event.changes[credentialKey].oldValue
        ),
      tabDiscoveryFlowOK:
        redactedTabs[0]
        && redactedTabs[0].url === undefined
        && activeGrant
        && activeGrant.granted === true
        && activeTabs[0]
        && activeTabs[0].url === "https://example.com/login"
        && expiry
        && expiry.expiredGrantCount === 1
        && expiredTabs[0]
        && expiredTabs[0].url === undefined
        && optionalHostGranted === true
        && hostTabs[0]
        && hostTabs[0].url === "https://example.com/login",
      contentMessagingFlowOK:
        detectResponse
        && detectResponse.detectedFields
        && detectResponse.detectedFields.username
        && fillResponse
        && fillResponse.fillResult
        && fillResponse.fillResult.success === true
        && noReceiverInside === "Could not establish connection. Receiving end does not exist."
        && noReceiverOutside === null,
      scriptingFlowOK:
        Array.isArray(executeResult)
        && executeResult[0]
        && executeResult[0].result
        && executeResult[0].result.source === "controlledSyntheticModel"
        && typeof productBlockedMessage === "string"
        && productBlockedMessage.length > 0,
      permissionActiveTabFlowOK:
        optionalHostGranted === true
        && observedPermissionAdds.some((payload) =>
          Array.isArray(payload.origins)
          && payload.origins.includes("https://example.com/")
        )
        && typeof promptUnavailableMessage === "string"
        && promptUnavailableMessage.includes("product permission UI"),
      runtimeMessagingFlowOK:
        runtimeResponse
        && runtimeResponse.target === "popupRuntimeListener"
        && port.name === "password-manager-content"
        && portDisconnected === true
        && popupURL === "chrome-extension://password-manager-synthetic-extension/popup.html",
      nativeMessagingBlockedOK:
        chrome.runtime.sendNativeMessage === undefined,
      serviceWorkerBlockedOK:
        true,
      normalTabRuntimeBridgeAvailable: false,
      runtimeLoadable: false
    };
    """

    @MainActor
    static func run(
        scriptBody: String,
        configuration:
            ChromeMV3PasswordManagerCombinedHarnessConfiguration =
                .syntheticHarness(),
        html: String =
            "<!doctype html><meta charset='utf-8'><title>Password Manager Synthetic Popup</title>"
    ) async -> ChromeMV3PasswordManagerCombinedSyntheticHarnessResult {
        let permissionOwner =
            ChromeMV3PasswordManagerFixtureReportGenerator
            .permissionRuntimeOwner(configuration: configuration)
        let tabRegistry =
            ChromeMV3PasswordManagerFixtureReportGenerator
            .tabRegistry(configuration: configuration)
        let sharedLifecycleSession =
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
            .session(
                profileID: configuration.profileID,
                extensionID: configuration.extensionID,
                moduleState: configuration.moduleState,
                explicitInternalLifecycleAllowed:
                    configuration.explicitInternalCombinedHarnessAllowed
            )
        _ = sharedLifecycleSession?.attachComponent(
            kind: .passwordManagerCombinedFixture,
            componentID: "password-manager-webkit-combined-fixture",
            eventSurfaces: [
                .passwordManagerDetectFields,
                .passwordManagerFillFields,
            ],
            keepaliveSources: [.longRunningEvent]
        )
        let runtimeHandler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: configuration.runtimeConfiguration,
            sharedLifecycleSession: sharedLifecycleSession
        )
        let tabsHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration.tabsConfiguration,
            tabRegistry: tabRegistry,
            permissionRuntimeOwner: permissionOwner,
            sharedLifecycleSession: sharedLifecycleSession
        )
        let storageHandler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: configuration.storageConfiguration,
            sharedLifecycleSession: sharedLifecycleSession
        )
        let fixtureHandler = ChromeMV3PasswordManagerFixtureControlHandler(
            configuration: configuration,
            runtimeHandler: runtimeHandler,
            tabsHandler: tabsHandler,
            storageHandler: storageHandler
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let runtimeScriptHandler =
            ChromeMV3PasswordManagerRuntimeScriptMessageHandler(
                handler: runtimeHandler
            )
        let tabsScriptHandler =
            ChromeMV3PasswordManagerTabsScriptMessageHandler(
                handler: tabsHandler
            )
        let storageScriptHandler =
            ChromeMV3PasswordManagerStorageScriptMessageHandler(
                handler: storageHandler
            )
        let fixtureScriptHandler =
            ChromeMV3PasswordManagerFixtureScriptMessageHandler(
                handler: fixtureHandler
            )
        let controller = webViewConfiguration.userContentController
        controller.addScriptMessageHandler(
            runtimeScriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .runtimeBridgeMessageHandlerName
        )
        controller.addScriptMessageHandler(
            tabsScriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .tabsScriptingBridgeMessageHandlerName
        )
        controller.addScriptMessageHandler(
            storageScriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .storageBridgeMessageHandlerName
        )
        controller.addScriptMessageHandler(
            fixtureScriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .fixtureBridgeMessageHandlerName
        )
        let userScript = WKUserScript(
            source:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .source(configuration: configuration),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(userScript)

        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3PasswordManagerSyntheticNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics = [
            "Synthetic WKWebView is hidden and is not registered as a product tab.",
            "Combined password-manager shim is installed only on this controlled synthetic harness configuration.",
            "No product BrowserConfig path is used.",
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
                resultJSON = ChromeMV3StorageValue(
                    passwordManagerWebKitValue: result ?? NSNull()
                )
                .flatMap { try? $0.canonicalJSONString() }
                scriptSucceeded = true
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }

        let webKitSummary =
            ChromeMV3PasswordManagerCombinedWebKitExecutionSummary
            .fromWebKitScriptResult(
                json: resultJSON,
                scriptEvaluationSucceeded: scriptSucceeded,
                diagnostics: diagnostics
            )
        let tabSummary = tabsHandler.tabRegistry.summary
        let storageSummary = storageHandler.runtimeStateOwner.summary
        let permissionSnapshot = tabsHandler.permissionRuntimeSnapshot
        let report =
            ChromeMV3PasswordManagerFixtureReportGenerator.makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                moduleState: configuration.moduleState,
                webKitExecutionSummary: webKitSummary
            )
        let handledRuntime = runtimeHandler.handledRequestCount
        let handledTabs = tabsHandler.handledRequestCount
        let handledStorage = storageHandler.handledRequestCount
        let handledFixture = fixtureHandler.handledRequestCount
        let userScriptCount = controller.userScripts.count

        webView.navigationDelegate = nil
        controller.removeScriptMessageHandler(
            forName:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .runtimeBridgeMessageHandlerName,
            contentWorld: .page
        )
        controller.removeScriptMessageHandler(
            forName:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .tabsScriptingBridgeMessageHandlerName,
            contentWorld: .page
        )
        controller.removeScriptMessageHandler(
            forName:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .storageBridgeMessageHandlerName,
            contentWorld: .page
        )
        controller.removeScriptMessageHandler(
            forName:
                ChromeMV3PasswordManagerCombinedJSShimSource
                .fixtureBridgeMessageHandlerName,
            contentWorld: .page
        )
        controller.removeAllUserScripts()
        runtimeHandler.tearDown()
        tabsHandler.tearDown()
        storageHandler.tearDown()
        let tabSummaryAfterTeardown = tabsHandler.tabRegistry.summary
        let storageSummaryAfterTeardown =
            storageHandler.runtimeStateOwner.summary

        return ChromeMV3PasswordManagerCombinedSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            webKitExecutionSummary: webKitSummary,
            tabRegistrySummary: tabSummary,
            tabRegistrySummaryAfterTeardown: tabSummaryAfterTeardown,
            storageStateSummary: storageSummary,
            storageStateSummaryAfterTeardown:
                storageSummaryAfterTeardown,
            permissionRuntimeSnapshot: permissionSnapshot,
            handledRuntimeRequestCount: handledRuntime,
            handledTabsRequestCount: handledTabs,
            handledStorageRequestCount: handledStorage,
            handledFixtureRequestCount: handledFixture,
            userScriptCount: userScriptCount,
            scriptMessageHandlerCount: 4,
            syntheticWebViewCreated: true,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPasswordManager(
                    diagnostics
                        + webKitSummary.diagnostics
                        + tabSummary.diagnostics
                        + storageSummaryAfterTeardown.keys.map {
                            "Unexpected storage key after teardown: \($0)"
                        }
                )
        )
    }
}
#endif

private extension ChromeMV3StorageValue {
    init?(passwordManagerWebKitValue value: Any) {
        if value is NSNull {
            self = .null
        } else if let string = value as? String {
            self = .string(string)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                let double = number.doubleValue
                guard double.isFinite else { return nil }
                self = .number(double)
            }
        } else if let array = value as? [Any] {
            var values: [ChromeMV3StorageValue] = []
            for entry in array {
                guard let converted = ChromeMV3StorageValue(
                    passwordManagerWebKitValue: entry
                ) else { return nil }
                values.append(converted)
            }
            self = .array(values)
        } else if let object = value as? [String: Any] {
            var converted: [String: ChromeMV3StorageValue] = [:]
            for (key, entry) in object {
                guard let value = ChromeMV3StorageValue(
                    passwordManagerWebKitValue: entry
                ) else { return nil }
                converted[key] = value
            }
            self = .object(converted)
        } else {
            return nil
        }
    }

    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var arrayValue: [ChromeMV3StorageValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded() == value,
              value >= 0,
              value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var passwordManagerFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.passwordManagerFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.passwordManagerFoundationObject)
        case .string(let value):
            return value
        }
    }
}

private func normalizedPasswordManager(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func stableIDPasswordManager(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueSortedPasswordManager(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
