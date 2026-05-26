//
//  ChromeMV3StorageLocalRuntime.swift
//  Sumi
//
//  DEBUG/internal chrome.storage.local runtime MVP for controlled synthetic
//  extension surfaces. This is not product normal-tab runtime support, not
//  storage.sync support, not service-worker wake support, and not Chrome
//  storage parity.
//

import CryptoKit
import Foundation

struct ChromeMV3StorageLocalRuntimeConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var surfaceID: String
    var surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind
    var extensionBaseURLString: String?
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalStorageJSBridgeAllowed: Bool
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInSyntheticHarness: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surfaceKind.sourceContext
    }

    var storageSourceContext: ChromeMV3StorageAPISourceContext {
        sourceContext.storageContext
    }

    static func syntheticHarness(
        extensionID: String = "storage-local-js-mvp-extension",
        profileID: String = "storage-local-js-mvp-profile",
        surfaceID: String = "storage-local-js-mvp-synthetic-surface",
        surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind =
            .extensionPageFixture,
        extensionBaseURLString: String? =
            "chrome-extension://storage-local-js-mvp-extension/",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalStorageJSBridgeAllowed: Bool = true
    ) -> ChromeMV3StorageLocalRuntimeConfiguration {
        let normalizedExtensionID = normalizedStorageLocal(
            extensionID,
            fallback: "storage-local-js-mvp-extension"
        )
        let normalizedProfileID = normalizedStorageLocal(
            profileID,
            fallback: "storage-local-js-mvp-profile"
        )
        let allowed = explicitInternalStorageJSBridgeAllowed
            && moduleState == .enabled
        return ChromeMV3StorageLocalRuntimeConfiguration(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            surfaceID: normalizedStorageLocal(
                surfaceID,
                fallback: "storage-local-synthetic-surface"
            ),
            surfaceKind: surfaceKind,
            extensionBaseURLString: extensionBaseURLString,
            moduleState: moduleState,
            explicitInternalStorageJSBridgeAllowed:
                explicitInternalStorageJSBridgeAllowed,
            storageImplementationAvailableInInternalRuntime: allowed,
            storageJSBridgeAvailableInSyntheticHarness: allowed,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            serviceWorkerLifecycleAvailableInInternalFixture: allowed,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedStorageLocal([
                    "storage.local runtime state is confined to a DEBUG/internal synthetic surface.",
                    "Storage namespace is profile, extension, and area scoped.",
                    "Product storage JS bridge exposure remains unavailable.",
                    "Normal-tab runtime bridge remains unavailable.",
                    "Service-worker wake and native messaging remain unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }
}

struct ChromeMV3StorageLocalRuntimeStateSummary:
    Codable,
    Equatable,
    Sendable
{
    var namespaceID: String
    var profileID: String
    var extensionID: String
    var area: ChromeMV3StorageAreaKind
    var keyCount: Int
    var keys: [String]
    var totalBytes: Int
    var operationRecordCount: Int
    var onChangedPayloadCount: Int
    var profileExtensionAreaIsolated: Bool
    var hostBackedSnapshotAvailable: Bool
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3StorageLocalRuntimeOperationRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var operationID: String
    var methodName: String
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var succeeded: Bool
    var changedKeys: [String]
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var resultPayload: ChromeMV3StorageValue?
    var onChangedPayload:
        ChromeMV3StorageOnChangedEventPayload?
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var diagnostics: [String]
}

struct ChromeMV3StorageLocalRuntimeStateOwnerSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var namespace: ChromeMV3StorageNamespace
    var storageSnapshot: ChromeMV3StorageSnapshot
    var summary: ChromeMV3StorageLocalRuntimeStateSummary
    var operationRecords: [ChromeMV3StorageLocalRuntimeOperationRecord]
    var onChangedPayloads: [ChromeMV3StorageOnChangedEventPayload]
    var diagnostics: [String]
}

final class ChromeMV3StorageLocalRuntimeStateOwner {
    let configuration: ChromeMV3StorageLocalRuntimeConfiguration
    private var broker: ChromeMV3StorageBroker
    private let operationHandler: ChromeMV3StorageAPIOperationHandler
    private let serviceWorkerLifecycleOwner:
        ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner?
    private var operationRecords:
        [ChromeMV3StorageLocalRuntimeOperationRecord] = []
    private var onChangedPayloads: [ChromeMV3StorageOnChangedEventPayload] = []
    private var nextSequence = 0

    init(
        configuration: ChromeMV3StorageLocalRuntimeConfiguration =
            .syntheticHarness(),
        persistenceRootURL: URL? = nil,
        initialValues: [String: ChromeMV3StorageValue] = [:]
    ) {
        self.configuration = configuration
        let namespace = ChromeMV3StorageNamespace(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            area: .local
        )
        self.broker = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode:
                persistenceRootURL.map {
                    .hostBacked(rootURL: $0.standardizedFileURL)
                } ?? .inMemory,
            initialValues: initialValues
        )
        self.operationHandler = ChromeMV3StorageAPIOperationHandler(
            state:
                configuration.moduleState == .enabled
                    && configuration.explicitInternalStorageJSBridgeAllowed
                    ? .enabledModelTestFixture
                    : .disabledModule
        )
        if configuration
            .serviceWorkerLifecycleAvailableInInternalFixture
        {
            let owner = ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner(
                configuration: .internalFixture(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    moduleState: configuration.moduleState,
                    explicitInternalLifecycleAllowed:
                        configuration
                        .explicitInternalStorageJSBridgeAllowed
                )
            )
            owner.registerListener(
                event: .storageOnChanged,
                listenerID: "storage-local-on-changed"
            )
            self.serviceWorkerLifecycleOwner = owner
        } else {
            self.serviceWorkerLifecycleOwner = nil
        }
    }

    var snapshot: ChromeMV3StorageLocalRuntimeStateOwnerSnapshot {
        ChromeMV3StorageLocalRuntimeStateOwnerSnapshot(
            namespace: broker.namespace,
            storageSnapshot: broker.exportSnapshot(),
            summary: summary,
            operationRecords: operationRecords,
            onChangedPayloads: onChangedPayloads,
            diagnostics: uniqueSortedStorageLocal(
                configuration.diagnostics
                    + [
                        "Internal storage.local runtime state is owned by one profile/extension namespace owner.",
                        "No product WebView configuration is touched.",
                        "Product service-worker wake remains unavailable for storage.onChanged.",
                    ]
            )
        )
    }

    var summary: ChromeMV3StorageLocalRuntimeStateSummary {
        let snapshot = broker.exportSnapshot()
        return ChromeMV3StorageLocalRuntimeStateSummary(
            namespaceID: snapshot.namespace.namespaceID,
            profileID: snapshot.namespace.profileID,
            extensionID: snapshot.namespace.extensionID,
            area: snapshot.namespace.area,
            keyCount: snapshot.summary.keyCount,
            keys: snapshot.summary.keys,
            totalBytes: snapshot.summary.totalBytes,
            operationRecordCount: operationRecords.count,
            onChangedPayloadCount: onChangedPayloads.count,
            profileExtensionAreaIsolated: true,
            hostBackedSnapshotAvailable: broker.snapshotURL != nil,
            storageImplementationAvailableInInternalRuntime:
                configuration
                .storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            serviceWorkerLifecycleAvailableInInternalFixture:
                configuration
                .serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            runtimeLoadable: false
        )
    }

    @discardableResult
    func loadHostSnapshotIfPresent(
        fileManager: FileManager = .default
    ) throws -> Bool {
        try broker.loadHostSnapshotIfPresent(fileManager: fileManager)
    }

    func exportSnapshot() -> ChromeMV3StorageSnapshot {
        broker.exportSnapshot()
    }

    func apply(
        _ input: ChromeMV3StorageAPIOperationInput,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        fileManager: FileManager = .default
    ) -> ChromeMV3StorageLocalRuntimeOperationRecord {
        let envelope = operationHandler.handle(
            input,
            broker: &broker,
            fileManager: fileManager
        )
        return record(
            methodName: methodName,
            invocationMode: invocationMode,
            envelope: envelope
        )
    }

    func recordFailure(
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        message: String,
        code: String,
        diagnostics: [String]
    ) -> ChromeMV3StorageLocalRuntimeOperationRecord {
        nextSequence += 1
        let record = ChromeMV3StorageLocalRuntimeOperationRecord(
            sequence: nextSequence,
            operationID:
                stableIDStorageLocal(
                    prefix: "storage-local-runtime-failure",
                    parts: [
                        configuration.profileID,
                        configuration.extensionID,
                        methodName,
                        invocationMode.rawValue,
                        message,
                    ]
                ),
            methodName: methodName,
            invocationMode: invocationMode,
            succeeded: false,
            changedKeys: [],
            lastErrorMessage: message,
            lastErrorCode: code,
            resultPayload: nil,
            onChangedPayload: nil,
            serviceWorkerLifecycleWakeResult: nil,
            diagnostics:
                uniqueSortedStorageLocal(
                    diagnostics
                        + [
                            "Storage bridge request was rejected before broker mutation.",
                        ]
                )
        )
        operationRecords.append(record)
        return record
    }

    func tearDown() {
        broker = ChromeMV3StorageBroker(
            namespace: broker.namespace,
            persistenceMode: .inMemory
        )
        operationRecords.removeAll()
        onChangedPayloads.removeAll()
        nextSequence = 0
        serviceWorkerLifecycleOwner?.tearDownForExtensionDisable()
    }

    private func record(
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageLocalRuntimeOperationRecord {
        nextSequence += 1
        let payload = resultPayload(from: envelope)
        let syntheticOnChanged = syntheticOnChangedPayload(from: envelope)
        let lifecycleWake = serviceWorkerLifecycleWake(
            from: syntheticOnChanged
        )
        if let syntheticOnChanged {
            onChangedPayloads.append(syntheticOnChanged)
        }
        let record = ChromeMV3StorageLocalRuntimeOperationRecord(
            sequence: nextSequence,
            operationID: envelope.operationID,
            methodName: methodName,
            invocationMode: invocationMode,
            succeeded: envelope.succeeded,
            changedKeys: envelope.changedKeys,
            lastErrorMessage:
                envelope.futureLastErrorContract?
                .futureRuntimeLastErrorMessage,
            lastErrorCode:
                envelope.futureLastErrorContract?.code.rawValue,
            resultPayload: payload,
            onChangedPayload: syntheticOnChanged,
            serviceWorkerLifecycleWakeResult: lifecycleWake,
            diagnostics:
                uniqueSortedStorageLocal(
                    envelope.diagnostics
                        + (lifecycleWake?.diagnostics ?? [])
                        + [
                            "storage.local operation was routed through the internal runtime state owner.",
                            "Product storage bridge remains unavailable.",
                        ]
                )
        )
        operationRecords.append(record)
        return record
    }

    private func resultPayload(
        from envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageValue? {
        if envelope.resultPayload.values.isEmpty == false {
            return .object(envelope.resultPayload.values)
        }
        if let bytes = envelope.resultPayload.bytesInUse {
            return .number(Double(bytes))
        }
        return envelope.resultPayload.voidResult ? .null : nil
    }

    private func syntheticOnChangedPayload(
        from envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageOnChangedEventPayload? {
        guard envelope.succeeded,
              let payload = envelope.generatedOnChangedPayload,
              payload.changedKeys.isEmpty == false
        else { return nil }
        return ChromeMV3StorageOnChangedEventPayload(
            areaName: payload.areaName,
            changedKeys: payload.changedKeys,
            changes: payload.changes,
            extensionID: payload.extensionID,
            profileID: payload.profileID,
            wouldDispatchNow: true,
            listenerRegistrationRequired: false,
            serviceWorkerWakeRequired: false,
            blockers: [
                "Synthetic storage.onChanged dispatch is in-page only for the controlled WebKit harness.",
                "Product service-worker wake remains unavailable.",
                "No product normal-tab listener is registered.",
            ],
            serviceWorkerWakePreflight: nil
        )
    }

    private func serviceWorkerLifecycleWake(
        from payload: ChromeMV3StorageOnChangedEventPayload?
    ) -> ChromeMV3ServiceWorkerInternalWakeResult? {
        guard let payload else { return nil }
        return serviceWorkerLifecycleOwner?.requestWake(
            reason: .storageChanged,
            listenerEvent: .storageOnChanged,
            payload: ChromeMV3StorageValue.storageLocalOnChangedPayload(
                payload
            ),
            payloadSummary: "storage.onChanged",
            sourceContext: configuration.sourceContext.runtimeContext
        )
    }
}

struct ChromeMV3StorageLocalJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var runtimeMembers: [String]
    var storageAreas: [String]
    var localMethods: [String]
    var storageEvents: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var unsupportedChromeStorageAreas: [String]
    var unsupportedChromeNamespaces: [String]
}

enum ChromeMV3StorageLocalJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3StorageLocal"

    static var coverage: ChromeMV3StorageLocalJSShimCoverage {
        ChromeMV3StorageLocalJSShimCoverage(
            exposedChromeNamespaces: ["runtime", "storage"],
            runtimeMembers: ["lastError"],
            storageAreas: ["local"],
            localMethods: [
                "clear",
                "get",
                "getBytesInUse",
                "remove",
                "set",
            ],
            storageEvents: ["onChanged"],
            callbackModeSupported: true,
            promiseModeSupported: true,
            lastErrorScopedToCallbackTurn: true,
            unsupportedChromeStorageAreas: ["managed", "session", "sync"],
            unsupportedChromeNamespaces: [
                "nativeMessaging",
                "permissions",
                "scripting",
                "tabs",
            ]
        )
    }

    static func source(
        configuration: ChromeMV3StorageLocalRuntimeConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "sourceContext": configuration.sourceContext.rawValue,
            "extensionBaseURLString":
                configuration.extensionBaseURLString ?? "",
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          const storage = {};
          const local = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;

          function bridgeUnavailableResponse(methodName) {
            return {
              bridgeCallID: "storage-local-js-unavailable",
              namespace: "storage",
              methodName,
              succeeded: false,
              resultPayload: null,
              onChangedPayload: null,
              lastErrorMessage: "storage.local JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["storage.local JS bridge handler is unavailable."]
            };
          }

          function bridgePost(methodName, invocationMode, args) {
            const handler = globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[bridgeName];
            if (!handler || typeof handler.postMessage !== "function") {
              return Promise.resolve(bridgeUnavailableResponse(methodName));
            }
            nextBridgeCallNumber += 1;
            return handler.postMessage({
              namespace: "storage",
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "storage-local-js",
                config.surfaceID,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            });
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

          function rejectFromResponse(response) {
            return Promise.reject(
              new Error(response.lastErrorMessage || "storage.local JS bridge call failed.")
            );
          }

          function makeStorageEvent() {
            const listeners = [];
            const event = {};
            Object.defineProperty(event, "addListener", {
              value(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              enumerable: true
            });
            Object.defineProperty(event, "removeListener", {
              value(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              enumerable: true
            });
            Object.defineProperty(event, "hasListener", {
              value(listener) {
                return listeners.includes(listener);
              },
              enumerable: true
            });
            Object.defineProperty(event, "hasListeners", {
              value() {
                return listeners.length > 0;
              },
              enumerable: true
            });
            Object.defineProperty(event, "__sumiDispatchSynthetic", {
              value(changes, areaName) {
                listeners.slice().forEach((listener) => {
                  listener(changes, areaName);
                });
              },
              enumerable: false
            });
            return Object.freeze(event);
          }

          const onChangedEvent = makeStorageEvent();

          function normalizeOnChangedPayload(payload) {
            if (!payload || payload.areaName !== "local" || !Array.isArray(payload.changes)) {
              return null;
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
            return { changes, areaName: payload.areaName };
          }

          function dispatchSyntheticStorageEvent(response) {
            const payload = normalizeOnChangedPayload(response && response.onChangedPayload);
            if (!payload || Object.keys(payload.changes).length === 0) {
              return;
            }
            onChangedEvent.__sumiDispatchSynthetic(payload.changes, payload.areaName);
          }

          function callbackArgs(methodName, response) {
            if (!response.succeeded) {
              return [];
            }
            if (methodName === "local.get") {
              return [response.resultPayload || {}];
            }
            if (methodName === "local.getBytesInUse") {
              return [Number(response.resultPayload || 0)];
            }
            return [];
          }

          function promiseValue(methodName, response) {
            if (methodName === "local.get") {
              return response.resultPayload || {};
            }
            if (methodName === "local.getBytesInUse") {
              return Number(response.resultPayload || 0);
            }
            return undefined;
          }

          function callbackOrPromise(methodName, args, callback) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = args.map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 storage.local JavaScript arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = bridgePost(methodName, mode, bridgeArgs)
              .then((response) => {
                if (response.succeeded) {
                  dispatchSyntheticStorageEvent(response);
                }
                return response;
              });
            if (callback) {
              promise.then((response) => {
                if (response.succeeded) {
                  invokeCallback(callback, null, callbackArgs(methodName, response));
                } else {
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return promiseValue(methodName, response);
              }
              return rejectFromResponse(response);
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

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(local, "get", {
            value(keys, callback) {
              const parsed = optionalKeysAndCallback(keys, callback);
              const args = parsed.keys === undefined ? [] : [parsed.keys];
              return callbackOrPromise("local.get", args, parsed.callback);
            },
            enumerable: true
          });

          Object.defineProperty(local, "set", {
            value(items, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("local.set", [items], cb);
            },
            enumerable: true
          });

          Object.defineProperty(local, "remove", {
            value(keys, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("local.remove", [keys], cb);
            },
            enumerable: true
          });

          Object.defineProperty(local, "clear", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("local.clear", [], cb);
            },
            enumerable: true
          });

          Object.defineProperty(local, "getBytesInUse", {
            value(keys, callback) {
              const parsed = optionalKeysAndCallback(keys, callback);
              const args = parsed.keys === undefined ? [] : [parsed.keys];
              return callbackOrPromise("local.getBytesInUse", args, parsed.callback);
            },
            enumerable: true
          });

          Object.defineProperty(storage, "local", {
            value: Object.freeze(local),
            enumerable: true
          });
          Object.defineProperty(storage, "onChanged", {
            value: onChangedEvent,
            enumerable: true
          });
          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
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

struct ChromeMV3StorageLocalJSBridgeHostResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var onChangedPayload: ChromeMV3StorageOnChangedEventPayload?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var storageOperationRecord:
        ChromeMV3StorageLocalRuntimeOperationRecord
    var storageStateSummary:
        ChromeMV3StorageLocalRuntimeStateSummary
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInSyntheticHarness: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.storageLocalRuntimeFoundationObject
                ?? NSNull(),
            "onChangedPayload": onChangedPayloadFoundationObject,
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "storageImplementationAvailableInInternalRuntime":
                storageImplementationAvailableInInternalRuntime,
            "storageJSBridgeAvailableInSyntheticHarness":
                storageJSBridgeAvailableInSyntheticHarness,
            "storageJSBridgeAvailableInProduct":
                storageJSBridgeAvailableInProduct,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "serviceWorkerWakeAvailable": serviceWorkerWakeAvailable,
            "serviceWorkerLifecycleAvailableInInternalFixture":
                serviceWorkerLifecycleAvailableInInternalFixture,
            "serviceWorkerWakeAvailableInProduct":
                serviceWorkerWakeAvailableInProduct,
            "serviceWorkerPermanentBackgroundAvailable":
                serviceWorkerPermanentBackgroundAvailable,
            "nativeMessagingAvailable": nativeMessagingAvailable,
            "serviceWorkerLifecycleWakeResult":
                serviceWorkerLifecycleWakeResultFoundationObject,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }

    private var onChangedPayloadFoundationObject: Any {
        guard let onChangedPayload else { return NSNull() }
        return onChangedPayload.storageLocalRuntimeFoundationObject
    }

    private var serviceWorkerLifecycleWakeResultFoundationObject: Any {
        guard let serviceWorkerLifecycleWakeResult,
              let data = try? JSONEncoder().encode(
                serviceWorkerLifecycleWakeResult
              ),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return NSNull() }
        return object
    }
}

final class ChromeMV3StorageLocalJSBridgeHandler {
    let configuration: ChromeMV3StorageLocalRuntimeConfiguration
    let runtimeStateOwner: ChromeMV3StorageLocalRuntimeStateOwner
    private(set) var handledRequestCount = 0
    private(set) var storageOperationRequestCount = 0
    private(set) var rejectedRequestCount = 0

    init(
        configuration: ChromeMV3StorageLocalRuntimeConfiguration =
            .syntheticHarness(),
        runtimeStateOwner: ChromeMV3StorageLocalRuntimeStateOwner? = nil
    ) {
        self.configuration = configuration
        self.runtimeStateOwner =
            runtimeStateOwner
            ?? ChromeMV3StorageLocalRuntimeStateOwner(
                configuration: configuration
            )
    }

    func handle(_ body: Any) -> ChromeMV3StorageLocalJSBridgeHostResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            let record = runtimeStateOwner.recordFailure(
                methodName: "parse",
                invocationMode: .promise,
                message: error.message,
                code: ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                diagnostics: [error.message]
            )
            return response(
                request: nil,
                methodName: "parse",
                succeeded: false,
                record: record,
                lastErrorMessage: error.message,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3StorageLocalJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalStorageJSBridgeAllowed
        else {
            rejectedRequestCount += 1
            let message =
                "storage.local JS bridge request blocked because the extensions module or explicit DEBUG/internal gate is disabled."
            let record = runtimeStateOwner.recordFailure(
                methodName: request.methodName,
                invocationMode: request.invocationMode,
                message: ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                code: ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                diagnostics: [message]
            )
            return response(
                request: request,
                succeeded: false,
                record: record,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                diagnostics: [message]
            )
        }

        guard request.namespace == "storage" else {
            rejectedRequestCount += 1
            return rejected(
                request: request,
                message:
                    ChromeMV3JSBridgeErrorCode.namespaceUnsupported
                    .lastErrorMessage,
                code:
                    ChromeMV3JSBridgeErrorCode.namespaceUnsupported.rawValue,
                diagnostics: [
                    "storage.local JS bridge accepts only the storage namespace.",
                ]
            )
        }

        guard request.methodName.hasPrefix("local.") else {
            rejectedRequestCount += 1
            return rejected(
                request: request,
                message:
                    "Only chrome.storage.local is available in this synthetic storage harness.",
                code: ChromeMV3StorageErrorCode.syncUnavailable.rawValue,
                diagnostics: [
                    "storage.sync, storage.session, and storage.managed are not exposed by the storage.local JS shim.",
                ]
            )
        }

        storageOperationRequestCount += 1
        switch makeOperationInput(from: request) {
        case .failure(let error):
            rejectedRequestCount += 1
            return rejected(
                request: request,
                message: error.message,
                code: error.code,
                diagnostics: error.diagnostics
            )
        case .success(let input):
            let record = runtimeStateOwner.apply(
                input,
                methodName: request.methodName,
                invocationMode: request.invocationMode
            )
            let succeeded = record.succeeded
            return response(
                request: request,
                succeeded: succeeded,
                record: record,
                lastErrorMessage: record.lastErrorMessage,
                lastErrorCode: record.lastErrorCode,
                diagnostics: record.diagnostics
            )
        }
    }

    func tearDown() {
        runtimeStateOwner.tearDown()
    }

    private func makeOperationInput(
        from request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<ChromeMV3StorageAPIOperationInput, BridgeArgumentError> {
        let invocationMode = storageInvocationMode(request.invocationMode)
        let operation: ChromeMV3StorageOperationKind
        switch request.methodName {
        case "local.get":
            operation = .get
            guard request.arguments.count <= 1 else {
                return .failure(extraArgument(request))
            }
            let selector = storageSelector(
                request.arguments.first,
                defaultWhenMissing: .omitted
            )
            if let error = selector.error { return .failure(error) }
            return .success(
                operationInput(
                    operation: operation,
                    invocationMode: invocationMode,
                    keySelector: selector.selector,
                    diagnostics: ["storage.local.get selector normalized."]
                )
            )
        case "local.set":
            operation = .set
            guard request.arguments.count == 1 else {
                return .failure(
                    argumentError(
                        "chrome.storage.local.set requires one object argument."
                    )
                )
            }
            guard case .object(let values) = request.arguments[0] else {
                return .failure(
                    argumentError(
                        "chrome.storage.local.set requires an object of key/value pairs."
                    )
                )
            }
            return .success(
                operationInput(
                    operation: operation,
                    invocationMode: invocationMode,
                    values: values,
                    diagnostics: ["storage.local.set values normalized."]
                )
            )
        case "local.remove":
            operation = .remove
            guard request.arguments.count == 1 else {
                return .failure(
                    argumentError(
                        "chrome.storage.local.remove requires a string key or string array."
                    )
                )
            }
            let selector = storageSelector(
                request.arguments.first,
                defaultWhenMissing: .invalidType("missing")
            )
            if let error = selector.error { return .failure(error) }
            return .success(
                operationInput(
                    operation: operation,
                    invocationMode: invocationMode,
                    keySelector: selector.selector,
                    diagnostics: ["storage.local.remove selector normalized."]
                )
            )
        case "local.clear":
            operation = .clear
            guard request.arguments.isEmpty else {
                return .failure(extraArgument(request))
            }
            return .success(
                operationInput(
                    operation: operation,
                    invocationMode: invocationMode,
                    diagnostics: ["storage.local.clear normalized."]
                )
            )
        case "local.getBytesInUse":
            operation = .getBytesInUse
            guard request.arguments.count <= 1 else {
                return .failure(extraArgument(request))
            }
            let selector = storageSelector(
                request.arguments.first,
                defaultWhenMissing: .omitted
            )
            if let error = selector.error { return .failure(error) }
            return .success(
                operationInput(
                    operation: operation,
                    invocationMode: invocationMode,
                    keySelector: selector.selector,
                    diagnostics: [
                        "storage.local.getBytesInUse selector normalized.",
                    ]
                )
            )
        default:
            return .failure(
                BridgeArgumentError(
                    message:
                        "Unsupported chrome.storage.local bridge method: \(request.methodName).",
                    code: ChromeMV3JSBridgeErrorCode.methodUnsupported
                        .rawValue,
                    diagnostics: [
                        "storage.local bridge accepts get, set, remove, clear, and getBytesInUse only.",
                    ]
                )
            )
        }
    }

    private func operationInput(
        operation: ChromeMV3StorageOperationKind,
        invocationMode: ChromeMV3StorageAPIInvocationMode,
        keySelector: ChromeMV3StorageAPIKeySelector? = nil,
        values: [String: ChromeMV3StorageValue] = [:],
        diagnostics: [String]
    ) -> ChromeMV3StorageAPIOperationInput {
        ChromeMV3StorageAPIOperationInput(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            area: .local,
            operation: operation,
            invocationMode: invocationMode,
            keySelector: keySelector,
            values: values,
            sourceContext: configuration.storageSourceContext,
            diagnostics: diagnostics
        )
    }

    private func storageInvocationMode(
        _ mode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3StorageAPIInvocationMode {
        mode == .callback ? .callback : .promise
    }

    private func storageSelector(
        _ value: ChromeMV3StorageValue?,
        defaultWhenMissing: ChromeMV3StorageAPIKeySelector
    ) -> (
        selector: ChromeMV3StorageAPIKeySelector,
        error: BridgeArgumentError?
    ) {
        guard let value else { return (defaultWhenMissing, nil) }
        switch value {
        case .null:
            return (.allKeys, nil)
        case .string(let key):
            return (.singleString(key), nil)
        case .array(let values):
            var keys: [String] = []
            for (index, entry) in values.enumerated() {
                guard case .string(let key) = entry else {
                    return (
                        .invalidType("array"),
                        argumentError(
                            "Storage key array entry \(index) must be a string."
                        )
                    )
                }
                keys.append(key)
            }
            return (.stringArray(keys), nil)
        case .object(let defaults):
            return (.defaults(defaults), nil)
        case .bool, .number:
            return (
                .invalidType(value.storageLocalRuntimeTypeName),
                argumentError(
                    "Unsupported chrome.storage.local key selector type \(value.storageLocalRuntimeTypeName)."
                )
            )
        }
    }

    private func extraArgument(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> BridgeArgumentError {
        argumentError(
            "Unexpected extra bridge argument for chrome.storage.\(request.methodName)."
        )
    }

    private func argumentError(_ message: String) -> BridgeArgumentError {
        BridgeArgumentError(
            message: message,
            code: ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
            diagnostics: [message]
        )
    }

    private func rejected(
        request: ChromeMV3RuntimeJSBridgeHostRequest,
        message: String,
        code: String,
        diagnostics: [String]
    ) -> ChromeMV3StorageLocalJSBridgeHostResponse {
        let record = runtimeStateOwner.recordFailure(
            methodName: request.methodName,
            invocationMode: request.invocationMode,
            message: message,
            code: code,
            diagnostics: diagnostics
        )
        return response(
            request: request,
            succeeded: false,
            record: record,
            lastErrorMessage: message,
            lastErrorCode: code,
            diagnostics: diagnostics
        )
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        methodName: String? = nil,
        succeeded: Bool,
        record: ChromeMV3StorageLocalRuntimeOperationRecord,
        lastErrorMessage: String?,
        lastErrorCode: String?,
        diagnostics: [String]
    ) -> ChromeMV3StorageLocalJSBridgeHostResponse {
        let invocationMode = request?.invocationMode ?? .promise
        return ChromeMV3StorageLocalJSBridgeHostResponse(
            bridgeCallID:
                request?.bridgeCallID
                ?? stableIDStorageLocal(
                    prefix: "storage-local-js-bridge-call",
                    parts: [methodName ?? "unknown"]
                ),
            namespace: request?.namespace ?? "storage",
            methodName: request?.methodName ?? methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: record.resultPayload,
            onChangedPayload: record.onChangedPayload,
            lastErrorMessage: succeeded ? nil : lastErrorMessage,
            lastErrorCode: succeeded ? nil : lastErrorCode,
            callbackWouldSetLastError:
                invocationMode == .callback && succeeded == false,
            promiseWouldReject:
                invocationMode == .promise && succeeded == false,
            storageOperationRecord: record,
            storageStateSummary: runtimeStateOwner.summary,
            storageImplementationAvailableInInternalRuntime:
                configuration
                .storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInSyntheticHarness:
                configuration.storageJSBridgeAvailableInSyntheticHarness,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            serviceWorkerLifecycleAvailableInInternalFixture:
                configuration
                .serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            serviceWorkerLifecycleWakeResult:
                record.serviceWorkerLifecycleWakeResult,
            diagnostics:
                uniqueSortedStorageLocal(
                    diagnostics
                        + configuration.diagnostics
                        + (record.serviceWorkerLifecycleWakeResult?
                            .diagnostics ?? [])
                        + [
                            "storage.local JS bridge response is synthetic-harness scoped.",
                            "Product storage bridge remains unavailable.",
                            "No service-worker wake or native messaging occurred.",
                        ]
                )
        )
    }
}

private struct BridgeArgumentError: Error, Equatable {
    var message: String
    var code: String
    var diagnostics: [String]
}

struct ChromeMV3StorageLocalOnChangedDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var payloadsGenerated: Int
    var listenerObservationStatus: String
    var syntheticListenerObserved: Bool
    var removeListenerObserved: Bool
    var hasListenerObserved: Bool
    var areaName: String
    var changedKeysObserved: [String]
    var serviceWorkerWakeAvailable: Bool
    var diagnostics: [String]
}

struct ChromeMV3StorageLocalPasswordManagerReadinessStatus:
    Codable,
    Equatable,
    Sendable
{
    var storageLocalInternalRuntimeAvailable: Bool
    var storageLocalJSBridgeAvailableInSyntheticHarness: Bool
    var storageLocalWebKitSyntheticExecutionAvailable: Bool
    var runtimeMessagingMVPAvailable: Bool
    var tabsScriptingMVPAvailable: Bool
    var permissionsMVPAvailable: Bool
    var nativeMessagingAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var passwordManagerStorageReadyForInternalSyntheticSurfaces: Bool
    var passwordManagerProductRuntimeReady: Bool
    var blockers: [String]
}

struct ChromeMV3StorageLocalWebKitExecutionSummary:
    Codable,
    Equatable,
    Sendable
{
    var status: String
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInSyntheticHarness: Bool
    var storageJSExecutedInWebKitSyntheticHarness: Bool
    var getStringCallbackExecuted: Bool
    var getArrayCallbackExecuted: Bool
    var getDefaultsCallbackExecuted: Bool
    var getAllPromiseExecuted: Bool
    var setCallbackExecuted: Bool
    var setPromiseExecuted: Bool
    var removeCallbackExecuted: Bool
    var removePromiseExecuted: Bool
    var clearCallbackExecuted: Bool
    var clearPromiseExecuted: Bool
    var getBytesInUseCallbackExecuted: Bool
    var getBytesInUsePromiseExecuted: Bool
    var invalidKeyLastErrorExecuted: Bool
    var invalidValueLastErrorExecuted: Bool
    var callbackLastErrorScoped: Bool
    var promiseRejectsOnError: Bool
    var onChangedListenerObserved: Bool
    var onChangedRemoveListenerObserved: Bool
    var onChangedHasListenerObserved: Bool
    var storageSyncDeferredOrUnsupported: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    static func notAttempted(
        storageImplementationAvailableInInternalRuntime: Bool,
        storageJSBridgeAvailableInSyntheticHarness: Bool
    ) -> ChromeMV3StorageLocalWebKitExecutionSummary {
        ChromeMV3StorageLocalWebKitExecutionSummary(
            status: "notAttemptedByModelReportGenerator",
            storageImplementationAvailableInInternalRuntime:
                storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInSyntheticHarness:
                storageJSBridgeAvailableInSyntheticHarness,
            storageJSExecutedInWebKitSyntheticHarness: false,
            getStringCallbackExecuted: false,
            getArrayCallbackExecuted: false,
            getDefaultsCallbackExecuted: false,
            getAllPromiseExecuted: false,
            setCallbackExecuted: false,
            setPromiseExecuted: false,
            removeCallbackExecuted: false,
            removePromiseExecuted: false,
            clearCallbackExecuted: false,
            clearPromiseExecuted: false,
            getBytesInUseCallbackExecuted: false,
            getBytesInUsePromiseExecuted: false,
            invalidKeyLastErrorExecuted: false,
            invalidValueLastErrorExecuted: false,
            callbackLastErrorScoped: false,
            promiseRejectsOnError: false,
            onChangedListenerObserved: false,
            onChangedRemoveListenerObserved: false,
            onChangedHasListenerObserved: false,
            storageSyncDeferredOrUnsupported: true,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "WebKit-executed storage.local synthetic harness was not run by this model report generator.",
                "Internal storage state availability is reported separately from WebKit JS execution.",
            ]
        )
    }

    static func fromWebKitScriptResult(
        json: String?,
        scriptEvaluationSucceeded: Bool,
        storageImplementationAvailableInInternalRuntime: Bool,
        storageJSBridgeAvailableInSyntheticHarness: Bool,
        diagnostics: [String]
    ) -> ChromeMV3StorageLocalWebKitExecutionSummary {
        let object = decodedObject(json)
        func bool(_ key: String) -> Bool {
            object?[key] as? Bool ?? false
        }
        return ChromeMV3StorageLocalWebKitExecutionSummary(
            status:
                scriptEvaluationSucceeded
                    ? "executedInWebKitSyntheticHarness"
                    : "blockedOrFailedInWebKitSyntheticHarness",
            storageImplementationAvailableInInternalRuntime:
                storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInSyntheticHarness:
                storageJSBridgeAvailableInSyntheticHarness,
            storageJSExecutedInWebKitSyntheticHarness:
                scriptEvaluationSucceeded,
            getStringCallbackExecuted: bool("getStringCallbackOK"),
            getArrayCallbackExecuted: bool("getArrayCallbackOK"),
            getDefaultsCallbackExecuted: bool("getDefaultsCallbackOK"),
            getAllPromiseExecuted: bool("getAllPromiseOK"),
            setCallbackExecuted: bool("setCallbackOK"),
            setPromiseExecuted: bool("setPromiseOK"),
            removeCallbackExecuted: bool("removeCallbackOK"),
            removePromiseExecuted: bool("removePromiseOK"),
            clearCallbackExecuted: bool("clearCallbackOK"),
            clearPromiseExecuted: bool("clearPromiseOK"),
            getBytesInUseCallbackExecuted:
                bool("getBytesInUseCallbackOK"),
            getBytesInUsePromiseExecuted:
                bool("getBytesInUsePromiseOK"),
            invalidKeyLastErrorExecuted: bool("invalidKeyLastErrorOK"),
            invalidValueLastErrorExecuted:
                bool("invalidValueLastErrorOK"),
            callbackLastErrorScoped: bool("callbackLastErrorScopedOK"),
            promiseRejectsOnError: bool("promiseRejectsOnErrorOK"),
            onChangedListenerObserved: bool("onChangedListenerOK"),
            onChangedRemoveListenerObserved:
                bool("onChangedRemoveListenerOK"),
            onChangedHasListenerObserved: bool("onChangedHasListenerOK"),
            storageSyncDeferredOrUnsupported:
                bool("storageSyncDeferredOrUnsupportedOK"),
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedStorageLocal(
                    diagnostics
                        + [
                            scriptEvaluationSucceeded
                                ? "storage.local JS calls were executed by WebKit in the controlled synthetic harness."
                                : "storage.local WebKit synthetic harness produced a deterministic blocked/failed diagnostic.",
                            "WebKit JS execution status is not inferred from model handler success.",
                        ]
                )
        )
    }

    private static func decodedObject(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8)
        else { return nil }
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return value as? [String: Any]
    }
}

struct ChromeMV3StorageLocalImplementationReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInSyntheticHarness: Bool
    var storageJSExecutedInWebKitSyntheticHarness: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var storageLocalGetAvailableInSyntheticHarness: Bool
    var storageLocalSetAvailableInSyntheticHarness: Bool
    var storageLocalRemoveAvailableInSyntheticHarness: Bool
    var storageLocalClearAvailableInSyntheticHarness: Bool
    var storageLocalGetBytesInUseAvailableInSyntheticHarness: Bool
    var storageOnChangedObservedOrDiagnosed: Bool
    var passwordManagerProductRuntimeReady: Bool
}

struct ChromeMV3StorageLocalImplementationReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var internalStorageStateSnapshot:
        ChromeMV3StorageLocalRuntimeStateOwnerSnapshot
    var operationResults:
        [ChromeMV3StorageLocalJSBridgeHostResponse]
    var shimCoverage: ChromeMV3StorageLocalJSShimCoverage
    var webKitExecutionSummary:
        ChromeMV3StorageLocalWebKitExecutionSummary
    var onChangedDiagnostics:
        ChromeMV3StorageLocalOnChangedDiagnostics
    var quotaErrorDiagnostics:
        [ChromeMV3StorageAPILastErrorContract]
    var storageSyncPolicy: ChromeMV3StorageSyncPolicy
    var passwordManagerStorageReadinessStatus:
        ChromeMV3StorageLocalPasswordManagerReadinessStatus
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInSyntheticHarness: Bool
    var storageJSExecutedInWebKitSyntheticHarness: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3StorageLocalImplementationReportSummary {
        ChromeMV3StorageLocalImplementationReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            storageImplementationAvailableInInternalRuntime:
                storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInSyntheticHarness:
                storageJSBridgeAvailableInSyntheticHarness,
            storageJSExecutedInWebKitSyntheticHarness:
                webKitExecutionSummary
                .storageJSExecutedInWebKitSyntheticHarness,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            storageLocalGetAvailableInSyntheticHarness:
                operationResults.contains {
                    $0.methodName == "local.get" && $0.succeeded
                },
            storageLocalSetAvailableInSyntheticHarness:
                operationResults.contains {
                    $0.methodName == "local.set" && $0.succeeded
                },
            storageLocalRemoveAvailableInSyntheticHarness:
                operationResults.contains {
                    $0.methodName == "local.remove" && $0.succeeded
                },
            storageLocalClearAvailableInSyntheticHarness:
                operationResults.contains {
                    $0.methodName == "local.clear" && $0.succeeded
                },
            storageLocalGetBytesInUseAvailableInSyntheticHarness:
                operationResults.contains {
                    $0.methodName == "local.getBytesInUse"
                        && $0.succeeded
                },
            storageOnChangedObservedOrDiagnosed:
                onChangedDiagnostics.syntheticListenerObserved
                    || onChangedDiagnostics.listenerObservationStatus
                    .isEmpty == false,
            passwordManagerProductRuntimeReady: false
        )
    }
}

enum ChromeMV3StorageLocalImplementationReportWriter {
    static let reportFileName =
        "runtime-storage-local-implementation-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3StorageLocalImplementationReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3StorageLocalImplementationReport {
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

enum ChromeMV3StorageLocalImplementationReportGenerator {
    static func makeReport(
        extensionID: String = "storage-local-js-mvp-extension",
        profileID: String = "storage-local-js-mvp-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        webKitExecutionSummary:
            ChromeMV3StorageLocalWebKitExecutionSummary? = nil,
        runtimeStateSnapshot:
            ChromeMV3StorageLocalRuntimeStateOwnerSnapshot? = nil,
        operationResults:
            [ChromeMV3StorageLocalJSBridgeHostResponse]? = nil
    ) -> ChromeMV3StorageLocalImplementationReport {
        let configuration =
            ChromeMV3StorageLocalRuntimeConfiguration.syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState
            )
        let generated = operationResults ?? generatedOperationResults(
            configuration: configuration
        )
        let snapshot = runtimeStateSnapshot
            ?? generated.last?.storageStateSummary
                .mapToSnapshotFallback(
                    configuration: configuration,
                    operationResults: generated
                )
            ?? ChromeMV3StorageLocalRuntimeStateOwner(
                configuration: configuration
            ).snapshot
        let webKitSummary =
            webKitExecutionSummary
            ?? ChromeMV3StorageLocalWebKitExecutionSummary.notAttempted(
                storageImplementationAvailableInInternalRuntime:
                    configuration
                    .storageImplementationAvailableInInternalRuntime,
                storageJSBridgeAvailableInSyntheticHarness:
                    configuration
                    .storageJSBridgeAvailableInSyntheticHarness
            )
        let onChanged = onChangedDiagnostics(
            operationResults: generated,
            webKitSummary: webKitSummary
        )
        let password = passwordManagerStatus(
            webKitSummary: webKitSummary,
            configuration: configuration
        )
        let reportID = stableIDStorageLocal(
            prefix: "runtime-storage-local-implementation",
            parts: [
                configuration.profileID,
                configuration.extensionID,
                generated.map(\.bridgeCallID).joined(separator: "|"),
                webKitSummary.status,
            ]
        )
        return ChromeMV3StorageLocalImplementationReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3StorageLocalImplementationReportWriter
                .reportFileName,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            internalStorageStateSnapshot: snapshot,
            operationResults: generated,
            shimCoverage: ChromeMV3StorageLocalJSShimSource.coverage,
            webKitExecutionSummary: webKitSummary,
            onChangedDiagnostics: onChanged,
            quotaErrorDiagnostics:
                ChromeMV3StorageAPILastErrorContract.coverage(area: .local)
                .filter {
                    $0.code == .quotaBytesExceeded
                        || $0.code == .quotaBytesPerItemExceeded
                        || $0.code == .maxItemsExceeded
                        || $0.code == .invalidValue
                        || $0.code == .invalidKey
                },
            storageSyncPolicy: ChromeMV3StorageSyncPolicy.conservativeV1,
            passwordManagerStorageReadinessStatus: password,
            storageImplementationAvailableInInternalRuntime:
                configuration
                .storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInSyntheticHarness:
                configuration.storageJSBridgeAvailableInSyntheticHarness,
            storageJSExecutedInWebKitSyntheticHarness:
                webKitSummary.storageJSExecutedInWebKitSyntheticHarness,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSortedStorageLocal(
                    configuration.diagnostics
                        + webKitSummary.diagnostics
                        + generated.flatMap(\.diagnostics)
                        + [
                            "storage.local MVP report separates internal runtime state from product normal-tab runtime.",
                            "storage.sync remains deferred and unsupported as real sync.",
                            "Product normal-tab storage bridge remains unavailable.",
                        ]
                )
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3StorageLocalImplementationReport {
        let rootURL = rootURL.standardizedFileURL
        let prerequisitesURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        let extensionID: String
        if fileManager.fileExists(atPath: prerequisitesURL.path),
           let data = try? Data(contentsOf: prerequisitesURL),
           let prerequisites = try? JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
           )
        {
            extensionID = prerequisites.candidateID
        } else {
            extensionID = "storage-local-js-mvp-extension"
        }
        return makeReport(extensionID: extensionID)
    }

    private static func generatedOperationResults(
        configuration: ChromeMV3StorageLocalRuntimeConfiguration
    ) -> [ChromeMV3StorageLocalJSBridgeHostResponse] {
        let handler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: configuration
        )
        let requests = [
            request(
                "local.set",
                invocationMode: .callback,
                arguments: [
                    .object([
                        "alpha": .string("one"),
                        "nested": .object([
                            "enabled": .bool(true),
                            "items": .array([
                                .string("a"),
                                .number(2),
                                .null,
                            ]),
                        ]),
                    ]),
                ]
            ),
            request(
                "local.get",
                invocationMode: .callback,
                arguments: [.string("alpha")]
            ),
            request(
                "local.get",
                invocationMode: .promise,
                arguments: [
                    .object([
                        "alpha": .string("default"),
                        "missing": .bool(false),
                    ]),
                ]
            ),
            request(
                "local.getBytesInUse",
                invocationMode: .promise,
                arguments: [.array([.string("alpha"), .string("nested")])]
            ),
            request(
                "local.remove",
                invocationMode: .callback,
                arguments: [.string("alpha")]
            ),
            request(
                "local.clear",
                invocationMode: .promise
            ),
            request(
                "local.get",
                invocationMode: .callback,
                arguments: [.number(1)]
            ),
            request(
                "local.set",
                invocationMode: .promise,
                arguments: [.null]
            ),
            request(
                "sync.get",
                invocationMode: .promise
            ),
        ]
        return requests.map { handler.handle($0) }
    }

    private static func onChangedDiagnostics(
        operationResults: [ChromeMV3StorageLocalJSBridgeHostResponse],
        webKitSummary: ChromeMV3StorageLocalWebKitExecutionSummary
    ) -> ChromeMV3StorageLocalOnChangedDiagnostics {
        let payloads = operationResults.compactMap(\.onChangedPayload)
        let changedKeys = payloads.flatMap(\.changedKeys)
        return ChromeMV3StorageLocalOnChangedDiagnostics(
            payloadsGenerated: payloads.count,
            listenerObservationStatus:
                webKitSummary.onChangedListenerObserved
                    ? "observedInWebKitSyntheticHarness"
                    : "payloadGeneratedSyntheticObservationNotAttemptedOrBlocked",
            syntheticListenerObserved:
                webKitSummary.onChangedListenerObserved,
            removeListenerObserved:
                webKitSummary.onChangedRemoveListenerObserved,
            hasListenerObserved:
                webKitSummary.onChangedHasListenerObserved,
            areaName: "local",
            changedKeysObserved: Array(Set(changedKeys)).sorted(),
            serviceWorkerWakeAvailable: false,
            diagnostics: [
                "storage.onChanged payloads are generated for storage.local writes.",
                "Synthetic listener observation is in-page only when the WebKit harness runs.",
                "No service-worker wake is performed.",
            ]
        )
    }

    private static func passwordManagerStatus(
        webKitSummary: ChromeMV3StorageLocalWebKitExecutionSummary,
        configuration: ChromeMV3StorageLocalRuntimeConfiguration
    ) -> ChromeMV3StorageLocalPasswordManagerReadinessStatus {
        let syntheticReady =
            configuration.storageImplementationAvailableInInternalRuntime
                && configuration.storageJSBridgeAvailableInSyntheticHarness
                && (
                    webKitSummary
                    .storageJSExecutedInWebKitSyntheticHarness
                    || webKitSummary.status
                    == "notAttemptedByModelReportGenerator"
                )
        return ChromeMV3StorageLocalPasswordManagerReadinessStatus(
            storageLocalInternalRuntimeAvailable:
                configuration
                .storageImplementationAvailableInInternalRuntime,
            storageLocalJSBridgeAvailableInSyntheticHarness:
                configuration.storageJSBridgeAvailableInSyntheticHarness,
            storageLocalWebKitSyntheticExecutionAvailable:
                webKitSummary.storageJSExecutedInWebKitSyntheticHarness,
            runtimeMessagingMVPAvailable: true,
            tabsScriptingMVPAvailable: true,
            permissionsMVPAvailable: true,
            nativeMessagingAvailable: false,
            serviceWorkerWakeAvailable: false,
            passwordManagerStorageReadyForInternalSyntheticSurfaces:
                syntheticReady,
            passwordManagerProductRuntimeReady: false,
            blockers: [
                "Password-manager product runtime remains blocked because product normal-tab runtime is unavailable.",
                "Service-worker wake remains unavailable.",
                "Native messaging remains unavailable.",
                "storage.sync remains deferred.",
            ]
        )
    }

    private static func request(
        _ methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDStorageLocal(
                    prefix: "storage-local-report-call",
                    parts: [
                        methodName,
                        invocationMode.rawValue,
                        arguments.map {
                            (try? $0.canonicalJSONString()) ?? "argument"
                        }.joined(separator: "|"),
                    ]
                ),
            namespace: "storage",
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
                title: "Chrome storage API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage",
                note: "Defines storage.local, get, set, remove, clear, getBytesInUse, storage.onChanged, quotas, Promise behavior, callback behavior, and runtime.lastError behavior."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome StorageArea",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage/StorageArea",
                note: "Defines StorageArea method signatures and key selector forms."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines callback-scoped runtime.lastError semantics."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKUserContentController",
                url: "https://developer.apple.com/documentation/webkit/wkusercontentcontroller",
                note: "Defines user script and content-world-scoped script message handler registration."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKScriptMessageHandlerWithReply",
                url: "https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply",
                note: "Defines JavaScript postMessage Promise reply behavior."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX WebKit headers",
                url: nil,
                note: "Local headers document WKUserScript, WKScriptMessageHandlerWithReply, WKContentWorld, WKWebViewConfiguration, and callAsyncJavaScript usage confined to the controlled synthetic harness."
            ),
            source(
                kind: "currentSumiCode",
                title: "Sumi Chrome MV3 storage broker and operation handler",
                url: nil,
                note: "Existing broker and operation handler provide deterministic storage.local mutation, quota checks, result envelopes, and onChanged payload generation."
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

#if DEBUG
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3StorageLocalJSScriptMessageHandler:
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
        let response = handler.handle(message.body)
        return (response.foundationObject, nil)
    }
}

struct ChromeMV3StorageLocalJSSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3StorageLocalImplementationReport
    var webKitExecutionSummary:
        ChromeMV3StorageLocalWebKitExecutionSummary
    var storageStateSummary:
        ChromeMV3StorageLocalRuntimeStateSummary
    var storageStateSummaryAfterTeardown:
        ChromeMV3StorageLocalRuntimeStateSummary
    var handledRequestCount: Int
    var storageOperationRequestCount: Int
    var rejectedRequestCount: Int
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var syntheticWebViewCreated: Bool
    var storageImplementationAvailableInInternalRuntime: Bool
    var storageJSBridgeAvailableInSyntheticHarness: Bool
    var storageJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3StorageLocalJSSyntheticNavigationObserver:
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
enum ChromeMV3StorageLocalJSSyntheticHarness {
    static let reportVerificationScriptBody = """
    const exposedNamespaces = Object.keys(chrome).sort();
    const storageKeys = Object.keys(chrome.storage).sort();
    const localKeys = Object.keys(chrome.storage.local).sort();
    const eventKeys = Object.keys(chrome.storage.onChanged).sort();
    const observedChanges = [];
    function observedListener(changes, areaName) {
      observedChanges.push({changes, areaName});
    }
    chrome.storage.onChanged.addListener(observedListener);
    const hasBefore = chrome.storage.onChanged.hasListener(observedListener);

    await chrome.storage.local.set({
      alpha: "one",
      beta: 2,
      nested: {enabled: true, list: ["a", false, null]},
      arrayValue: [1, "two", true, null]
    });

    let getStringCallback = null;
    let getStringLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.storage.local.get("alpha", function(items) {
        getStringCallback = items;
        getStringLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    const getStringLastErrorOutside = chrome.runtime.lastError || null;

    let getArrayCallback = null;
    await new Promise((resolve) => {
      chrome.storage.local.get(["alpha", "beta", "missing"], function(items) {
        getArrayCallback = items;
        resolve();
      });
    });

    let getDefaultsCallback = null;
    await new Promise((resolve) => {
      chrome.storage.local.get({alpha: "default", missingDefault: true}, function(items) {
        getDefaultsCallback = items;
        resolve();
      });
    });

    const getAllPromise = await chrome.storage.local.get(null);
    let bytesCallback = -1;
    await new Promise((resolve) => {
      chrome.storage.local.getBytesInUse(["alpha", "nested"], function(bytes) {
        bytesCallback = bytes;
        resolve();
      });
    });
    const bytesPromise = await chrome.storage.local.getBytesInUse(null);

    let setCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.storage.local.set({callbackKey: "callback"}, function() {
        setCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    await chrome.storage.local.set({promiseKey: {ok: true}});

    let removeCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.storage.local.remove("callbackKey", function() {
        removeCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    await chrome.storage.local.remove(["promiseKey", "missingRemove"]);

    let invalidKeyInside = null;
    let invalidKeyArgCount = -1;
    await new Promise((resolve) => {
      chrome.storage.local.get(7, function() {
        invalidKeyArgCount = arguments.length;
        invalidKeyInside = chrome.runtime.lastError && chrome.runtime.lastError.message;
        resolve();
      });
    });
    const invalidKeyOutside = chrome.runtime.lastError || null;

    let invalidValueInside = null;
    await new Promise((resolve) => {
      chrome.storage.local.set(null, function() {
        invalidValueInside = chrome.runtime.lastError && chrome.runtime.lastError.message;
        resolve();
      });
    });

    let promiseRejectedMessage = null;
    try {
      await chrome.storage.local.remove(null);
    } catch (error) {
      promiseRejectedMessage = error && error.message;
    }

    let clearCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.storage.local.clear(function() {
        clearCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    await chrome.storage.local.set({afterClear: "value"});
    await chrome.storage.local.clear();
    const afterClear = await chrome.storage.local.get(null);

    chrome.storage.onChanged.removeListener(observedListener);
    const hasAfterRemove = chrome.storage.onChanged.hasListener(observedListener);
    await chrome.storage.local.set({notObserved: true});
    const observedCountAfterRemove = observedChanges.length;

    return {
      exposedNamespaces,
      storageKeys,
      localKeys,
      eventKeys,
      tabsMissing: chrome.tabs === undefined,
      permissionsMissing: chrome.permissions === undefined,
      nativeMessagingMissing: chrome.nativeMessaging === undefined,
      storageSyncMissing: chrome.storage.sync === undefined,
      getStringCallback,
      getArrayCallback,
      getDefaultsCallback,
      getAllPromise,
      bytesCallback,
      bytesPromise,
      afterClear,
      observedChanges,
      invalidKeyInside,
      invalidKeyOutside,
      invalidValueInside,
      promiseRejectedMessage,
      getStringCallbackOK:
        getStringCallback
        && getStringCallback.alpha === "one"
        && getStringLastErrorInside === null
        && getStringLastErrorOutside === null,
      getArrayCallbackOK:
        getArrayCallback
        && getArrayCallback.alpha === "one"
        && getArrayCallback.beta === 2
        && !Object.prototype.hasOwnProperty.call(getArrayCallback, "missing"),
      getDefaultsCallbackOK:
        getDefaultsCallback
        && getDefaultsCallback.alpha === "one"
        && getDefaultsCallback.missingDefault === true,
      getAllPromiseOK:
        getAllPromise
        && getAllPromise.alpha === "one"
        && getAllPromise.nested.enabled === true
        && Array.isArray(getAllPromise.arrayValue),
      setCallbackOK: setCallbackLastErrorInside === null,
      setPromiseOK: getAllPromise.alpha === "one",
      removeCallbackOK: removeCallbackLastErrorInside === null,
      removePromiseOK: true,
      clearCallbackOK: clearCallbackLastErrorInside === null,
      clearPromiseOK:
        afterClear && Object.keys(afterClear).length === 0,
      getBytesInUseCallbackOK:
        typeof bytesCallback === "number" && bytesCallback > 0,
      getBytesInUsePromiseOK:
        typeof bytesPromise === "number" && bytesPromise >= bytesCallback,
      invalidKeyLastErrorOK:
        typeof invalidKeyInside === "string"
        && invalidKeyInside.length > 0
        && invalidKeyArgCount === 0,
      invalidValueLastErrorOK:
        typeof invalidValueInside === "string"
        && invalidValueInside.length > 0,
      callbackLastErrorScopedOK:
        typeof invalidKeyInside === "string"
        && invalidKeyInside.length > 0
        && invalidKeyOutside === null,
      promiseRejectsOnErrorOK:
        typeof promiseRejectedMessage === "string"
        && promiseRejectedMessage.length > 0,
      onChangedListenerOK:
        observedChanges.some((event) =>
          event.areaName === "local"
          && event.changes.alpha
          && event.changes.alpha.newValue === "one"
        )
        && observedChanges.some((event) =>
          event.areaName === "local"
          && event.changes.callbackKey
          && event.changes.callbackKey.oldValue === "callback"
        )
        && observedChanges.some((event) =>
          event.areaName === "local"
          && event.changes.afterClear
          && event.changes.afterClear.oldValue === "value"
        ),
      onChangedRemoveListenerOK:
        observedCountAfterRemove === observedChanges.length
        && hasAfterRemove === false,
      onChangedHasListenerOK: hasBefore === true && hasAfterRemove === false,
      storageSyncDeferredOrUnsupportedOK: chrome.storage.sync === undefined
    };
    """

    @MainActor
    static func run(
        scriptBody: String,
        configuration: ChromeMV3StorageLocalRuntimeConfiguration =
            .syntheticHarness(),
        runtimeStateOwner:
            ChromeMV3StorageLocalRuntimeStateOwner? = nil,
        html: String =
            "<!doctype html><meta charset='utf-8'><title>Storage Local JS MVP</title>"
    ) async -> ChromeMV3StorageLocalJSSyntheticHarnessResult {
        let resolvedOwner =
            runtimeStateOwner
            ?? ChromeMV3StorageLocalRuntimeStateOwner(
                configuration: configuration
            )
        let bridgeHandler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: configuration,
            runtimeStateOwner: resolvedOwner
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let scriptHandler = ChromeMV3StorageLocalJSScriptMessageHandler(
            handler: bridgeHandler
        )
        webViewConfiguration.userContentController.addScriptMessageHandler(
            scriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3StorageLocalJSShimSource
                .bridgeMessageHandlerName
        )
        let shimSource = ChromeMV3StorageLocalJSShimSource.source(
            configuration: configuration
        )
        let userScript = WKUserScript(
            source: shimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webViewConfiguration.userContentController.addUserScript(userScript)

        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3StorageLocalJSSyntheticNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics: [String] = [
            "Synthetic WKWebView is hidden and is not registered as a product tab.",
            "storage.local shim is installed as a WKUserScript only on this controlled synthetic harness configuration.",
            "storage.local bridge handler is installed only on the synthetic harness WKUserContentController.",
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
                    storageLocalWebKitValue: result ?? NSNull()
                )
                .flatMap { try? $0.canonicalJSONString() }
                scriptSucceeded = true
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }

        let stateSnapshot = bridgeHandler.runtimeStateOwner.snapshot
        let modelReport = ChromeMV3StorageLocalImplementationReportGenerator
            .makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                moduleState: configuration.moduleState
            )
        let webKitSummary =
            ChromeMV3StorageLocalWebKitExecutionSummary
            .fromWebKitScriptResult(
                json: resultJSON,
                scriptEvaluationSucceeded: scriptSucceeded,
                storageImplementationAvailableInInternalRuntime:
                    configuration
                    .storageImplementationAvailableInInternalRuntime,
                storageJSBridgeAvailableInSyntheticHarness:
                    configuration
                    .storageJSBridgeAvailableInSyntheticHarness,
                diagnostics: diagnostics
            )
        let responses = stateSnapshot.operationRecords.map {
            ChromeMV3StorageLocalJSBridgeHostResponse(
                bridgeCallID: $0.operationID,
                namespace: "storage",
                methodName: $0.methodName,
                succeeded: $0.succeeded,
                resultPayload: $0.resultPayload,
                onChangedPayload: $0.onChangedPayload,
                lastErrorMessage: $0.lastErrorMessage,
                lastErrorCode: $0.lastErrorCode,
                callbackWouldSetLastError:
                    $0.invocationMode == .callback && $0.succeeded == false,
                promiseWouldReject:
                    $0.invocationMode == .promise && $0.succeeded == false,
                storageOperationRecord: $0,
                storageStateSummary: stateSnapshot.summary,
                storageImplementationAvailableInInternalRuntime:
                    configuration
                    .storageImplementationAvailableInInternalRuntime,
                storageJSBridgeAvailableInSyntheticHarness:
                    configuration
                    .storageJSBridgeAvailableInSyntheticHarness,
                storageJSBridgeAvailableInProduct: false,
                normalTabRuntimeBridgeAvailable: false,
                serviceWorkerWakeAvailable: false,
                serviceWorkerLifecycleAvailableInInternalFixture:
                    configuration
                    .serviceWorkerLifecycleAvailableInInternalFixture,
                serviceWorkerWakeAvailableInProduct: false,
                serviceWorkerPermanentBackgroundAvailable: false,
                nativeMessagingAvailable: false,
                runtimeLoadable: false,
                serviceWorkerLifecycleWakeResult:
                    $0.serviceWorkerLifecycleWakeResult,
                diagnostics: $0.diagnostics
            )
        }
        let report =
            ChromeMV3StorageLocalImplementationReportGenerator.makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                moduleState: configuration.moduleState,
                webKitExecutionSummary: webKitSummary,
                runtimeStateSnapshot: stateSnapshot,
                operationResults:
                    responses.isEmpty ? modelReport.operationResults : responses
            )
        let handledRequestCount = bridgeHandler.handledRequestCount
        let storageOperationRequestCount =
            bridgeHandler.storageOperationRequestCount
        let rejectedRequestCount = bridgeHandler.rejectedRequestCount
        let userScriptCount =
            webViewConfiguration.userContentController.userScripts.count
        let summaryBeforeTeardown = bridgeHandler.runtimeStateOwner.summary

        webView.navigationDelegate = nil
        webViewConfiguration.userContentController
            .removeScriptMessageHandler(
                forName:
                    ChromeMV3StorageLocalJSShimSource
                    .bridgeMessageHandlerName,
                contentWorld: .page
            )
        webViewConfiguration.userContentController.removeAllUserScripts()
        bridgeHandler.tearDown()
        let summaryAfterTeardown = bridgeHandler.runtimeStateOwner.summary

        return ChromeMV3StorageLocalJSSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            webKitExecutionSummary: webKitSummary,
            storageStateSummary: summaryBeforeTeardown,
            storageStateSummaryAfterTeardown: summaryAfterTeardown,
            handledRequestCount: handledRequestCount,
            storageOperationRequestCount: storageOperationRequestCount,
            rejectedRequestCount: rejectedRequestCount,
            userScriptCount: userScriptCount,
            scriptMessageHandlerCount: 1,
            syntheticWebViewCreated: true,
            storageImplementationAvailableInInternalRuntime:
                configuration
                .storageImplementationAvailableInInternalRuntime,
            storageJSBridgeAvailableInSyntheticHarness:
                configuration.storageJSBridgeAvailableInSyntheticHarness,
            storageJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedStorageLocal(
                    diagnostics + webKitSummary.diagnostics
                )
        )
    }
}
#endif

