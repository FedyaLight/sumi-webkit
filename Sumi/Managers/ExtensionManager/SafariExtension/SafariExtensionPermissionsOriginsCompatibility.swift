//
//  SafariExtensionPermissionsOriginsCompatibility.swift
//  Sumi
//
//  Generic WebExtension permissions API compatibility for origin inputs that
//  WebKit rejects before consulting the host's native permission grants.
//

import Foundation
import ObjectiveC.runtime
import WebKit

@available(macOS 15.5, *)
@MainActor
enum SafariExtensionPermissionsOriginsCompatibility {
    static let installationSourceIdentifier =
        "sumi-webextension-permissions-origins-compatibility"

    private static let privateUserScriptSelector = NSSelectorFromString(
        "_initWithSource:injectionTime:forMainFrameOnly:includeMatchPatternStrings:excludeMatchPatternStrings:associatedURL:contentWorld:"
    )
    private static let associatedUserScriptFactory =
        AssociatedUserScriptFactory(selector: privateUserScriptSelector)

    static var isPrivateUserScriptSPIAvailable: Bool {
        associatedUserScriptFactory.isAvailable
    }

    static func installPrelude(
        into userContentController: WKUserContentController,
        extensionContext: WKWebExtensionContext
    ) -> Bool {
        let baseURL = extensionContext.baseURL
        guard let userScript = makePreludeUserScript(associatedURL: baseURL) else {
            RuntimeDiagnostics.debug(
                "Permissions origins compatibility prelude unavailable for \(extensionContext.uniqueIdentifier)",
                category: "Extensions"
            )
            return false
        }

        userContentController.addUserScript(userScript)
        return true
    }

    static func makePreludeUserScript(associatedURL: URL) -> WKUserScript? {
        guard isExtensionAssociatedURL(associatedURL) else {
            return nil
        }

        return associatedUserScriptFactory.makeUserScript(
            source: preludeSource,
            associatedURL: associatedURL,
            includeMatchPatternStrings: includeMatchPatternStrings(for: associatedURL)
        )
    }

