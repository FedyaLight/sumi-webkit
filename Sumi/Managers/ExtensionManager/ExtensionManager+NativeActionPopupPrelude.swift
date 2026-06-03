#if DEBUG
import Foundation
import ObjectiveC
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3NativeActionPopupPreludeMessageHandler:
    NSObject,
    WKScriptMessageHandler
{
    weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        manager?.recordNativeActionPopupPreludeMessage(
            message.body,
            frameInfo: message.frameInfo
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private enum ChromeMV3NativeActionPopupPreludeAssociatedKeys {
    static var installed: UInt8 = 0
}

@available(macOS 15.5, *)
@MainActor
private extension WKUserContentController {
    var sumiNativeActionPopupPreludeInstalled: Bool {
        get {
            (objc_getAssociatedObject(
                self,
                &ChromeMV3NativeActionPopupPreludeAssociatedKeys.installed
            ) as? Bool) == true
        }
        set {
            objc_setAssociatedObject(
                self,
                &ChromeMV3NativeActionPopupPreludeAssociatedKeys.installed,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func installNativeActionPopupPreludeIfEnabled(
        into configuration: WKWebViewConfiguration,
        reason: String
    ) -> Bool {
        guard Self.isNativeActionPopupBoundaryObservationEnabled else {
            return false
        }

        let userContentController = configuration.userContentController
        guard userContentController.sumiNativeActionPopupPreludeInstalled == false else {
            return true
        }

        let handler = ChromeMV3NativeActionPopupPreludeMessageHandler(
            manager: self
        )
        userContentController.add(
            handler,
            contentWorld: .page,
            name: Self.nativeActionPopupPreludeMessageHandlerName
        )

        let userScript = WKUserScript(
            source: Self.nativeActionPopupPreludeSource(
                messageHandlerName:
                    Self.nativeActionPopupPreludeMessageHandlerName
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        userContentController.addUserScript(userScript)
        userContentController.sumiNativeActionPopupPreludeInstalled = true
        extensionRuntimeTrace(
            "nativeActionPopupPrelude installed reason=\(reason) configuration=\(extensionRuntimeConfigurationDescription(configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(userContentController))"
        )
        return true
    }

    func recordNativeActionPopupPreludeMessage(
        _ body: Any,
        frameInfo: WKFrameInfo
    ) {
        guard Self.isNativeActionPopupBoundaryObservationEnabled,
              let raw = body as? [String: Any],
              let extensionID = sanitizedPreludeString(
                  raw["extensionId"],
                  allowedValues: Set(extensionContexts.keys)
              ),
              extensionContexts[extensionID] != nil,
              nativeActionPopupBoundaryRecorders[extensionID] != nil
        else {
            return
        }

        let apiName = sanitizedPreludeString(
            raw["apiName"],
            allowedValues: Self.allowedNativeActionPopupPreludeAPINames
        ) ?? "nativeActionPopupPrelude"
        let sourceContext = sanitizedPreludeString(
            raw["sourceContext"],
            allowedValues: Self.allowedNativeActionPopupPreludeSourceContexts
        ) ?? "extensionPage.pageWorld"
        let targetContext = sanitizedPreludeString(
            raw["targetContext"],
            allowedValues: Self.allowedNativeActionPopupPreludeTargetContexts
        ) ?? "unknown"
        let resultClassifier = sanitizedPreludeString(
            raw["resultClassifier"],
            allowedValues:
                Self.allowedNativeActionPopupPreludeResultClassifiers
        )
        let listenerRouteResult = sanitizedPreludeString(
            raw["listenerRouteResult"],
            allowedValues:
                Self.allowedNativeActionPopupPreludeListenerResults
        )
        let firstMissingAPIOrError = sanitizedPreludeString(
            raw["firstMissingAPIOrError"],
            allowedValues:
                Self.allowedNativeActionPopupPreludeMissingOrErrorClassifiers
        )
        let keyCount = sanitizedPreludeKeyCount(raw["keyCount"])
        let safeTopLevelFieldNames = sanitizedPreludeFieldNames(
            raw["safeTopLevelFieldNames"]
        )
        let portName = sanitizedPreludePortName(raw["portName"])
        let payloadShape = sanitizedPreludeString(
            raw["messageShape"],
            maxLength: 96
        )
        let sanitizedURLShape = Self.sanitizedNativeActionPopupPreludeURLShape(
            frameInfo.request.url
        )
        let descriptorSummary = sanitizedPreludeString(
            raw["descriptorSummary"],
            maxLength: 240
        )

        if apiName == "nativeActionPopupPrelude" {
            nativeActionPopupBoundaryRecorders[extensionID]?
                .recordPreludeAttachment(
                    resultClassifier: resultClassifier,
                    firstMissingAPIOrError: firstMissingAPIOrError
                )
        }

        nativeActionPopupBoundaryRecorders[extensionID]?.recordRoute(
            apiName: apiName,
            sourceContext: sourceContext,
            targetContext: targetContext,
            nativeBoundary: "WKUserScript.pageWorld",
            metadataAvailable: true,
            payloadShape: payloadShape,
            resultClassifier: resultClassifier,
            keyCount: keyCount,
            safeTopLevelFieldNames: safeTopLevelFieldNames,
            portName: portName,
            listenerRouteResult: listenerRouteResult,
            firstMissingAPIOrError: firstMissingAPIOrError,
            sanitizedURLShape: sanitizedURLShape,
            descriptorSummary: descriptorSummary,
            notes: [
                "DEBUG-only prelude record; raw message bodies and URL values are not accepted.",
            ]
        )
    }

    private func sanitizedPreludeString(
        _ value: Any?,
        allowedValues: Set<String>? = nil,
        maxLength: Int = 80
    ) -> String? {
        guard let string = value as? String,
              string.isEmpty == false,
              string.count <= maxLength,
              string.range(
                  of: #"^[A-Za-z0-9_.:/<>()-]+$"#,
                  options: .regularExpression
              ) != nil
        else {
            return nil
        }

        if let allowedValues {
            return allowedValues.contains(string) ? string : nil
        }

        return Self.containsSensitivePreludeFragment(string) ? nil : string
    }

    private func sanitizedPreludeKeyCount(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let count = number.intValue
        guard count >= 0, count <= 200 else { return nil }
        return count
    }

    private func sanitizedPreludeFieldNames(_ value: Any?) -> [String] {
        guard let fieldNames = value as? [String] else { return [] }
        return Array(
            Set(
                fieldNames
                    .filter { Self.safePreludeTopLevelFieldNames.contains($0) }
                    .filter { Self.containsSensitivePreludeFragment($0) == false }
            )
        ).sorted()
    }

    private func sanitizedPreludePortName(_ value: Any?) -> String? {
        guard let portName = sanitizedPreludeString(value, maxLength: 64),
              portName.range(
                  of: #"^[A-Za-z][A-Za-z0-9_.:-]{0,63}$"#,
                  options: .regularExpression
              ) != nil
        else {
            return nil
        }
        return portName
    }

    private nonisolated static func containsSensitivePreludeFragment(
        _ value: String
    ) -> Bool {
        sensitivePreludeFragments.contains { fragment in
            value.localizedCaseInsensitiveContains(fragment)
        }
    }

    nonisolated static func sanitizedNativeActionPopupPreludeURLShape(
        _ url: URL?
    ) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return nil
        }
        if extensionSchemes.contains(scheme) {
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

    private nonisolated static let allowedNativeActionPopupPreludeAPINames:
        Set<String> = [
            "nativeActionPopupPrelude",
            "chrome.runtime.sendMessage",
            "chrome.runtime.connect",
            "chrome.runtime.connectNative",
            "chrome.runtime.sendNativeMessage",
            "chrome.tabs.query",
            "chrome.tabs.sendMessage",
            "chrome.Port.postMessage",
            "chrome.Port.disconnect",
            "browser.runtime.sendMessage",
            "browser.runtime.connect",
            "browser.runtime.connectNative",
            "browser.runtime.sendNativeMessage",
            "browser.tabs.query",
            "browser.tabs.sendMessage",
            "browser.Port.postMessage",
            "browser.Port.disconnect",
        ]

    private nonisolated static let allowedNativeActionPopupPreludeSourceContexts:
        Set<String> = [
            "extensionPage.pageWorld",
            "extensionPage.port",
        ]

    private nonisolated static let allowedNativeActionPopupPreludeTargetContexts:
        Set<String> = [
            "extensionRuntime",
            "externalExtension",
            "runtimePort",
            "nativeApplication",
            "nativeApplicationPort",
            "contentScriptTab",
            "tabQuery",
            "unknown",
        ]

    private nonisolated static let allowedNativeActionPopupPreludeResultClassifiers:
        Set<String> = [
            "apiMissing",
            "namespaceMissing",
            "ownerMissing",
            "notFunction",
            "notWritable",
            "wrapperInstalled",
            "alreadyWrapped",
            "called",
            "returnedUndefined",
            "returnedNull",
            "returnedPromise",
            "returnedPort",
            "returnedValue",
            "threw",
            "portWrapInstalled",
            "portWrapFailed",
            "preludeInstalledAtDocumentStart",
            "preludeNoChromeNamespaceAtDocumentStart",
            "preludeNoObservableNamespaceAtDocumentStart",
            "descriptorObserved",
        ]

    private nonisolated static let allowedNativeActionPopupPreludeListenerResults:
        Set<String> = [
            "notObservable",
            "calledOriginal",
            "returnedOriginal",
            "threwOriginal",
        ]

    private nonisolated static let allowedNativeActionPopupPreludeMissingOrErrorClassifiers:
        Set<String> = [
            "chromeMissing",
            "browserMissing",
            "runtimeMissing",
            "tabsMissing",
            "runtime.sendMessageMissing",
            "runtime.connectMissing",
            "runtime.connectNativeMissing",
            "runtime.sendNativeMessageMissing",
            "tabs.queryMissing",
            "tabs.sendMessageMissing",
            "methodNotWritable",
            "originalThrew",
            "portPostMessageMissing",
            "portDisconnectMissing",
        ]

    private nonisolated static let safePreludeTopLevelFieldNames: Set<String> = [
        "active",
        "action",
        "audible",
        "autoDiscardable",
        "command",
        "currentWindow",
        "discarded",
        "documentId",
        "frameId",
        "frozen",
        "highlighted",
        "id",
        "index",
        "kind",
        "lastFocusedWindow",
        "method",
        "muted",
        "name",
        "operation",
        "pinned",
        "status",
        "title",
        "type",
        "windowId",
        "windowType",
    ]

    private nonisolated static let sensitivePreludeFragments: Set<String> = [
        "auth",
        "cookie",
        "credential",
        "password",
        "secret",
        "session",
        "token",
        "vault",
    ]

    private nonisolated static func nativeActionPopupPreludeSource(
        messageHandlerName: String
    ) -> String {
        """
        (() => {
          "use strict";
          const marker = "__sumiNativeActionPopupRoutePreludeInstalled";
          if (globalThis[marker] === true) {
            return;
          }
          try {
            Object.defineProperty(globalThis, marker, {
              value: true,
              configurable: false,
              enumerable: false,
              writable: false
            });
          } catch (_) {
            globalThis[marker] = true;
          }

          const handlerName = "\(messageHandlerName)";
          const sourceContext = "extensionPage.pageWorld";
          const safeFieldNames = new Set([
            "active", "action", "audible", "autoDiscardable", "command",
            "currentWindow", "discarded", "documentId", "frameId", "frozen",
            "highlighted", "id", "index", "kind", "lastFocusedWindow",
            "method", "muted", "name", "operation", "pinned", "status",
            "title", "type", "windowId", "windowType"
          ]);
          const sensitiveFragments = [
            "auth", "cookie", "credential", "password", "secret", "session",
            "token", "vault"
          ];

          function runtimeId(namespaceObject) {
            try {
              return namespaceObject && namespaceObject.runtime
                && typeof namespaceObject.runtime.id === "string"
                ? namespaceObject.runtime.id
                : null;
            } catch (_) {
              return null;
            }
          }

          function activeExtensionId(namespaceObject) {
            return runtimeId(globalThis.chrome)
              || runtimeId(globalThis.browser)
              || runtimeId(namespaceObject);
          }

          function isSensitiveName(name) {
            const lower = String(name || "").toLowerCase();
            return sensitiveFragments.some((fragment) => lower.includes(fragment));
          }

          function safeNamesForObject(value) {
            if (!value || typeof value !== "object" || Array.isArray(value)) {
              return [];
            }
            return Object.keys(value)
              .filter((key) => safeFieldNames.has(key))
              .filter((key) => !isSensitiveName(key))
              .sort();
          }

          function keyCount(value) {
            if (!value || typeof value !== "object" || Array.isArray(value)) {
              return null;
            }
            return Object.keys(value).length;
          }

          function valueKind(value) {
            if (value === null) {
              return "null";
            }
            if (Array.isArray(value)) {
              return "array(count:" + value.length + ")";
            }
            const type = typeof value;
            if (type === "object") {
              return "object";
            }
            if (type === "string") {
              return "string(length:" + value.length + ")";
            }
            if (type === "number") {
              return "number";
            }
            if (type === "boolean") {
              return "boolean";
            }
            if (type === "undefined") {
              return "undefined";
            }
            return "value(" + type + ")";
          }

          function safePortName(value) {
            if (typeof value !== "string" || value.length === 0 || value.length > 64) {
              return null;
            }
            if (!/^[A-Za-z][A-Za-z0-9_.:-]{0,63}$/.test(value)) {
              return null;
            }
            if (isSensitiveName(value)) {
              return null;
            }
            return value;
          }

          function post(record) {
            try {
              const handler = globalThis.webkit
                && globalThis.webkit.messageHandlers
                && globalThis.webkit.messageHandlers[handlerName];
              if (!handler || typeof handler.postMessage !== "function") {
                return;
              }
              handler.postMessage(record);
            } catch (_) {
            }
          }

          function postRoute(namespaceObject, record) {
            post(Object.assign({
              extensionId: activeExtensionId(namespaceObject),
              sourceContext
            }, record));
          }

          function returnClassifier(value, portExpected) {
            if (typeof value === "undefined") {
              return "returnedUndefined";
            }
            if (value === null) {
              return "returnedNull";
            }
            if (portExpected && value && typeof value === "object") {
              return "returnedPort";
            }
            if (value && typeof value.then === "function") {
              return "returnedPromise";
            }
            return "returnedValue";
          }

          function messageArgument(apiName, args) {
            if (apiName.endsWith("runtime.sendMessage")) {
              return typeof args[0] === "string" && args.length > 1
                ? args[1]
                : args[0];
            }
            if (apiName.endsWith("tabs.sendMessage")) {
              return args[1];
            }
            if (apiName.endsWith("tabs.query")) {
              return args[0];
            }
            if (apiName.endsWith("sendNativeMessage")) {
              return args[1];
            }
            if (apiName.endsWith("Port.postMessage")) {
              return args[0];
            }
            return undefined;
          }

          function targetContextFor(apiName, args) {
            if (apiName.endsWith("runtime.sendMessage")) {
              return typeof args[0] === "string" && args.length > 1
                ? "externalExtension"
                : "extensionRuntime";
            }
            if (apiName.endsWith("runtime.connect")) {
              return typeof args[0] === "string"
                ? "externalExtension"
                : "runtimePort";
            }
            if (apiName.endsWith("connectNative")) {
              return "nativeApplicationPort";
            }
            if (apiName.endsWith("sendNativeMessage")) {
              return "nativeApplication";
            }
            if (apiName.endsWith("tabs.query")) {
              return "tabQuery";
            }
            if (apiName.endsWith("tabs.sendMessage")) {
              return "contentScriptTab";
            }
            if (apiName.endsWith("Port.postMessage") || apiName.endsWith("Port.disconnect")) {
              return "runtimePort";
            }
            return "unknown";
          }

          function connectInfo(args) {
            if (args[0] && typeof args[0] === "object") {
              return args[0];
            }
            if (args[1] && typeof args[1] === "object") {
              return args[1];
            }
            return null;
          }

          function shapeRecord(apiName, namespaceObject, args, resultClassifier, listenerRouteResult, firstMissingAPIOrError) {
            const message = messageArgument(apiName, args);
            const info = connectInfo(args);
            const fields = safeNamesForObject(message);
            const count = keyCount(message);
            const portName = safePortName(
              info && Object.prototype.hasOwnProperty.call(info, "name")
                ? info.name
                : undefined
            );
            return {
              apiName,
              targetContext: targetContextFor(apiName, args),
              messageShape: valueKind(message),
              keyCount: count,
              safeTopLevelFieldNames: fields,
              portName,
              resultClassifier,
              listenerRouteResult,
              firstMissingAPIOrError
            };
          }

          function descriptorAllowsWrap(owner, methodName) {
            let cursor = owner;
            while (cursor) {
              const descriptor = Object.getOwnPropertyDescriptor(cursor, methodName);
              if (descriptor) {
                return descriptor.writable !== false || typeof descriptor.set === "function";
              }
              cursor = Object.getPrototypeOf(cursor);
            }
            return true;
          }

          function descriptorFlag(value) {
            if (value === true) {
              return "true";
            }
            if (value === false) {
              return "false";
            }
            return "na";
          }

          function objectExtensibleFlag(value) {
            try {
              if (!value || (typeof value !== "object" && typeof value !== "function")) {
                return "na";
              }
              return descriptorFlag(Object.isExtensible(value));
            } catch (_) {
              return "na";
            }
          }

          function descriptorSummary(namespaceObject, owner, methodName) {
            const namespaceExtensible = objectExtensibleFlag(namespaceObject);
            const objectExtensible = objectExtensibleFlag(owner);
            let cursor = owner;
            let depth = 0;
            let foundDescriptor = null;
            let foundOwner = null;
            while (cursor) {
              const descriptor = Object.getOwnPropertyDescriptor(cursor, methodName);
              if (descriptor) {
                foundDescriptor = descriptor;
                foundOwner = cursor;
                break;
              }
              cursor = Object.getPrototypeOf(cursor);
              depth += 1;
            }
            if (!foundDescriptor) {
              return [
                "descriptor:missing",
                "owner:missing",
                "prototypeDepth:missing",
                "objectExtensible:" + objectExtensible,
                "namespaceExtensible:" + namespaceExtensible
              ].join("/");
            }

            const isData = Object.prototype.hasOwnProperty.call(foundDescriptor, "value")
              || Object.prototype.hasOwnProperty.call(foundDescriptor, "writable");
            return [
              "descriptor:" + (isData ? "data" : "accessor"),
              "owner:" + (depth === 0 ? "own" : "prototype"),
              "prototypeDepth:" + String(depth),
              "writable:" + (isData ? descriptorFlag(foundDescriptor.writable) : "na"),
              "configurable:" + descriptorFlag(foundDescriptor.configurable),
              "enumerable:" + descriptorFlag(foundDescriptor.enumerable),
              "getter:" + descriptorFlag(typeof foundDescriptor.get === "function"),
              "setter:" + descriptorFlag(typeof foundDescriptor.set === "function"),
              "objectExtensible:" + objectExtensible,
              "descriptorOwnerExtensible:" + objectExtensibleFlag(foundOwner),
              "namespaceExtensible:" + namespaceExtensible
            ].join("/");
          }

          function wrapPort(namespaceName, namespaceObject, port) {
            if (!port || typeof port !== "object") {
              return port;
            }
            if (port.__sumiNativeActionPopupPortWrapped === true) {
              return port;
            }
            try {
              Object.defineProperty(port, "__sumiNativeActionPopupPortWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
            } catch (_) {
              postRoute(namespaceObject, {
                apiName: namespaceName + ".Port.postMessage",
                targetContext: "runtimePort",
                resultClassifier: "portWrapFailed",
                listenerRouteResult: "notObservable",
                firstMissingAPIOrError: null
              });
              return port;
            }

            [["postMessage", "Port.postMessage"], ["disconnect", "Port.disconnect"]]
              .forEach(([methodName, apiSuffix]) => {
                const original = port[methodName];
                const apiName = namespaceName + "." + apiSuffix;
                if (typeof original !== "function") {
                  postRoute(namespaceObject, {
                    apiName,
                    targetContext: "runtimePort",
                    resultClassifier: "apiMissing",
                    listenerRouteResult: "notObservable",
                    firstMissingAPIOrError: methodName === "postMessage"
                      ? "portPostMessageMissing"
                      : "portDisconnectMissing"
                  });
                  return;
                }
                postRoute(namespaceObject, {
                  apiName,
                  targetContext: "runtimePort",
                  resultClassifier: "descriptorObserved",
                  listenerRouteResult: "notObservable",
                  descriptorSummary: descriptorSummary(
                    namespaceObject,
                    port,
                    methodName
                  )
                });
                if (!descriptorAllowsWrap(port, methodName)) {
                  postRoute(namespaceObject, {
                    apiName,
                    targetContext: "runtimePort",
                    resultClassifier: "notWritable",
                    listenerRouteResult: "notObservable",
                    firstMissingAPIOrError: "methodNotWritable"
                  });
                  return;
                }
                const wrapped = function() {
                  const args = Array.prototype.slice.call(arguments);
                  postRoute(namespaceObject, shapeRecord(
                    apiName,
                    namespaceObject,
                    args,
                    "called",
                    "calledOriginal",
                    null
                  ));
                  try {
                    const result = Reflect.apply(original, this, args);
                    postRoute(namespaceObject, shapeRecord(
                      apiName,
                      namespaceObject,
                      args,
                      returnClassifier(result, false),
                      "returnedOriginal",
                      null
                    ));
                    return result;
                  } catch (error) {
                    postRoute(namespaceObject, shapeRecord(
                      apiName,
                      namespaceObject,
                      args,
                      "threw",
                      "threwOriginal",
                      "originalThrew"
                    ));
                    throw error;
                  }
                };
                try {
                  Object.defineProperty(wrapped, "name", {
                    value: original.name,
                    configurable: true
                  });
                  Object.defineProperty(wrapped, "length", {
                    value: original.length,
                    configurable: true
                  });
                } catch (_) {
                }
                port[methodName] = wrapped;
                postRoute(namespaceObject, {
                  apiName,
                  targetContext: "runtimePort",
                  resultClassifier: "portWrapInstalled",
                  listenerRouteResult: "notObservable",
                  portName: safePortName(port.name)
                });
              });
            return port;
          }

          function wrapMethod(namespaceName, namespaceObject, owner, methodName, missingClassifier, portExpected) {
            const apiName = namespaceName + "." + (owner === namespaceObject.tabs ? "tabs." : "runtime.") + methodName;
            if (!owner) {
              postRoute(namespaceObject, {
                apiName,
                targetContext: "unknown",
                resultClassifier: "ownerMissing",
                listenerRouteResult: "notObservable",
                firstMissingAPIOrError: missingClassifier
              });
              return;
            }
            const original = owner[methodName];
            postRoute(namespaceObject, {
              apiName,
              targetContext: targetContextFor(apiName, []),
              resultClassifier: "descriptorObserved",
              listenerRouteResult: "notObservable",
              descriptorSummary: descriptorSummary(
                namespaceObject,
                owner,
                methodName
              )
            });
            if (typeof original !== "function") {
              postRoute(namespaceObject, {
                apiName,
                targetContext: "unknown",
                resultClassifier: "apiMissing",
                listenerRouteResult: "notObservable",
                firstMissingAPIOrError: missingClassifier
              });
              return;
            }
            if (original.__sumiNativeActionPopupPreludeWrapped === true) {
              postRoute(namespaceObject, {
                apiName,
                targetContext: "unknown",
                resultClassifier: "alreadyWrapped",
                listenerRouteResult: "notObservable"
              });
              return;
            }
            if (!descriptorAllowsWrap(owner, methodName)) {
              postRoute(namespaceObject, {
                apiName,
                targetContext: "unknown",
                resultClassifier: "notWritable",
                listenerRouteResult: "notObservable",
                firstMissingAPIOrError: "methodNotWritable"
              });
              return;
            }

            const wrapped = function() {
              const args = Array.prototype.slice.call(arguments);
              postRoute(namespaceObject, shapeRecord(
                apiName,
                namespaceObject,
                args,
                "called",
                "calledOriginal",
                null
              ));
              try {
                const result = Reflect.apply(original, this, args);
                if (portExpected) {
                  wrapPort(namespaceName, namespaceObject, result);
                }
                postRoute(namespaceObject, shapeRecord(
                  apiName,
                  namespaceObject,
                  args,
                  returnClassifier(result, portExpected),
                  "returnedOriginal",
                  null
                ));
                return result;
              } catch (error) {
                postRoute(namespaceObject, shapeRecord(
                  apiName,
                  namespaceObject,
                  args,
                  "threw",
                  "threwOriginal",
                  "originalThrew"
                ));
                throw error;
              }
            };

            try {
              Object.defineProperty(wrapped, "__sumiNativeActionPopupPreludeWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              Object.defineProperty(wrapped, "name", {
                value: original.name,
                configurable: true
              });
              Object.defineProperty(wrapped, "length", {
                value: original.length,
                configurable: true
              });
            } catch (_) {
            }

            owner[methodName] = wrapped;
            postRoute(namespaceObject, {
              apiName,
              targetContext: targetContextFor(apiName, []),
              resultClassifier: "wrapperInstalled",
              listenerRouteResult: "notObservable"
            });
          }

          function installForNamespace(namespaceName, namespaceObject) {
            if (!namespaceObject) {
              post({
                extensionId: activeExtensionId(namespaceObject),
                sourceContext,
                apiName: "nativeActionPopupPrelude",
                targetContext: "unknown",
                resultClassifier: namespaceName === "chrome"
                  ? "preludeNoChromeNamespaceAtDocumentStart"
                  : "namespaceMissing",
                firstMissingAPIOrError: namespaceName === "chrome"
                  ? "chromeMissing"
                  : "browserMissing"
              });
              return false;
            }

            const runtime = namespaceObject.runtime;
            const tabs = namespaceObject.tabs;
            if (!runtime && !tabs) {
              postRoute(namespaceObject, {
                apiName: "nativeActionPopupPrelude",
                targetContext: "unknown",
                resultClassifier: "preludeNoObservableNamespaceAtDocumentStart",
                firstMissingAPIOrError: "runtimeMissing"
              });
              return false;
            }

            wrapMethod(namespaceName, namespaceObject, runtime, "sendMessage", "runtime.sendMessageMissing", false);
            wrapMethod(namespaceName, namespaceObject, runtime, "connect", "runtime.connectMissing", true);
            wrapMethod(namespaceName, namespaceObject, runtime, "connectNative", "runtime.connectNativeMissing", true);
            wrapMethod(namespaceName, namespaceObject, runtime, "sendNativeMessage", "runtime.sendNativeMessageMissing", false);
            wrapMethod(namespaceName, namespaceObject, tabs, "query", "tabs.queryMissing", false);
            wrapMethod(namespaceName, namespaceObject, tabs, "sendMessage", "tabs.sendMessageMissing", false);
            return true;
          }

          const installedChrome = installForNamespace("chrome", globalThis.chrome);
          const installedBrowser = installForNamespace("browser", globalThis.browser);
          post({
            extensionId: activeExtensionId(globalThis.chrome || globalThis.browser),
            sourceContext,
            apiName: "nativeActionPopupPrelude",
            targetContext: "unknown",
            resultClassifier: installedChrome || installedBrowser
              ? "preludeInstalledAtDocumentStart"
              : "preludeNoObservableNamespaceAtDocumentStart",
            listenerRouteResult: "notObservable",
            firstMissingAPIOrError: installedChrome || installedBrowser
              ? null
              : "chromeMissing"
          });
        })();
        """
    }
}
#endif