private extension ChromeMV3StorageLocalRuntimeStateSummary {
    func mapToSnapshotFallback(
        configuration: ChromeMV3StorageLocalRuntimeConfiguration,
        operationResults: [ChromeMV3StorageLocalJSBridgeHostResponse]
    ) -> ChromeMV3StorageLocalRuntimeStateOwnerSnapshot {
        ChromeMV3StorageLocalRuntimeStateOwnerSnapshot(
            namespace:
                ChromeMV3StorageNamespace(
                    profileID: profileID,
                    extensionID: extensionID,
                    area: .local
                ),
            storageSnapshot:
                ChromeMV3StorageSnapshot(
                    namespace:
                        ChromeMV3StorageNamespace(
                            profileID: profileID,
                            extensionID: extensionID,
                            area: .local
                        )
                ),
            summary: self,
            operationRecords:
                operationResults.map(\.storageOperationRecord),
            onChangedPayloads:
                operationResults.compactMap(\.onChangedPayload),
            diagnostics: configuration.diagnostics
        )
    }
}

private extension ChromeMV3StorageOnChangedEventPayload {
    var storageLocalRuntimeFoundationObject: Any {
        [
            "areaName": areaName,
            "changedKeys": changedKeys,
            "changes":
                changes.map {
                    $0.storageLocalRuntimeFoundationObject
                },
            "extensionID": extensionID,
            "profileID": profileID,
            "wouldDispatchNow": wouldDispatchNow,
            "listenerRegistrationRequired": listenerRegistrationRequired,
            "serviceWorkerWakeRequired": serviceWorkerWakeRequired,
            "blockers": blockers,
        ]
    }
}

