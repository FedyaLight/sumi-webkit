//
//  ChromeMV3PermissionsJSMVP.swift
//  Sumi
//
//  DEBUG/internal chrome.permissions JavaScript bridge model for controlled
//  synthetic extension surfaces. This file does not import WebKit, install
//  user scripts, attach to product tabs, show product permission UI, wake
//  service workers, launch native messaging, or make the MV3 runtime loadable.
//

import CryptoKit
import Foundation

struct ChromeMV3PermissionsJSBridgeConfiguration:
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
    var explicitInternalPermissionsJSBridgeAllowed: Bool
    var permissionsJSBridgeAvailableInSyntheticHarness: Bool
    var permissionsJSBridgeAvailableInProduct: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surfaceKind.sourceContext
    }

    static func syntheticHarness(
        extensionID: String = "permissions-js-mvp-extension",
        profileID: String = "permissions-js-mvp-profile",
        surfaceID: String = "permissions-js-mvp-synthetic-surface",
        surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind =
            .extensionPageFixture,
        extensionBaseURLString: String? =
            "chrome-extension://permissions-js-mvp-extension/",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalPermissionsJSBridgeAllowed: Bool = true
    ) -> ChromeMV3PermissionsJSBridgeConfiguration {
        let normalizedExtensionID = normalizedPermissionsJS(
            extensionID,
            fallback: "permissions-js-mvp-extension"
        )
        let normalizedProfileID = normalizedPermissionsJS(
            profileID,
            fallback: "permissions-js-mvp-profile"
        )
        let allowed = explicitInternalPermissionsJSBridgeAllowed
            && moduleState == .enabled
        return ChromeMV3PermissionsJSBridgeConfiguration(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            surfaceID: normalizedPermissionsJS(
                surfaceID,
                fallback: "permissions-js-synthetic-surface"
            ),
            surfaceKind: surfaceKind,
            extensionBaseURLString: extensionBaseURLString,
            moduleState: moduleState,
            explicitInternalPermissionsJSBridgeAllowed:
                explicitInternalPermissionsJSBridgeAllowed,
            permissionsJSBridgeAvailableInSyntheticHarness: allowed,
            permissionsJSBridgeAvailableInProduct: false,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPermissionsJS([
                    "permissions JS bridge is confined to a DEBUG/internal synthetic surface.",
                    "Product permission UI remains unavailable.",
                    "Product normal-tab runtime bridge remains unavailable.",
                    "Service-worker wake and native messaging remain unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }
}

struct ChromeMV3PermissionsJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var runtimeMembers: [String]
    var permissionsMethods: [String]
    var permissionsEvents: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var modeledPromptResultKeys: [String]
    var unsupportedChromeNamespaces: [String]
}

enum ChromeMV3PermissionsJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3Permissions"

    static var coverage: ChromeMV3PermissionsJSShimCoverage {
        ChromeMV3PermissionsJSShimCoverage(
            exposedChromeNamespaces: ["permissions", "runtime"],
            runtimeMembers: ["lastError"],
            permissionsMethods: [
                "contains",
                "getAll",
                "remove",
                "request",
            ],
            permissionsEvents: ["onAdded", "onRemoved"],
            callbackModeSupported: true,
            promiseModeSupported: true,
            lastErrorScopedToCallbackTurn: true,
            modeledPromptResultKeys: [
                "__sumiModeledPromptResult",
                "__sumiUserGestureModeled",
            ],
            unsupportedChromeNamespaces: [
                "nativeMessaging",
                "scripting",
                "storage",
                "tabs",
            ]
        )
    }

    static func source(
        configuration: ChromeMV3PermissionsJSBridgeConfiguration
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
          const permissions = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;

          function bridgeUnavailableResponse(methodName) {
            return {
              bridgeCallID: "permissions-js-unavailable",
              namespace: "permissions",
              methodName,
              succeeded: false,
              resultPayload: null,
              permissionEventPayload: null,
              lastErrorMessage: "permissions JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["permissions JS bridge handler is unavailable."]
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
              namespace: "permissions",
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "permissions-js",
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
              new Error(response.lastErrorMessage || "permissions JS bridge call failed.")
            );
          }

          function makePermissionEvent() {
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
              value(payload) {
                listeners.slice().forEach((listener) => {
                  listener(payload);
                });
              },
              enumerable: false
            });
            return Object.freeze(event);
          }

          const onAddedEvent = makePermissionEvent();
          const onRemovedEvent = makePermissionEvent();

          function normalizedPermissionPayload(rawPayload) {
            if (!rawPayload || typeof rawPayload !== "object") {
              return null;
            }
            return {
              permissions: Array.isArray(rawPayload.permissions)
                ? rawPayload.permissions.slice().sort()
                : [],
              origins: Array.isArray(rawPayload.origins)
                ? rawPayload.origins.slice().sort()
                : []
            };
          }

          function dispatchSyntheticPermissionEvent(response) {
            const rawPayload = response && response.permissionEventPayload;
            const payload = normalizedPermissionPayload(rawPayload);
            if (!payload) {
              return;
            }
            if (rawPayload.eventKind === "onAdded") {
              onAddedEvent.__sumiDispatchSynthetic(payload);
            } else if (rawPayload.eventKind === "onRemoved") {
              onRemovedEvent.__sumiDispatchSynthetic(payload);
            }
          }

          function callbackOrPromise(methodName, args, callback) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = args.map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 JavaScript bridge arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = bridgePost(methodName, mode, bridgeArgs)
              .then((response) => {
                if (response.succeeded) {
                  dispatchSyntheticPermissionEvent(response);
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
              return rejectFromResponse(response);
            });
          }

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "contains", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("contains", [permissionsObject || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "getAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("getAll", [], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "request", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("request", [permissionsObject || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "remove", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("remove", [permissionsObject || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "onAdded", {
            value: onAddedEvent,
            enumerable: true
          });
          Object.defineProperty(permissions, "onRemoved", {
            value: onRemovedEvent,
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

struct ChromeMV3PermissionsJSBridgeHostResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var permissionEventPayload: ChromeMV3PermissionsAPIEventPayload?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var permissionsContainsResult:
        ChromeMV3PermissionsAPIContainsResult?
    var permissionsGetAllResult:
        ChromeMV3PermissionsAPIGetAllResult?
    var permissionsRequestResult:
        ChromeMV3PermissionsAPIRequestResult?
    var permissionsRemoveResult:
        ChromeMV3PermissionsAPIRemoveResult?
    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    var permissionsJSBridgeAvailableInSyntheticHarness: Bool
    var permissionsJSBridgeAvailableInProduct: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.permissionsJSFoundationObject ?? NSNull(),
            "permissionEventPayload":
                permissionEventPayloadFoundationObject,
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "permissionRuntimeStateAvailable": true,
            "permissionsJSBridgeAvailableInSyntheticHarness":
                permissionsJSBridgeAvailableInSyntheticHarness,
            "permissionsJSBridgeAvailableInProduct":
                permissionsJSBridgeAvailableInProduct,
            "permissionUIAvailableInProduct":
                permissionUIAvailableInProduct,
            "activeTabAvailableInProduct": activeTabAvailableInProduct,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "serviceWorkerWakeAvailable": serviceWorkerWakeAvailable,
            "nativeMessagingAvailable": nativeMessagingAvailable,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }

    private var permissionEventPayloadFoundationObject: Any {
        guard let permissionEventPayload else { return NSNull() }
        return ChromeMV3StorageValue.permissionsJSEventPayload(
            permissionEventPayload
        ).permissionsJSFoundationObject
    }
}

final class ChromeMV3PermissionsJSBridgeHandler {
    let configuration: ChromeMV3PermissionsJSBridgeConfiguration
    private var permissionRuntimeOwner:
        ChromeMV3PermissionRuntimeStateOwner
    private(set) var handledRequestCount = 0
    private(set) var permissionsRequestCount = 0
    private(set) var rejectedRequestCount = 0

    init(
        configuration: ChromeMV3PermissionsJSBridgeConfiguration,
        permissionRuntimeOwner:
            ChromeMV3PermissionRuntimeStateOwner? = nil
    ) {
        self.configuration = configuration
        self.permissionRuntimeOwner =
            permissionRuntimeOwner
            ?? ChromeMV3PermissionsJSBridgeHandler
            .defaultPermissionRuntimeOwner(configuration: configuration)
    }

    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    {
        permissionRuntimeOwner.snapshot
    }

    func handle(_ body: Any) -> ChromeMV3PermissionsJSBridgeHostResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            return response(
                request: nil,
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                    .rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalPermissionsJSBridgeAllowed
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .rawValue,
                diagnostics: [
                    "permissions JS bridge request blocked because the extensions module or explicit DEBUG/internal gate is disabled.",
                ]
            )
        }

        guard request.namespace == "permissions" else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.namespaceUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.namespaceUnsupported.rawValue,
                diagnostics: [
                    "Unsupported permissions JS bridge namespace: \(request.namespace).",
                ]
            )
        }

        switch request.methodName {
        case "contains":
            return permissionsContains(request)
        case "getAll":
            return permissionsGetAll(request)
        case "request":
            return permissionsRequest(request)
        case "remove":
            return permissionsRemove(request)
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
                    "Unsupported permissions JS bridge method: \(request.methodName).",
                ]
            )
        }
    }

    func tearDown() {
        permissionRuntimeOwner =
            Self.defaultPermissionRuntimeOwner(configuration: configuration)
    }

    private func permissionsContains(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
        permissionsRequestCount += 1
        switch permissionsInput(request, requiresObjectArgument: true) {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            let result = permissionRuntimeOwner.contains(input: input)
            return response(
                request: request,
                succeeded: true,
                payload: .bool(result.wouldReturn),
                permissionsContainsResult: result,
                diagnostics: result.diagnostics
            )
        }
    }

    private func permissionsGetAll(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
        permissionsRequestCount += 1
        guard request.arguments.isEmpty else {
            rejectedRequestCount += 1
            return invalidArguments(
                request,
                "permissions.getAll does not accept arguments."
            )
        }
        let result = permissionRuntimeOwner.getAll()
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "permissions": .array(
                    result.permissions.map(ChromeMV3StorageValue.string)
                ),
                "origins": .array(
                    result.origins.map(ChromeMV3StorageValue.string)
                ),
            ]),
            permissionsGetAllResult: result,
            diagnostics: result.diagnostics
        )
    }

    private func permissionsRequest(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
        permissionsRequestCount += 1
        switch permissionsInput(request, requiresObjectArgument: true) {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            let promptResult = modeledPromptResult(
                from: request.arguments.first
            )
            let application = permissionRuntimeOwner.request(
                input: input,
                modeledPromptResult: promptResult
            )
            let allowedByPromptModel =
                application.result.wouldGrantIfUserAccepted
                    && (promptResult == .accepted || promptResult == .denied)
            let alreadyGranted = application.result.wouldBeAllowedByModel
            let success = alreadyGranted || allowedByPromptModel
            if success {
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(application.returnedBoolean),
                    permissionEventPayload:
                        promptResult == .accepted
                            ? application.result.eventPayloadIfAccepted
                            : nil,
                    permissionsRequestResult: application.result,
                    diagnostics: application.diagnostics
                )
            }
            rejectedRequestCount += 1
            let failure = requestFailure(for: application.result)
            return response(
                request: request,
                succeeded: false,
                payload: .bool(false),
                lastErrorMessage: failure.message,
                lastErrorCode: failure.code,
                permissionsRequestResult: application.result,
                diagnostics:
                    uniqueSortedPermissionsJS(
                        application.diagnostics + failure.diagnostics
                    )
            )
        }
    }

    private func permissionsRemove(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
        permissionsRequestCount += 1
        switch permissionsInput(request, requiresObjectArgument: true) {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            let application = permissionRuntimeOwner.remove(input: input)
            if application.returnedBoolean {
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(true),
                    permissionEventPayload:
                        application.result.eventPayloadIfApplied,
                    permissionsRemoveResult: application.result,
                    diagnostics: application.diagnostics
                )
            }
            rejectedRequestCount += 1
            let failure = removeFailure(for: application.result)
            return response(
                request: request,
                succeeded: false,
                payload: .bool(false),
                lastErrorMessage: failure.message,
                lastErrorCode: failure.code,
                permissionsRemoveResult: application.result,
                diagnostics:
                    uniqueSortedPermissionsJS(
                        application.diagnostics + failure.diagnostics
                    )
            )
        }
    }

    private func permissionsInput(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        requiresObjectArgument: Bool
    ) -> Result<
        ChromeMV3PermissionsAPIRequestInput,
        ChromeMV3PermissionsJSArgumentError
    > {
        if requiresObjectArgument {
            guard request.arguments.count == 1 else {
                return argumentFailure(
                    "permissions.\(request.methodName) requires one permissions object."
                )
            }
        }
        let object = request.arguments.first?.objectValue
        if requiresObjectArgument, object == nil {
            return argumentFailure(
                "permissions.\(request.methodName) argument must be an object."
            )
        }
        let permissions = stringArray(
            object?["permissions"],
            fieldName: "permissions"
        )
        if let message = permissions.error {
            return argumentFailure(message)
        }
        let origins = stringArray(object?["origins"], fieldName: "origins")
        if let message = origins.error {
            return argumentFailure(message)
        }
        return .success(
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                sourceContext:
                    configuration.sourceContext.permissionsContext,
                userGestureModeled:
                    object?["__sumiUserGestureModeled"]?.boolValue
                    ?? (configuration.sourceContext == .actionPopup),
                extensionModuleEnabled:
                    configuration.moduleState == .enabled,
                permissions: permissions.values,
                origins: origins.values
            )
        )
    }

    private func stringArray(
        _ value: ChromeMV3StorageValue?,
        fieldName: String
    ) -> (values: [String], error: String?) {
        guard let value else { return ([], nil) }
        guard case .array(let entries) = value else {
            return ([], "\(fieldName) must be a string array.")
        }
        var values: [String] = []
        for entry in entries {
            guard let string = entry.stringValue else {
                return ([], "\(fieldName) entries must be strings.")
            }
            values.append(string)
        }
        return (Array(Set(values)).sorted(), nil)
    }

    private func modeledPromptResult(
        from value: ChromeMV3StorageValue?
    ) -> ChromeMV3ModeledPermissionPromptResult {
        guard let object = value?.objectValue,
              let result = object["__sumiModeledPromptResult"]
        else { return .notProvided }
        if let bool = result.boolValue {
            return bool ? .accepted : .denied
        }
        switch result.stringValue?.lowercased() {
        case "accept", "accepted", "grant", "granted", "allow", "allowed":
            return .accepted
        case "deny", "denied", "reject", "rejected", "block", "blocked":
            return .denied
        default:
            return .notProvided
        }
    }

    private func requestFailure(
        for result: ChromeMV3PermissionsAPIRequestResult
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions
            .map(\.classification)
        if result.wouldRequirePrompt {
            return (
                "productUIUnavailable",
                "Permission promptRequired, but product permission UI is unavailable in the internal synthetic harness.",
                [
                    "Request requires a permission prompt.",
                    "permissionUIAvailableInProduct remains false.",
                    "Provide an explicit modeled prompt result in internal tests.",
                ]
            )
        }
        if classifications.contains(.missingUserGesture) {
            return (
                "promptRequiredUserGestureMissing",
                "chrome.permissions.request requires a modeled user gesture before prompting.",
                ["Request was blocked because no modeled user gesture was supplied."]
            )
        }
        if classifications.contains(.notDeclaredOptional) {
            return (
                "permissionNotDeclaredOptional",
                "Requested permission or origin is not declared optional.",
                ["Only declared optional permissions can be granted by this synthetic bridge."]
            )
        }
        if classifications.contains(.unsupportedPermission) {
            return (
                "unsupportedPermission",
                "Requested permission or origin is unsupported by the modeled contract.",
                ["Unsupported permission request was rejected deterministically."]
            )
        }
        if classifications.contains(.deniedByPolicy) {
            return (
                "permissionDenied",
                "Requested permission is denied by the internal permission state.",
                ["Denied permission request was rejected deterministically."]
            )
        }
        return (
            "permissionRequestRejected",
            "chrome.permissions.request was rejected by internal permission state.",
            ["Permission request was not grantable by the synthetic bridge."]
        )
    }

    private func removeFailure(
        for result: ChromeMV3PermissionsAPIRemoveResult
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions
            .map(\.classification)
        if classifications.contains(.requiredManifestPermission) {
            return (
                "requiredManifestPermission",
                "Required manifest permissions cannot be removed.",
                ["chrome.permissions.remove rejected a required manifest permission."]
            )
        }
        if classifications.contains(.notGranted) {
            return (
                "permissionNotGranted",
                "Requested permission or origin is not currently granted.",
                ["chrome.permissions.remove rejected a non-granted permission."]
            )
        }
        if classifications.contains(.unsupportedOrDeferred) {
            return (
                "unsupportedOrDeferredPermission",
                "Requested permission or origin is unsupported or deferred.",
                ["chrome.permissions.remove rejected unsupported/deferred state."]
            )
        }
        return (
            "permissionRemoveRejected",
            "chrome.permissions.remove was rejected by internal permission state.",
            ["Permission remove was not applicable."]
        )
    }

    private func invalidArguments(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ message: String
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
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
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        permissionEventPayload:
            ChromeMV3PermissionsAPIEventPayload? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        permissionsContainsResult:
            ChromeMV3PermissionsAPIContainsResult? = nil,
        permissionsGetAllResult:
            ChromeMV3PermissionsAPIGetAllResult? = nil,
        permissionsRequestResult:
            ChromeMV3PermissionsAPIRequestResult? = nil,
        permissionsRemoveResult:
            ChromeMV3PermissionsAPIRemoveResult? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3PermissionsJSBridgeHostResponse {
        let invocationMode = request?.invocationMode ?? .promise
        return ChromeMV3PermissionsJSBridgeHostResponse(
            bridgeCallID: request?.bridgeCallID
                ?? stableIDPermissionsJS(
                    prefix: "permissions-js-response",
                    parts: [methodName ?? "unknown", succeeded.description]
                ),
            namespace: request?.namespace ?? "permissions",
            methodName: request?.methodName ?? methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: payload,
            permissionEventPayload: permissionEventPayload,
            lastErrorMessage: lastErrorMessage,
            lastErrorCode: lastErrorCode,
            callbackWouldSetLastError:
                invocationMode == .callback && succeeded == false,
            promiseWouldReject:
                invocationMode == .promise && succeeded == false,
            permissionsContainsResult: permissionsContainsResult,
            permissionsGetAllResult: permissionsGetAllResult,
            permissionsRequestResult: permissionsRequestResult,
            permissionsRemoveResult: permissionsRemoveResult,
            permissionRuntimeSnapshot: permissionRuntimeOwner.snapshot,
            permissionsJSBridgeAvailableInSyntheticHarness:
                configuration
                .permissionsJSBridgeAvailableInSyntheticHarness,
            permissionsJSBridgeAvailableInProduct: false,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPermissionsJS(
                    configuration.diagnostics
                        + diagnostics
                        + [
                            "permissions JS bridge handler is DEBUG/internal and synthetic-surface gated.",
                            "No product permission UI is displayed.",
                            "No product normal-tab bridge is installed.",
                            "No native messaging, service-worker wake, or product runtime exposure occurred.",
                        ]
                )
        )
    }

    private func argumentFailure<T>(
        _ message: String
    ) -> Result<T, ChromeMV3PermissionsJSArgumentError> {
        .failure(ChromeMV3PermissionsJSArgumentError(message: message))
    }

    static func defaultPermissionRuntimeOwner(
        configuration: ChromeMV3PermissionsJSBridgeConfiguration
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
                                "tabs",
                            ],
                            declaredHostPermissions: [],
                            optionalAPIPermissions: [
                                "bookmarks",
                                "history",
                                "topSites",
                            ],
                            optionalHostPermissions: [
                                "https://example.com/*",
                                "https://optional.example/*",
                            ]
                        )
                )
        )
    }
}

