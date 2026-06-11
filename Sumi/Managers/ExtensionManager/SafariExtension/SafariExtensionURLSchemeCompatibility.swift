//
//  SafariExtensionURLSchemeCompatibility.swift
//  Sumi
//
//  WebKit-backed WKWebExtension hosts expose extension resources through the
//  internal webkit-extension: scheme when a custom context baseURL is used.
//  Safari Web Extensions expose safari-web-extension: URLs to extension code.
//  This layer keeps WebKit's loadable internal URLs at resource boundaries while
//  presenting Safari-compatible URLs through common WebExtension JS APIs and URL
//  parsing surfaces.
//

import Foundation
import ObjectiveC.runtime
import WebKit

@available(macOS 15.5, *)
@MainActor
enum SafariExtensionURLSchemeCompatibility {
    enum PreludeScope: String {
        case extensionPage
        case contentScript
    }

    static let installationSourceIdentifier =
        "sumi-webextension-url-scheme-compatibility"

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
                "URL scheme compatibility prelude unavailable for \(extensionContext.uniqueIdentifier) scope=\(scope.rawValue)",
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
        let source = preludeSource(internalBaseURL: extensionContext.baseURL)
        if scope == .contentScript {
            return WKUserScript(
                source: source,
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
            source as NSString,
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

    private static func preludeSource(internalBaseURL: URL) -> String {
        let internalOrigin = internalOriginString(for: internalBaseURL)
        let publicOrigin = internalOrigin.replacingOccurrences(
            of: "webkit-extension://",
            with: "safari-web-extension://"
        )

        return """
        (() => {
          const marker = "__sumiWebExtensionURLSchemeCompatibilityInstalled";
          const internalOrigin = \(javascriptStringLiteral(internalOrigin));
          const publicOrigin = \(javascriptStringLiteral(publicOrigin));
          if (!internalOrigin.startsWith("webkit-extension://") ||
              !publicOrigin.startsWith("safari-web-extension://")) {
            return;
          }

          const installed = globalThis[marker] || {};
          if (installed[internalOrigin] === true) {
            return;
          }
          installed[internalOrigin] = true;
          Object.defineProperty(globalThis, marker, {
            value: installed,
            configurable: true,
            enumerable: false,
            writable: false
          });

          const hasOriginBoundary = (value, origin) => {
            if (typeof value !== "string" || !value.startsWith(origin)) {
              return false;
            }
            const next = value.charAt(origin.length);
            return next === "" || next === "/" || next === "?" || next === "#";
          };

          const translateURLString = (value, fromOrigin, toOrigin) => {
            if (typeof value !== "string" || !hasOriginBoundary(value, fromOrigin)) {
              return value;
            }
            return toOrigin + value.slice(fromOrigin.length);
          };

          const toInternalString = (value) => {
            if (typeof value === "string") {
              return translateURLString(value, publicOrigin, internalOrigin);
            }
            if (value && typeof value.href === "string") {
              return translateURLString(value.href, publicOrigin, internalOrigin);
            }
            return value;
          };

          const toPublicString = (value) => {
            if (typeof value !== "string") {
              return value;
            }
            return translateURLString(value, internalOrigin, publicOrigin);
          };

          const findDescriptor = (object, propertyName) => {
            let current = object;
            while (current) {
              const descriptor = Object.getOwnPropertyDescriptor(current, propertyName);
              if (descriptor) {
                return { owner: current, descriptor };
              }
              current = Object.getPrototypeOf(current);
            }
            return null;
          };

          const translatePostMessageArguments = (argsLike) => {
            const args = Array.prototype.slice.call(argsLike);
            if (typeof args[1] === "string") {
              args[1] = toInternalString(args[1]);
              return args;
            }
            if (args[1] &&
                typeof args[1] === "object" &&
                typeof args[1].targetOrigin === "string") {
              try {
                args[1] = Object.assign({}, args[1], {
                  targetOrigin: toInternalString(args[1].targetOrigin)
                });
              } catch (_) {
              }
            }
            return args;
          };

          const windowProxyToWrappedProxy = new WeakMap();
          const wrappedProxyToWindowProxy = new WeakMap();

          const knownWindowProxy = (value) => {
            if (!value || (typeof value !== "object" && typeof value !== "function")) {
              return value;
            }
            try {
              return windowProxyToWrappedProxy.get(value) || value;
            } catch (_) {
              return value;
            }
          };

          const wrapWindowProxy = (targetWindow) => {
            if (!targetWindow ||
                targetWindow === globalThis ||
                (typeof targetWindow !== "object" &&
                 typeof targetWindow !== "function")) {
              return targetWindow;
            }
            try {
              const existing = windowProxyToWrappedProxy.get(targetWindow);
              if (existing) {
                return existing;
              }
            } catch (_) {
              return targetWindow;
            }

            const proxy = new Proxy(targetWindow, {
              get(target, property, receiver) {
                if (property === "__sumiURLSchemeCompatibilityWindowProxy") {
                  return true;
                }
                if (property === "postMessage") {
                  return function() {
                    const args = translatePostMessageArguments(arguments);
                    const postMessage = Reflect.get(target, "postMessage", receiver);
                    return postMessage.apply(target, args);
                  };
                }
                const value = Reflect.get(target, property, receiver);
                return typeof value === "function" ? value.bind(target) : value;
              },
              set(target, property, value, receiver) {
                return Reflect.set(target, property, value, receiver);
              }
            });

            try {
              windowProxyToWrappedProxy.set(targetWindow, proxy);
              wrappedProxyToWindowProxy.set(proxy, targetWindow);
            } catch (_) {
              return targetWindow;
            }
            return proxy;
          };

          const NativeURL = globalThis.URL;
          if (typeof NativeURL === "function" &&
              NativeURL.__sumiURLSchemeCompatibilityWrapped !== true) {
            const makePublicURLProxy = (url) => new Proxy(url, {
              get(target, property, receiver) {
                if (property === "href") {
                  return toPublicString(target.href);
                }
                if (property === "origin") {
                  return toPublicString(target.origin);
                }
                if (property === "protocol" &&
                    hasOriginBoundary(target.href, internalOrigin)) {
                  return "safari-web-extension:";
                }
                if (property === "toString" || property === "toJSON") {
                  return () => toPublicString(target.href);
                }
                if (property === Symbol.toPrimitive) {
                  return () => toPublicString(target.href);
                }
                const value = Reflect.get(target, property, target);
                return typeof value === "function" ? value.bind(target) : value;
              },
              set(target, property, value, receiver) {
                if (property === "href") {
                  return Reflect.set(
                    target,
                    property,
                    toInternalString(value),
                    target
                  );
                }
                return Reflect.set(target, property, value, target);
              }
            });

            const PublicURL = function(url, base) {
              const parsed = base === undefined
                ? new NativeURL(toInternalString(url))
                : new NativeURL(toInternalString(url), toInternalString(base));
              return hasOriginBoundary(parsed.href, internalOrigin)
                ? makePublicURLProxy(parsed)
                : parsed;
            };

            Object.setPrototypeOf(PublicURL, NativeURL);
            PublicURL.prototype = NativeURL.prototype;
            if (typeof NativeURL.canParse === "function") {
              PublicURL.canParse = (url, base) => {
                try {
                  return base === undefined
                    ? NativeURL.canParse(toInternalString(url))
                    : NativeURL.canParse(toInternalString(url), toInternalString(base));
                } catch (_) {
                  return false;
                }
              };
            }
            if (typeof NativeURL.parse === "function") {
              PublicURL.parse = (url, base) => {
                const parsed = base === undefined
                  ? NativeURL.parse(toInternalString(url))
                  : NativeURL.parse(toInternalString(url), toInternalString(base));
                return parsed && hasOriginBoundary(parsed.href, internalOrigin)
                  ? makePublicURLProxy(parsed)
                  : parsed;
              };
            }
            Object.defineProperty(PublicURL, "__sumiURLSchemeCompatibilityWrapped", {
              value: true,
              configurable: false,
              enumerable: false,
              writable: false
            });
            try {
              globalThis.URL = PublicURL;
            } catch (_) {
            }
          }

          const wrapGetURL = (container) => {
            const runtime = container && container.runtime;
            if (runtime &&
                typeof runtime.getURL === "function" &&
                runtime.getURL.__sumiURLSchemeCompatibilityWrapped !== true) {
              const original = runtime.getURL.bind(runtime);
              const wrapped = function(path) {
                return toPublicString(original(path));
              };
              Object.defineProperty(wrapped, "__sumiURLSchemeCompatibilityWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              try {
                runtime.getURL = wrapped;
              } catch (_) {
              }
            }

            const extensionNamespace = container && container.extension;
            if (extensionNamespace &&
                typeof extensionNamespace.getURL === "function" &&
                extensionNamespace.getURL.__sumiURLSchemeCompatibilityWrapped !== true) {
              const original = extensionNamespace.getURL.bind(extensionNamespace);
              const wrapped = function(path) {
                return toPublicString(original(path));
              };
              Object.defineProperty(wrapped, "__sumiURLSchemeCompatibilityWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              try {
                extensionNamespace.getURL = wrapped;
              } catch (_) {
              }
            }
          };

          const urlAttributeNames = new Set([
            "action",
            "cite",
            "data",
            "formaction",
            "href",
            "poster",
            "src"
          ]);

          const installSetAttributeTranslation = () => {
            const prototype = globalThis.Element && globalThis.Element.prototype;
            if (!prototype ||
                typeof prototype.setAttribute !== "function" ||
                prototype.setAttribute.__sumiURLSchemeCompatibilityWrapped === true) {
              return;
            }
            const original = prototype.setAttribute;
            const wrapped = function(name, value) {
              const attributeName = String(name || "").toLowerCase();
              const translatedValue = urlAttributeNames.has(attributeName)
                ? toInternalString(value)
                : value;
              return original.call(this, name, translatedValue);
            };
            Object.defineProperty(wrapped, "__sumiURLSchemeCompatibilityWrapped", {
              value: true,
              configurable: false,
              enumerable: false,
              writable: false
            });
            try {
              prototype.setAttribute = wrapped;
            } catch (_) {
            }
          };

          const installURLPropertyTranslation = (constructorName, propertyName) => {
            const constructor = globalThis[constructorName];
            const prototype = constructor && constructor.prototype;
            if (!prototype) {
              return;
            }
            const descriptor = Object.getOwnPropertyDescriptor(prototype, propertyName);
            if (!descriptor ||
                typeof descriptor.set !== "function" ||
                descriptor.set.__sumiURLSchemeCompatibilityWrapped === true) {
              return;
            }
            const getter = descriptor.get;
            const setter = descriptor.set;
            const wrappedSetter = function(value) {
              return setter.call(this, toInternalString(value));
            };
            Object.defineProperty(wrappedSetter, "__sumiURLSchemeCompatibilityWrapped", {
              value: true,
              configurable: false,
              enumerable: false,
              writable: false
            });
            try {
              Object.defineProperty(prototype, propertyName, {
                configurable: descriptor.configurable,
                enumerable: descriptor.enumerable,
                get: typeof getter === "function"
                  ? function() { return toPublicString(getter.call(this)); }
                  : getter,
                set: wrappedSetter
              });
            } catch (_) {
            }
          };

          const installResourceBoundaryTranslations = () => {
            installSetAttributeTranslation();
            for (const [constructorName, propertyName] of [
              ["HTMLAnchorElement", "href"],
              ["HTMLAreaElement", "href"],
              ["HTMLBaseElement", "href"],
              ["HTMLEmbedElement", "src"],
              ["HTMLFrameElement", "src"],
              ["HTMLIFrameElement", "src"],
              ["HTMLImageElement", "src"],
              ["HTMLInputElement", "src"],
              ["HTMLLinkElement", "href"],
              ["HTMLMediaElement", "src"],
              ["HTMLObjectElement", "data"],
              ["HTMLScriptElement", "src"],
              ["HTMLSourceElement", "src"],
              ["HTMLTrackElement", "src"]
            ]) {
              installURLPropertyTranslation(constructorName, propertyName);
            }

            if (typeof globalThis.fetch === "function" &&
                globalThis.fetch.__sumiURLSchemeCompatibilityWrapped !== true) {
              const nativeFetch = globalThis.fetch.bind(globalThis);
              const wrappedFetch = function(input, init) {
                return nativeFetch(toInternalString(input), init);
              };
              Object.defineProperty(wrappedFetch, "__sumiURLSchemeCompatibilityWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              try {
                globalThis.fetch = wrappedFetch;
              } catch (_) {
              }
            }

            const xhrPrototype =
              globalThis.XMLHttpRequest && globalThis.XMLHttpRequest.prototype;
            if (xhrPrototype &&
                typeof xhrPrototype.open === "function" &&
                xhrPrototype.open.__sumiURLSchemeCompatibilityWrapped !== true) {
              const nativeOpen = xhrPrototype.open;
              const wrappedOpen = function(method, url) {
                const args = Array.prototype.slice.call(arguments);
                args[1] = toInternalString(url);
                return nativeOpen.apply(this, args);
              };
              Object.defineProperty(wrappedOpen, "__sumiURLSchemeCompatibilityWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              try {
                xhrPrototype.open = wrappedOpen;
              } catch (_) {
              }
            }

            const windowPrototype =
              globalThis.Window && globalThis.Window.prototype;
            if (windowPrototype &&
                typeof windowPrototype.postMessage === "function" &&
                windowPrototype.postMessage.__sumiURLSchemeCompatibilityWrapped !== true) {
              const nativePostMessage = windowPrototype.postMessage;
              const wrappedPostMessage = function() {
                return nativePostMessage.apply(
                  this,
                  translatePostMessageArguments(arguments)
                );
              };
              Object.defineProperty(wrappedPostMessage, "__sumiURLSchemeCompatibilityWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              try {
                windowPrototype.postMessage = wrappedPostMessage;
              } catch (_) {
              }
            }

            for (const [constructorName, propertyName] of [
              ["HTMLFrameElement", "contentWindow"],
              ["HTMLIFrameElement", "contentWindow"],
              ["HTMLObjectElement", "contentWindow"]
            ]) {
              const constructor = globalThis[constructorName];
              const prototype = constructor && constructor.prototype;
              if (!prototype) {
                continue;
              }
              const lookup = findDescriptor(prototype, propertyName);
              const descriptor = lookup && lookup.descriptor;
              if (!lookup ||
                  !descriptor ||
                  typeof descriptor.get !== "function" ||
                  descriptor.get.__sumiURLSchemeCompatibilityWrapped === true ||
                  descriptor.configurable === false) {
                continue;
              }
              const getter = descriptor.get;
              const setter = descriptor.set;
              const wrappedGetter = function() {
                return wrapWindowProxy(getter.call(this));
              };
              Object.defineProperty(wrappedGetter, "__sumiURLSchemeCompatibilityWrapped", {
                value: true,
                configurable: false,
                enumerable: false,
                writable: false
              });
              try {
                Object.defineProperty(lookup.owner, propertyName, {
                  configurable: descriptor.configurable,
                  enumerable: descriptor.enumerable,
                  get: wrappedGetter,
                  set: setter
                });
              } catch (_) {
              }
            }

            if (windowPrototype) {
              for (const propertyName of ["parent", "top", "opener"]) {
                const lookup = findDescriptor(windowPrototype, propertyName);
                const descriptor = lookup && lookup.descriptor;
                if (!lookup ||
                    !descriptor ||
                    typeof descriptor.get !== "function" ||
                    descriptor.get.__sumiURLSchemeCompatibilityWrapped === true ||
                    descriptor.configurable === false) {
                  continue;
                }
                const getter = descriptor.get;
                const setter = descriptor.set;
                const wrappedGetter = function() {
                  return wrapWindowProxy(getter.call(this));
                };
                Object.defineProperty(wrappedGetter, "__sumiURLSchemeCompatibilityWrapped", {
                  value: true,
                  configurable: false,
                  enumerable: false,
                  writable: false
                });
                try {
                  Object.defineProperty(lookup.owner, propertyName, {
                    configurable: descriptor.configurable,
                    enumerable: descriptor.enumerable,
                    get: wrappedGetter,
                    set: setter
                  });
                  void globalThis[propertyName];
                } catch (_) {
                }
              }
            }

            const messageEventPrototype =
              globalThis.MessageEvent && globalThis.MessageEvent.prototype;
            if (messageEventPrototype) {
              const lookup = findDescriptor(messageEventPrototype, "source");
              const descriptor = lookup && lookup.descriptor;
              if (lookup &&
                  descriptor &&
                  typeof descriptor.get === "function" &&
                  descriptor.get.__sumiURLSchemeCompatibilityWrapped !== true &&
                  descriptor.configurable !== false) {
                const getter = descriptor.get;
                const wrappedGetter = function() {
                  return knownWindowProxy(getter.call(this));
                };
                Object.defineProperty(wrappedGetter, "__sumiURLSchemeCompatibilityWrapped", {
                  value: true,
                  configurable: false,
                  enumerable: false,
                  writable: false
                });
                try {
                  Object.defineProperty(lookup.owner, "source", {
                    configurable: descriptor.configurable,
                    enumerable: descriptor.enumerable,
                    get: wrappedGetter
                  });
                } catch (_) {
                }
              }
            }
          };

          const install = () => {
            wrapGetURL(globalThis.browser);
            wrapGetURL(globalThis.chrome);
            installResourceBoundaryTranslations();
          };

          install();
          let attempts = 0;
          const retry = () => {
            attempts += 1;
            install();
            if (attempts < 20) {
              setTimeout(retry, attempts < 4 ? 0 : 25);
            }
          };
          setTimeout(retry, 0);
        })();
        """
    }

    private static func internalOriginString(for baseURL: URL) -> String {
        guard let scheme = baseURL.scheme,
              let host = baseURL.host
        else {
            return baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "\(scheme)://\(host)"
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.first == "[",
              json.last == "]"
        else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func installURLSchemeCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID,
        requireLoadedContext: Bool,
        scopes: Set<SafariExtensionURLSchemeCompatibility.PreludeScope>
    ) {
        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            urlSchemeCompatibilityInstallations[controllerIdentifier] ?? []

        for (extensionId, extensionContext) in extensionContexts(for: profileId) {
            if requireLoadedContext, extensionContext.isLoaded == false {
                continue
            }
            installURLSchemeCompatibilityPreludes(
                into: userContentController,
                profileId: profileId,
                extensionId: extensionId,
                extensionContext: extensionContext,
                scopes: scopes,
                installedKeys: &installedKeys
            )
        }

        urlSchemeCompatibilityInstallations[controllerIdentifier] = installedKeys
    }

    func installURLSchemeCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID,
        extensionId: String,
        extensionContext: WKWebExtensionContext,
        scopes: Set<SafariExtensionURLSchemeCompatibility.PreludeScope>
    ) {
        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            urlSchemeCompatibilityInstallations[controllerIdentifier] ?? []
        installURLSchemeCompatibilityPreludes(
            into: userContentController,
            profileId: profileId,
            extensionId: extensionId,
            extensionContext: extensionContext,
            scopes: scopes,
            installedKeys: &installedKeys
        )
        urlSchemeCompatibilityInstallations[controllerIdentifier] = installedKeys
    }

    private func installURLSchemeCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID,
        extensionId: String,
        extensionContext: WKWebExtensionContext,
        scopes: Set<SafariExtensionURLSchemeCompatibility.PreludeScope>,
        installedKeys: inout Set<String>
    ) {
        let baseURL = extensionContext.baseURL
        for scope in scopes {
            if scope == .extensionPage,
               SafariExtensionURLSchemeCompatibility.isPrivateUserScriptSPIAvailable == false
            {
                RuntimeDiagnostics.debug(
                    "URL scheme compatibility SPI unavailable",
                    category: "Extensions"
                )
                continue
            }

            let installKey = [
                SafariExtensionURLSchemeCompatibility.installationSourceIdentifier,
                scope.rawValue,
                profileId.uuidString,
                extensionId,
                baseURL.absoluteString,
            ].joined(separator: ":")
            guard installedKeys.contains(installKey) == false else {
                continue
            }

            if SafariExtensionURLSchemeCompatibility.installPrelude(
                into: userContentController,
                extensionContext: extensionContext,
                scope: scope
            ) {
                installedKeys.insert(installKey)
                extensionRuntimeTrace(
                    "urlSchemeCompatibility installed extensionId=\(extensionId) profileId=\(profileId.uuidString) scope=\(scope.rawValue)"
                )
            }
        }
    }

    func clearURLSchemeCompatibilityInstallations() {
        urlSchemeCompatibilityInstallations.removeAll()
    }
}
