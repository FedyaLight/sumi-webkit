//
//  SafariExtensionRuntimeConnectCompatibility.swift
//  Sumi
//
//  Generic WebExtension runtime.connect compatibility for same-extension
//  content-script/background ports when WebKit does not deliver onConnect.
//

import Foundation
import ObjectiveC.runtime
import WebKit

@available(macOS 15.5, *)
@MainActor
enum SafariExtensionRuntimeConnectCompatibility {
    enum PreludeScope: String {
        case extensionPage
        case contentScript
    }

    static let installationSourceIdentifier =
        "sumi-webextension-runtime-connect-compatibility"

    private static let privateUserScriptSelector = NSSelectorFromString(
        "_initWithSource:injectionTime:forMainFrameOnly:includeMatchPatternStrings:excludeMatchPatternStrings:associatedURL:contentWorld:"
    )

    static var isPrivateUserScriptSPIAvailable: Bool {
        WKUserScript.instancesRespond(to: privateUserScriptSelector)
    }

    static func installPrelude(
        into userContentController: WKUserContentController,
        extensionContext: WKWebExtensionContext,
        scope: PreludeScope
    ) -> Bool {
        guard let userScript = makePreludeUserScript(
            extensionContext: extensionContext,
            scope: scope
        ) else {
            RuntimeDiagnostics.debug(
                "Runtime connect compatibility prelude unavailable for \(extensionContext.uniqueIdentifier) scope=\(scope.rawValue)",
                category: "Extensions"
            )
            return false
        }

        userContentController.addUserScript(userScript)
        return true
    }

    static func makePreludeUserScript(
        extensionContext: WKWebExtensionContext,
        scope: PreludeScope
    ) -> WKUserScript? {
        if scope == .contentScript {
            return WKUserScript(
                source: preludeSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentScriptWorld(for: extensionContext)
            )
        }

        let associatedURL = extensionContext.baseURL
        guard isPrivateUserScriptSPIAvailable,
              let method = class_getInstanceMethod(
                  WKUserScript.self,
                  privateUserScriptSelector
              ),
              let rawObject = class_createInstance(WKUserScript.self, 0) as AnyObject?
        else {
            return nil
        }

        typealias Initializer = @convention(c) (
            AnyObject,
            Selector,
            NSString,
            Int,
            Bool,
            NSArray,
            NSArray,
            NSURL,
            WKContentWorld?
        ) -> AnyObject?

        let initializer = unsafeBitCast(
            method_getImplementation(method),
            to: Initializer.self
        )
        let initialized = initializer(
            rawObject,
            privateUserScriptSelector,
            preludeSource as NSString,
            WKUserScriptInjectionTime.atDocumentStart.rawValue,
            false,
            includeMatchPatternStrings(for: associatedURL, scope: scope) as NSArray,
            [] as NSArray,
            associatedURL as NSURL,
            nil
        )

        return initialized as? WKUserScript
    }

    private static func contentScriptWorld(
        for extensionContext: WKWebExtensionContext
    ) -> WKContentWorld {
        WKContentWorld.world(
            name: "WebExtension-\(extensionContext.uniqueIdentifier)"
        )
    }

    private static func includeMatchPatternStrings(
        for extensionBaseURL: URL,
        scope: PreludeScope
    ) -> [String] {
        switch scope {
        case .contentScript:
            return ["<all_urls>"]
        case .extensionPage:
            let baseString = extensionBaseURL.absoluteString
            let extensionDocumentPattern =
                baseString.hasSuffix("/") ? "\(baseString)*" : "\(baseString)/*"
            return [extensionDocumentPattern]
        }
    }