struct ChromeMV3PermissionsJSArgumentError:
    Error,
    Equatable,
    Sendable
{
    var message: String
}

struct ChromeMV3PermissionsWebKitExecutionSummary:
    Codable,
    Equatable,
    Sendable
{
    var status: String
    var permissionRuntimeStateAvailable: Bool
    var permissionsModelHandlersAvailable: Bool
    var permissionsJSBridgeAvailableInSyntheticHarness: Bool
    var permissionsJSExecutedInWebKitSyntheticHarness: Bool
    var containsCallbackExecuted: Bool
    var containsPromiseExecuted: Bool
    var containsOriginsExecuted: Bool
    var containsMissingOptionalReturnedFalse: Bool
    var containsRevokedOptionalReturnedFalse: Bool
    var getAllCallbackExecuted: Bool
    var getAllPromiseExecuted: Bool
    var requestAcceptedModeledPermissionExecuted: Bool
    var requestAcceptedModeledOriginExecuted: Bool
    var requestDeniedModeledResultExecuted: Bool
    var requestWithoutModeledPromptRejected: Bool
    var requestUndeclaredRejected: Bool
    var removeOptionalPermissionExecuted: Bool
    var removeOptionalOriginExecuted: Bool
    var removeRequiredPermissionRejected: Bool
    var callbackModeRepresentedFromActualJSCall: Bool
    var promiseModeRepresentedFromActualJSCall: Bool
    var lastErrorScopedFromActualJSCall: Bool
    var onAddedPayloadGenerated: Bool
    var onRemovedPayloadGenerated: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]

    static func notAttempted(
        permissionRuntimeStateAvailable: Bool,
        permissionsModelHandlersAvailable: Bool,
        permissionsJSBridgeAvailableInSyntheticHarness: Bool
    ) -> ChromeMV3PermissionsWebKitExecutionSummary {
        ChromeMV3PermissionsWebKitExecutionSummary(
            status: "notAttemptedByModelReportGenerator",
            permissionRuntimeStateAvailable:
                permissionRuntimeStateAvailable,
            permissionsModelHandlersAvailable:
                permissionsModelHandlersAvailable,
            permissionsJSBridgeAvailableInSyntheticHarness:
                permissionsJSBridgeAvailableInSyntheticHarness,
            permissionsJSExecutedInWebKitSyntheticHarness: false,
            containsCallbackExecuted: false,
            containsPromiseExecuted: false,
            containsOriginsExecuted: false,
            containsMissingOptionalReturnedFalse: false,
            containsRevokedOptionalReturnedFalse: false,
            getAllCallbackExecuted: false,
            getAllPromiseExecuted: false,
            requestAcceptedModeledPermissionExecuted: false,
            requestAcceptedModeledOriginExecuted: false,
            requestDeniedModeledResultExecuted: false,
            requestWithoutModeledPromptRejected: false,
            requestUndeclaredRejected: false,
            removeOptionalPermissionExecuted: false,
            removeOptionalOriginExecuted: false,
            removeRequiredPermissionRejected: false,
            callbackModeRepresentedFromActualJSCall: false,
            promiseModeRepresentedFromActualJSCall: false,
            lastErrorScopedFromActualJSCall: false,
            onAddedPayloadGenerated: false,
            onRemovedPayloadGenerated: false,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            productRuntimeExposed: false,
            diagnostics: [
                "WebKit-executed permissions synthetic harness was not run by this model-only report generator.",
                "Model handler availability is reported separately from WebKit JS execution.",
            ]
        )
    }

    static func fromWebKitScriptResult(
        json: String?,
        scriptEvaluationSucceeded: Bool,
        permissionRuntimeStateAvailable: Bool,
        permissionsModelHandlersAvailable: Bool,
        permissionsJSBridgeAvailableInSyntheticHarness: Bool,
        diagnostics: [String]
    ) -> ChromeMV3PermissionsWebKitExecutionSummary {
        let object = decodedObject(json)
        func bool(_ key: String) -> Bool {
            object?[key] as? Bool ?? false
        }
        let callbackMode = bool("containsCallbackOK")
            || bool("getAllCallbackOK")
            || bool("removeRequiredCallbackLastErrorOK")
        let promiseMode = bool("containsPromiseOK")
            || bool("getAllPromiseOK")
            || bool("requestAcceptedPermissionOK")
            || bool("requestWithoutPromptRejectedOK")
        let executed = scriptEvaluationSucceeded
        return ChromeMV3PermissionsWebKitExecutionSummary(
            status:
                executed
                    ? "executedInWebKitSyntheticHarness"
                    : "blockedOrFailedInWebKitSyntheticHarness",
            permissionRuntimeStateAvailable:
                permissionRuntimeStateAvailable,
            permissionsModelHandlersAvailable:
                permissionsModelHandlersAvailable,
            permissionsJSBridgeAvailableInSyntheticHarness:
                permissionsJSBridgeAvailableInSyntheticHarness,
            permissionsJSExecutedInWebKitSyntheticHarness: executed,
            containsCallbackExecuted: bool("containsCallbackOK"),
            containsPromiseExecuted: bool("containsPromiseOK"),
            containsOriginsExecuted: bool("containsOriginAfterGrantOK"),
            containsMissingOptionalReturnedFalse:
                bool("containsMissingOptionalFalseOK"),
            containsRevokedOptionalReturnedFalse:
                bool("containsRevokedOptionalFalseOK"),
            getAllCallbackExecuted: bool("getAllCallbackOK"),
            getAllPromiseExecuted: bool("getAllPromiseOK"),
            requestAcceptedModeledPermissionExecuted:
                bool("requestAcceptedPermissionOK"),
            requestAcceptedModeledOriginExecuted:
                bool("requestAcceptedOriginOK"),
            requestDeniedModeledResultExecuted:
                bool("requestDeniedModeledOK"),
            requestWithoutModeledPromptRejected:
                bool("requestWithoutPromptRejectedOK"),
            requestUndeclaredRejected: bool("requestUndeclaredRejectedOK"),
            removeOptionalPermissionExecuted:
                bool("removeOptionalPermissionOK"),
            removeOptionalOriginExecuted: bool("removeOptionalOriginOK"),
            removeRequiredPermissionRejected:
                bool("removeRequiredCallbackLastErrorOK"),
            callbackModeRepresentedFromActualJSCall: callbackMode,
            promiseModeRepresentedFromActualJSCall: promiseMode,
            lastErrorScopedFromActualJSCall:
                bool("lastErrorScopedOK"),
            onAddedPayloadGenerated: bool("onAddedPayloadOK"),
            onRemovedPayloadGenerated: bool("onRemovedPayloadOK"),
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            productRuntimeExposed: false,
            diagnostics:
                uniqueSortedPermissionsJS(
                    diagnostics
                        + [
                            executed
                                ? "chrome.permissions JS calls were executed by WebKit in the controlled synthetic harness."
                                : "permissions WebKit synthetic harness produced a deterministic blocked/failed diagnostic.",
                            "WebKit JS execution status is not inferred from model handler success.",
                            "Synthetic onAdded/onRemoved listener payloads are page-local diagnostics; product service-worker wake remains unavailable.",
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

private extension ChromeMV3StorageValue {
    static func permissionsJSEventPayload(
        _ payload: ChromeMV3PermissionsAPIEventPayload
    ) -> ChromeMV3StorageValue {
        .object([
            "eventKind": .string(payload.eventKind.rawValue),
            "source": .string(payload.source.rawValue),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
            "permissions": .array(
                payload.permissions.map(ChromeMV3StorageValue.string)
            ),
            "origins": .array(
                payload.origins.map(ChromeMV3StorageValue.string)
            ),
            "wouldDispatchNow": .bool(payload.wouldDispatchNow),
            "listenerRegistrationRequired":
                .bool(payload.listenerRegistrationRequired),
            "serviceWorkerWakeRequired":
                .bool(payload.serviceWorkerWakeRequired),
            "canWakeServiceWorkerNow":
                .bool(payload.canWakeServiceWorkerNow),
        ])
    }

    var permissionsJSFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.permissionsJSFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.permissionsJSFoundationObject)
        case .string(let value):
            return value
        }
    }

    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

private func normalizedPermissionsJS(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func stableIDPermissionsJS(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueSortedPermissionsJS(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