    private static func isExtensionAssociatedURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "webkit-extension" || scheme == "safari-web-extension"
    }

    private struct AssociatedUserScriptFactory {
        let selector: Selector

        var isAvailable: Bool {
            WKUserScript.instancesRespond(to: selector)
                && class_getInstanceMethod(WKUserScript.self, selector) != nil
        }

        func makeUserScript(
            source: String,
            associatedURL: URL,
            includeMatchPatternStrings: [String]
        ) -> WKUserScript? {
            guard isAvailable,
                  let method = class_getInstanceMethod(WKUserScript.self, selector),
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
                selector,
                source as NSString,
                WKUserScriptInjectionTime.atDocumentStart.rawValue,
                false,
                includeMatchPatternStrings as NSArray,
                [] as NSArray,
                associatedURL as NSURL,
                nil
            )

            return initialized as? WKUserScript
        }
    }

    static func normalizedOriginsForWebKitPermissionsAPI(
        _ origins: [String]
    ) -> [String] {
        origins.map(normalizedOriginForWebKitPermissionsAPI)
    }

    private static func includeMatchPatternStrings(
        for extensionBaseURL: URL
    ) -> [String] {
        let baseString = extensionBaseURL.absoluteString
        let extensionDocumentPattern =
            baseString.hasSuffix("/") ? "\(baseString)*" : "\(baseString)/*"
        return [
            "<all_urls>",
            extensionDocumentPattern,
        ]
    }

    static func normalizedOriginForWebKitPermissionsAPI(
        _ origin: String
    ) -> String {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return origin }

        if (try? WKWebExtension.MatchPattern(string: trimmed)) != nil {
            return origin
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host.isEmpty == false,
              host.contains(":") == false,
              rawHTTPAuthorityHasPort(in: trimmed)
        else {
            return origin
        }

        return "\(scheme)://\(host)/*"
    }

    private static func rawHTTPAuthorityHasPort(in value: String) -> Bool {
        guard let schemeRange = value.range(of: "://") else { return false }
        let afterScheme = value[schemeRange.upperBound...]
        let authority = afterScheme.split(
            maxSplits: 1,
            whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }
        ).first.map(String.init) ?? ""

        guard authority.isEmpty == false else { return false }
        if authority.hasPrefix("[") {
            return authority.range(of: #"\]:\d+$"#, options: .regularExpression) != nil
        }
        return authority.range(of: #"^[^:]+:\d+$"#, options: .regularExpression) != nil
    }

    private static let preludeSource = """
    (() => {
      if (location.protocol !== "webkit-extension:" &&
          location.protocol !== "safari-web-extension:") {
        return;
      }

      const marker = "__sumiWebExtensionPermissionsOriginsCompatibilityInstalled";
      if (globalThis[marker] === true) {
        return;
      }
      Object.defineProperty(globalThis, marker, {
        value: true,
        configurable: false,
        enumerable: false,
        writable: false
      });

      const normalizeOrigin = (origin) => {
        if (typeof origin !== "string" || origin.length === 0) {
          return origin;
        }
        const trimmed = origin.trim();
        if (trimmed.length === 0) {
          return origin;
        }

        let parsed;
        try {
          parsed = new URL(trimmed);
        } catch (_) {
          return origin;
        }

        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
          return origin;
        }

        const authorityMatch = trimmed.match(/^[A-Za-z][A-Za-z0-9+.-]*:\\/\\/([^/?#]+)/);
        const authority = authorityMatch ? authorityMatch[1] : "";
        const hasPort = /\\]:\\d+$/.test(authority) || /^[^\\[\\]:]+:\\d+$/.test(authority);
        const host = parsed.hostname;
        if (!hasPort || !host || host.includes(":")) {
          return origin;
        }

        return `${parsed.protocol}//${host}/*`;
      };

      const normalizeDetails = (details) => {
        if (!details || typeof details !== "object" || !Array.isArray(details.origins)) {
          return details;
        }

        let changed = false;
        const origins = details.origins.map((origin) => {
          const normalized = normalizeOrigin(origin);
          changed = changed || normalized !== origin;
          return normalized;
        });

        if (!changed) {
          return details;
        }

        return Object.assign({}, details, { origins });
      };

      const wrapPermissionsNamespace = (namespace) => {
        const permissions = namespace && namespace.permissions;
        if (!permissions || typeof permissions !== "object") {
          return;
        }

        for (const name of ["contains", "request", "remove"]) {
          const original = permissions[name];
          if (typeof original !== "function" || original.__sumiOriginsCompatibilityWrapped === true) {
            continue;
          }

          const wrapped = function(details, callback) {
            const normalizedDetails = normalizeDetails(details);
            if (arguments.length > 1) {
              return original.call(this, normalizedDetails, callback);
            }
            return original.call(this, normalizedDetails);
          };

          Object.defineProperty(wrapped, "__sumiOriginsCompatibilityWrapped", {
            value: true,
            configurable: false,
            enumerable: false,
            writable: false
          });

          try {
            permissions[name] = wrapped;
          } catch (_) {
          }
        }
      };

      wrapPermissionsNamespace(globalThis.browser);
      wrapPermissionsNamespace(globalThis.chrome);
    })();
    """
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func installPermissionsOriginsCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID
    ) {
        guard SafariExtensionPermissionsOriginsCompatibility
            .isPrivateUserScriptSPIAvailable
        else {
            RuntimeDiagnostics.debug(
                "Permissions origins compatibility SPI unavailable",
                category: "Extensions"
            )
            return
        }

        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            permissionsOriginsCompatibilityInstallations[controllerIdentifier] ?? []

        for (extensionId, extensionContext) in extensionContexts(for: profileId) {
            guard extensionContext.isLoaded else {
                continue
            }
            let baseURL = extensionContext.baseURL

            let installKey = [
                SafariExtensionPermissionsOriginsCompatibility.installationSourceIdentifier,
                profileId.uuidString,
                extensionId,
                baseURL.absoluteString,
            ].joined(separator: ":")
            guard installedKeys.contains(installKey) == false else {
                continue
            }

            if SafariExtensionPermissionsOriginsCompatibility.installPrelude(
                into: userContentController,
                extensionContext: extensionContext
            ) {
                installedKeys.insert(installKey)
                extensionRuntimeTrace(
                    "permissionsOriginsCompatibility installed extensionId=\(extensionId) profileId=\(profileId.uuidString)"
                )
            }
        }

        permissionsOriginsCompatibilityInstallations[
            controllerIdentifier
        ] = installedKeys
    }

    func clearPermissionsOriginsCompatibilityInstallations() {
        permissionsOriginsCompatibilityInstallations.removeAll()
    }
}