    private static let preludeSource = """
    (() => {
      const installRuntimeConnectCompatibility = () => {
        const namespaceNames = ["browser", "chrome"];

        const createEvent = () => {
          const listeners = [];
          const event = {
            addListener(listener) {
              if (typeof listener !== "function" || listeners.includes(listener)) {
                return;
              }
              listeners.push(listener);
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
            }
          };
          Object.defineProperty(event, "__sumiDispatch", {
            value(...args) {
              for (const listener of listeners.slice()) {
                try {
                  listener(...args);
                } catch (error) {
                  setTimeout(() => { throw error; }, 0);
                }
              }
            }
          });
          Object.defineProperty(event, "__sumiListenerCount", {
            get() { return listeners.length; }
          });
          return event;
        };

        const runtimeNamespace = (namespace) => {
          const runtime = namespace && namespace.runtime;
          if (!runtime ||
              typeof runtime !== "object" ||
              typeof runtime.sendMessage !== "function") {
            return null;
          }
          return runtime;
        };

        const callbackLastError = (runtime) => {
          try {
            return runtime.lastError && runtime.lastError.message
              ? String(runtime.lastError.message)
              : null;
          } catch (_) {
            return null;
          }
        };

        const sendRuntimeMessage = (runtime, envelope, callback) => {
          let callbackCalled = false;
          const finish = (reply, errorMessage) => {
            if (callbackCalled) {
              return;
            }
            callbackCalled = true;
            callback(reply, errorMessage || null);
          };

          try {
            const result = runtime.sendMessage(envelope, (reply) => {
              finish(reply, callbackLastError(runtime));
            });
            if (result && typeof result.then === "function") {
              result.then(
                (reply) => finish(reply, null),
                (error) => finish(null, String(error && (error.message || error)))
              );
            }
          } catch (error) {
            finish(null, String(error && (error.message || error)));
          }
        };

        const makePortId = (runtime) => {
          const runtimeId = typeof runtime.id === "string" ? runtime.id : "unknown";
          const random = Math.random().toString(36).slice(2);
          return `sumi-port-${runtimeId}-${Date.now().toString(36)}-${random}`;
        };

        const parseConnectArguments = (runtime, argsLike) => {
          const args = Array.prototype.slice.call(argsLike);
          let extensionId = null;
          let connectInfo = {};

          if (args.length >= 2) {
            if (typeof args[0] === "string") {
              extensionId = args[0];
            }
            if (args[1] && typeof args[1] === "object") {
              connectInfo = args[1];
            }
          } else if (args.length === 1) {
            if (typeof args[0] === "string") {
              extensionId = args[0];
            } else if (args[0] && typeof args[0] === "object") {
              connectInfo = args[0];
            }
          }

          const runtimeId = typeof runtime.id === "string" ? runtime.id : null;
          return {
            extensionId,
            connectInfo,
            shouldShim: !extensionId || !runtimeId || extensionId === runtimeId
          };
        };

        const senderEnvelope = () => {
          let origin = null;
          try {
            origin = location.origin === "null" ? null : location.origin;
          } catch (_) {
          }

          let url = null;
          try {
            url = location.href || null;
          } catch (_) {
          }

          return { origin, url };
        };

        const installNamespace = (namespaceName) => {
          const namespace = globalThis[namespaceName];
          const runtime = runtimeNamespace(namespace);
          if (!runtime) {
            return false;
          }

          const runtimeId = typeof runtime.id === "string" ? runtime.id : "unknown";
          const marker = "__sumiRuntimeConnectCompatibilityInstalled";
          const markerValue = `${namespaceName}:${runtimeId}`;
          const installed = globalThis[marker] || {};
          if (installed[markerValue] === true) {
            return true;
          }

          const nativeConnect = typeof runtime.connect === "function"
            ? runtime.connect.bind(runtime)
            : null;
          const nativeOnConnect = runtime.onConnect;
          if (runtime.connect &&
              runtime.connect.__sumiRuntimeConnectCompatibilityWrapped === true &&
              nativeOnConnect &&
              nativeOnConnect.addListener &&
              nativeOnConnect.addListener.__sumiRuntimeConnectCompatibilityWrapped === true) {
            installed[markerValue] = true;
            Object.defineProperty(globalThis, marker, {
              value: installed,
              configurable: true,
              enumerable: false,
              writable: false
            });
            return true;
          }
          if (!nativeConnect || !nativeOnConnect ||
              typeof nativeOnConnect.addListener !== "function") {
            return false;
          }

          const connectListeners = [];
          const backgroundPorts = new Map();
          const outboundQueues = new Map();

          const queueOutboundEvent = (portId, event) => {
            const queue = outboundQueues.get(portId) || [];
            queue.push(event);
            outboundQueues.set(portId, queue);
          };

          const normalizeSender = (nativeSender, fallbackSender) => {
            if (nativeSender && typeof nativeSender === "object") {
              return nativeSender;
            }
            if (fallbackSender && typeof fallbackSender === "object") {
              return fallbackSender;
            }
            return undefined;
          };

          const dispatchConnect = (message, nativeSender, sendResponse) => {
            if (connectListeners.length === 0) {
              return false;
            }

            const portId = String(message.portId || "");
            if (!portId) {
              sendResponse({ ok: false, error: "Missing port id" });
              return true;
            }

            const port = {
              name: typeof message.name === "string" ? message.name : "",
              sender: normalizeSender(nativeSender, message.sender),
              onMessage: createEvent(),
              onDisconnect: createEvent(),
              postMessage(payload) {
                queueOutboundEvent(portId, {
                  type: "message",
                  message: payload === undefined ? null : payload
                });
              },
              disconnect() {
                if (!backgroundPorts.has(portId)) {
                  return;
                }
                backgroundPorts.delete(portId);
                queueOutboundEvent(portId, { type: "disconnect", error: null });
                this.onDisconnect.__sumiDispatch(this);
              }
            };

            backgroundPorts.set(portId, port);
            for (const listener of connectListeners.slice()) {
              try {
                listener(port);
              } catch (error) {
                setTimeout(() => { throw error; }, 0);
              }
            }

            sendResponse({ ok: true });
            return true;
          };

          const dispatchPostMessage = (message, sendResponse) => {
            const port = backgroundPorts.get(String(message.portId || ""));
            if (!port) {
              sendResponse({ ok: false, error: "Port is not connected" });
              return true;
            }

            port.onMessage.__sumiDispatch(message.message, port);
            sendResponse({ ok: true });
            return true;
          };

          const dispatchDisconnect = (message, sendResponse) => {
            const portId = String(message.portId || "");
            const port = backgroundPorts.get(portId);
            backgroundPorts.delete(portId);
            outboundQueues.delete(portId);
            if (port) {
              port.onDisconnect.__sumiDispatch(port);
            }
            sendResponse({ ok: true });
            return true;
          };

          const dispatchPoll = (message, sendResponse) => {
            const portId = String(message.portId || "");
            const queue = outboundQueues.get(portId) || [];
            outboundQueues.set(portId, []);
            sendResponse({ ok: true, events: queue });
            return true;
          };

          runtime.onMessage.addListener((message, sender, sendResponse) => {
            if (!message ||
                message.__sumiRuntimeConnectCompatibility !== true) {
              return false;
            }

            switch (message.type) {
            case "connect":
              return dispatchConnect(message, sender, sendResponse);
            case "postMessage":
              return dispatchPostMessage(message, sendResponse);
            case "disconnect":
              return dispatchDisconnect(message, sendResponse);
            case "poll":
              return dispatchPoll(message, sendResponse);
            default:
              return false;
            }
          });

          const nativeAddListener = nativeOnConnect.addListener.bind(nativeOnConnect);
          const nativeRemoveListener =
            typeof nativeOnConnect.removeListener === "function"
              ? nativeOnConnect.removeListener.bind(nativeOnConnect)
              : null;
          const nativeHasListener =
            typeof nativeOnConnect.hasListener === "function"
              ? nativeOnConnect.hasListener.bind(nativeOnConnect)
              : null;

          nativeOnConnect.addListener = function(listener) {
            if (typeof listener === "function" && !connectListeners.includes(listener)) {
              connectListeners.push(listener);
            }
            return nativeAddListener(listener);
          };
          nativeOnConnect.removeListener = function(listener) {
            const index = connectListeners.indexOf(listener);
            if (index >= 0) {
              connectListeners.splice(index, 1);
            }
            return nativeRemoveListener ? nativeRemoveListener(listener) : undefined;
          };
          nativeOnConnect.hasListener = function(listener) {
            return connectListeners.includes(listener) ||
              (nativeHasListener ? nativeHasListener(listener) : false);
          };

          const wrappedAddListener = nativeOnConnect.addListener;
          const wrappedRemoveListener = nativeOnConnect.removeListener;
          const wrappedHasListener = nativeOnConnect.hasListener;
          for (const wrapped of [
            wrappedAddListener,
            wrappedRemoveListener,
            wrappedHasListener
          ]) {
            if (typeof wrapped !== "function") {
              continue;
            }
            Object.defineProperty(wrapped, "__sumiRuntimeConnectCompatibilityWrapped", {
              value: true,
              configurable: false,
              enumerable: false,
              writable: false
            });
          }

          const wrappedConnect = function() {
            const parsed = parseConnectArguments(runtime, arguments);
            if (!parsed.shouldShim) {
              return nativeConnect.apply(this, arguments);
            }

            const portId = makePortId(runtime);
            const connectInfo = parsed.connectInfo || {};
            const name = typeof connectInfo.name === "string" ? connectInfo.name : "";
            let disconnected = false;
            let pollDelay = 25;
            const port = {
              name,
              onMessage: createEvent(),
              onDisconnect: createEvent(),
              postMessage(payload) {
                if (disconnected) {
                  return;
                }
                sendRuntimeMessage(runtime, {
                  __sumiRuntimeConnectCompatibility: true,
                  runtimeId,
                  type: "postMessage",
                  portId,
                  message: payload === undefined ? null : payload
                }, () => {});
              },
              disconnect() {
                if (disconnected) {
                  return;
                }
                disconnected = true;
                sendRuntimeMessage(runtime, {
                  __sumiRuntimeConnectCompatibility: true,
                  runtimeId,
                  type: "disconnect",
                  portId
                }, () => {});
                port.onDisconnect.__sumiDispatch(port);
              }
            };

            const handleDisconnect = (errorMessage) => {
              if (disconnected) {
                return;
              }
              disconnected = true;
              let previousLastErrorDescriptor = null;
              let didOverrideLastError = false;
              if (errorMessage) {
                try {
                  previousLastErrorDescriptor =
                    Object.getOwnPropertyDescriptor(runtime, "lastError");
                  Object.defineProperty(runtime, "lastError", {
                    value: { message: errorMessage },
                    configurable: true,
                    enumerable: false,
                    writable: false
                  });
                  didOverrideLastError = true;
                } catch (_) {
                }
              }
              try {
                port.onDisconnect.__sumiDispatch(port);
              } finally {
                if (didOverrideLastError) {
                  try {
                    if (previousLastErrorDescriptor) {
                      Object.defineProperty(
                        runtime,
                        "lastError",
                        previousLastErrorDescriptor
                      );
                    } else {
                      delete runtime.lastError;
                    }
                  } catch (_) {
                  }
                }
              }
            };

            const handleEvents = (events) => {
              for (const event of Array.isArray(events) ? events : []) {
                if (!event || disconnected) {
                  continue;
                }
                if (event.type === "message") {
                  port.onMessage.__sumiDispatch(event.message, port);
                  continue;
                }
                if (event.type === "disconnect") {
                  handleDisconnect(event.error || null);
                  return;
                }
              }
            };

            const poll = () => {
              if (disconnected) {
                return;
              }
              sendRuntimeMessage(runtime, {
                __sumiRuntimeConnectCompatibility: true,
                runtimeId,
                type: "poll",
                portId
              }, (reply, errorMessage) => {
                if (disconnected) {
                  return;
                }
                if (errorMessage) {
                  pollDelay = Math.min(500, Math.max(100, pollDelay * 2));
                } else {
                  handleEvents(reply && reply.events);
                  pollDelay = reply && Array.isArray(reply.events) && reply.events.length > 0
                    ? 0
                    : 75;
                }
                setTimeout(poll, pollDelay);
              });
            };

            sendRuntimeMessage(runtime, {
              __sumiRuntimeConnectCompatibility: true,
              runtimeId,
              type: "connect",
              portId,
              name,
              connectInfo,
              sender: senderEnvelope()
            }, (reply, errorMessage) => {
              if (errorMessage || !reply || reply.ok !== true) {
                handleDisconnect(errorMessage || (reply && reply.error) || null);
                return;
              }
              poll();
            });

            return port;
          };
          Object.defineProperty(wrappedConnect, "__sumiRuntimeConnectCompatibilityWrapped", {
            value: true,
            configurable: false,
            enumerable: false,
            writable: false
          });
          runtime.connect = wrappedConnect;

          installed[markerValue] = true;
          Object.defineProperty(globalThis, marker, {
            value: installed,
            configurable: true,
            enumerable: false,
            writable: false
          });
          return true;
        };

        let installedAny = false;
        for (const namespaceName of namespaceNames) {
          installedAny = installNamespace(namespaceName) || installedAny;
        }
        return installedAny;
      };

      if (installRuntimeConnectCompatibility()) {
        return;
      }

      let attempts = 0;
      const retry = () => {
        attempts += 1;
        if (installRuntimeConnectCompatibility() || attempts >= 20) {
          return;
        }
        setTimeout(retry, attempts < 4 ? 0 : 25);
      };
      setTimeout(retry, 0);
    })();
    """
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func installRuntimeConnectCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID,
        requireLoadedContext: Bool,
        scopes: Set<SafariExtensionRuntimeConnectCompatibility.PreludeScope>
    ) {
        guard SafariExtensionRuntimeConnectCompatibility
            .isPrivateUserScriptSPIAvailable
        else {
            RuntimeDiagnostics.debug(
                "Runtime connect compatibility SPI unavailable",
                category: "Extensions"
            )
            return
        }

        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            runtimeConnectCompatibilityInstallations[controllerIdentifier] ?? []

        for (extensionId, extensionContext) in extensionContexts(for: profileId) {
            if requireLoadedContext, extensionContext.isLoaded == false {
                continue
            }
            installRuntimeConnectCompatibilityPreludes(
                into: userContentController,
                profileId: profileId,
                extensionId: extensionId,
                extensionContext: extensionContext,
                scopes: scopes,
                installedKeys: &installedKeys
            )
        }

        runtimeConnectCompatibilityInstallations[
            controllerIdentifier
        ] = installedKeys
    }

    func installRuntimeConnectCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID,
        extensionId: String,
        extensionContext: WKWebExtensionContext,
        scopes: Set<SafariExtensionRuntimeConnectCompatibility.PreludeScope>
    ) {
        guard SafariExtensionRuntimeConnectCompatibility
            .isPrivateUserScriptSPIAvailable
        else {
            RuntimeDiagnostics.debug(
                "Runtime connect compatibility SPI unavailable",
                category: "Extensions"
            )
            return
        }

        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            runtimeConnectCompatibilityInstallations[controllerIdentifier] ?? []
        installRuntimeConnectCompatibilityPreludes(
            into: userContentController,
            profileId: profileId,
            extensionId: extensionId,
            extensionContext: extensionContext,
            scopes: scopes,
            installedKeys: &installedKeys
        )
        runtimeConnectCompatibilityInstallations[
            controllerIdentifier
        ] = installedKeys
    }

    private func installRuntimeConnectCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID,
        extensionId: String,
        extensionContext: WKWebExtensionContext,
        scopes: Set<SafariExtensionRuntimeConnectCompatibility.PreludeScope>,
        installedKeys: inout Set<String>
    ) {
        let baseURL = extensionContext.baseURL
        for scope in scopes {
            let installKey = [
                SafariExtensionRuntimeConnectCompatibility.installationSourceIdentifier,
                scope.rawValue,
                profileId.uuidString,
                extensionId,
                baseURL.absoluteString,
            ].joined(separator: ":")
            guard installedKeys.contains(installKey) == false else {
                continue
            }

            if SafariExtensionRuntimeConnectCompatibility.installPrelude(
                into: userContentController,
                extensionContext: extensionContext,
                scope: scope
            ) {
                installedKeys.insert(installKey)
                extensionRuntimeTrace(
                    "runtimeConnectCompatibility installed extensionId=\(extensionId) profileId=\(profileId.uuidString) scope=\(scope.rawValue)"
                )
            }
        }
    }

    func clearRuntimeConnectCompatibilityInstallations() {
        runtimeConnectCompatibilityInstallations.removeAll()
    }
}