private extension ChromeMV3StorageChangeRecord {
    var storageLocalRuntimeFoundationObject: Any {
        var object: [String: Any] = ["key": key]
        if let oldValue {
            object["oldValue"] = oldValue.storageLocalRuntimeFoundationObject
        }
        if let newValue {
            object["newValue"] = newValue.storageLocalRuntimeFoundationObject
        }
        return object
    }
}

private extension ChromeMV3StorageValue {
    static func storageLocalOnChangedPayload(
        _ payload: ChromeMV3StorageOnChangedEventPayload
    ) -> ChromeMV3StorageValue {
        .object([
            "areaName": .string(payload.areaName),
            "changedKeys": .array(
                payload.changedKeys.map(ChromeMV3StorageValue.string)
            ),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
        ])
    }

    init?(storageLocalWebKitValue value: Any) {
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
                    storageLocalWebKitValue: item
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
                    storageLocalWebKitValue: item
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

    var storageLocalRuntimeFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.storageLocalRuntimeFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.storageLocalRuntimeFoundationObject)
        case .string(let value):
            return value
        }
    }

    var storageLocalRuntimeTypeName: String {
        switch self {
        case .array:
            return "array"
        case .bool:
            return "boolean"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object:
            return "object"
        case .string:
            return "string"
        }
    }
}

private func normalizedStorageLocal(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func uniqueSortedStorageLocal(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func stableIDStorageLocal(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}
