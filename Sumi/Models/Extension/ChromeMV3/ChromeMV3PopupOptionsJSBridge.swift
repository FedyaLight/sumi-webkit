//
//  ChromeMV3PopupOptionsJSBridge.swift
//  Sumi
//
//  Developer-preview chrome.* JavaScript bridge for extension-owned action
//  popup and options WKWebViews. This bridge is installed only by the
//  popup/options host after Prompt 60 product gates pass. It does not install
//  into product normal tabs, attach content scripts, enable product DNR,
//  display product permission UI, launch native hosts, wake service workers,
//  or make the global MV3 runtime loadable.
//

import CryptoKit
import Foundation

#if canImport(WebKit)
import WebKit
#endif

struct ChromeMV3PopupOptionsBlockedAPIDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var namespace: String
    var methodName: String
    var reason: String
    var remediation: String
    var roadmapOwner: String
    var lastErrorCode: String
    var lastErrorMessage: String
}

struct ChromeMV3PopupOptionsAPIMethodPolicy:
    Codable,
    Equatable,
    Sendable
{
    var exposedNamespaces: [String]
    var blockedNamespaces: [String]
    var allowedMethods: [String]
    var blockedDiagnostics: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]

    static let defaultPolicy = ChromeMV3PopupOptionsAPIMethodPolicy(
        exposedNamespaces: [
            "permissions",
            "runtime",
            "scripting",
            "storage.local",
            "tabs",
        ],
        blockedNamespaces: [
            "declarativeNetRequest",
            "identity",
            "nativeMessaging",
            "offscreen",
            "sidePanel",
            "webRequest",
        ],
        allowedMethods: [
            "permissions.contains",
            "permissions.getAll",
            "permissions.remove",
            "permissions.request",
            "runtime.connect",
            "runtime.connectNative",
            "runtime.getManifest",
            "runtime.getURL",
            "runtime.lastError",
            "runtime.nativePort.disconnect",
            "runtime.nativePort.postMessage",
            "runtime.port.disconnect",
            "runtime.port.postMessage",
            "runtime.sendMessage",
            "runtime.sendNativeMessage",
            "storage.local.clear",
            "storage.local.get",
            "storage.local.getBytesInUse",
            "storage.local.remove",
            "storage.local.set",
            "storage.onChanged",
            "tabs.connect",
            "tabs.port.disconnect",
            "tabs.port.postMessage",
            "tabs.query",
            "tabs.sendMessage",
            "permissions.__sumiPermissionEventListenerCount",
        ],
        blockedDiagnostics: [
            blocked(
                namespace: "tabs",
                methodName: "sendMessage",
                reason:
                    "tabs.sendMessage requires a registered developer-preview content-script endpoint.",
                remediation:
                    "Attach an eligible manifest-declared content script before routing tabs.sendMessage.",
                roadmapOwner: "Prompt 61"
            ),
            blocked(
                namespace: "tabs",
                methodName: "connect",
                reason:
                    "tabs.connect requires a registered developer-preview content-script Port endpoint.",
                remediation:
                    "Attach an eligible manifest-declared content script and register runtime.onConnect before opening a Port.",
                roadmapOwner: "Prompt 61"
            ),
            blocked(
                namespace: "scripting",
                methodName: "executeScript",
                reason:
                    "No explicit safe product target exists for scripting.executeScript in popup/options developer preview.",
                remediation:
                    "Require a safe target policy before enabling scripting execution.",
                roadmapOwner: "Future scripting product prompt"
            ),
            blocked(
                namespace: "runtime",
                methodName: "sendNativeMessage",
                reason:
                    "Arbitrary native messaging hosts are not allowed from popup/options.",
                remediation:
                    "Use fixture/trusted host policy before allowing native messaging.",
                roadmapOwner: "Native messaging product policy"
            ),
            blocked(
                namespace: "runtime",
                methodName: "connect" + "Native",
                reason:
                    "Arbitrary native messaging hosts are not allowed from popup/options.",
                remediation:
                    "Use fixture/trusted host policy before allowing native messaging.",
                roadmapOwner: "Native messaging product policy"
            ),
            blocked(
                namespace: "declarativeNetRequest",
                methodName: "*",
                reason:
                    "Product DNR network enforcement is not enabled by the popup/options bridge.",
                remediation:
                    "Keep network enforcement in compatibility diagnostics until a product policy is implemented.",
                roadmapOwner: "Network enforcement prompt"
            ),
            blocked(
                namespace: "webRequest",
                methodName: "*",
                reason:
                    "Product webRequest enforcement is not enabled by the popup/options bridge.",
                remediation:
                    "Keep network enforcement in compatibility diagnostics until a product policy is implemented.",
                roadmapOwner: "Network enforcement prompt"
            ),
            blocked(
                namespace: "sidePanel",
                methodName: "*",
                reason:
                    "Product sidePanel runtime is unavailable for popup/options developer preview.",
                remediation:
                    "Keep sidePanel diagnostics synthetic/product-blocked.",
                roadmapOwner: "sidePanel runtime prompt"
            ),
            blocked(
                namespace: "offscreen",
                methodName: "*",
                reason:
                    "Product offscreen runtime is unavailable for popup/options developer preview.",
                remediation:
                    "Keep offscreen diagnostics synthetic/product-blocked.",
                roadmapOwner: "offscreen runtime prompt"
            ),
            blocked(
                namespace: "identity",
                methodName: "*",
                reason:
                    "Product identity runtime is unavailable for popup/options developer preview.",
                remediation:
                    "Keep identity diagnostics synthetic/product-blocked.",
                roadmapOwner: "identity runtime prompt"
            ),
            blocked(
                namespace: "unsupported",
                methodName: "*",
                reason:
                    "The requested Chrome extension API is not in the popup/options allowlist.",
                remediation:
                    "Add an explicit API contract before exposing another namespace or method.",
                roadmapOwner: "MV3 bridge owner"
            ),
        ].sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace < $1.namespace
            }
            return $0.methodName < $1.methodName
        }
    )

    static let controlledActionPopupPolicy =
        ChromeMV3PopupOptionsAPIMethodPolicy(
            exposedNamespaces: {
                var namespaces = [
                    "i18n",
                    "runtime",
                    "storage.local",
                    "storage.session",
                    "storage.sync",
                    "tabs",
                ]
                #if DEBUG
                namespaces.append("extension")
                #endif
                return namespaces
            }(),
            blockedNamespaces: [
                "contextMenus",
                "declarativeNetRequest",
                "identity",
                "nativeMessaging",
                "offscreen",
                "permissions",
                "sidePanel",
                "scripting",
                "webRequest",
            ],
            allowedMethods: {
                var methods = [
                    "i18n.getMessage",
                    "i18n.getUILanguage",
                    "runtime.connect",
                    "runtime.getManifest",
                    "runtime.getURL",
                    "runtime.lastError",
                    "runtime.port.disconnect",
                    "runtime.port.postMessage",
                    "runtime.sendMessage",
                    "storage.local.clear",
                    "storage.local.get",
                    "storage.local.getBytesInUse",
                    "storage.local.onChanged",
                    "storage.local.remove",
                    "storage.local.set",
                    "storage.onChanged",
                    "storage.session.clear",
                    "storage.session.get",
                    "storage.session.getBytesInUse",
                    "storage.session.onChanged",
                    "storage.session.remove",
                    "storage.session.set",
                    "storage.sync.clear",
                    "storage.sync.get",
                    "storage.sync.getBytesInUse",
                    "storage.sync.onChanged",
                    "storage.sync.remove",
                    "storage.sync.set",
                    "tabs.query",
                    "tabs.sendMessage",
                ]
                #if DEBUG
                methods.append("extension.getBackgroundPage")
                methods.append("runtime.onMessage")
                methods.append("tabs.getCurrent")
                #endif
                return methods
            }(),
            blockedDiagnostics: (
                [
                    blocked(
                        namespace: "runtime",
                        methodName: "sendNativeMessage",
                        reason:
                            "Native messaging is not exposed by the controlled action popup host.",
                        remediation:
                            "Keep native messaging unavailable until a separate trusted-host product policy exists.",
                        roadmapOwner: "Native messaging product policy"
                    ),
                    blocked(
                        namespace: "runtime",
                        methodName: "connect" + "Native",
                        reason:
                            "Native messaging Ports are not exposed by the controlled action popup host.",
                        remediation:
                            "Keep native messaging unavailable until a separate trusted-host product policy exists.",
                        roadmapOwner: "Native messaging product policy"
                    ),
                    blocked(
                        namespace: "permissions",
                        methodName: "*",
                        reason:
                            "permissions.* is not exposed by the controlled action popup host.",
                        remediation:
                            "Add permissions UI/runtime support through a separate reviewed implementation prompt.",
                        roadmapOwner: "Permissions product prompt"
                    ),
                    blocked(
                        namespace: "scripting",
                        methodName: "*",
                        reason:
                            "scripting.* is not exposed by the controlled action popup host.",
                        remediation:
                            "Add scripting only after a safe target policy exists.",
                        roadmapOwner: "Future scripting product prompt"
                    ),
                    blocked(
                        namespace: "contextMenus",
                        methodName: "*",
                        reason:
                            "contextMenus is outside this controlled action popup increment.",
                        remediation:
                            "Add contextMenus through a separate reviewed implementation prompt.",
                        roadmapOwner: "MV3 bridge owner"
                    ),
                    blocked(
                        namespace: "unsupported",
                        methodName: "*",
                        reason:
                            "The requested Chrome extension API is not in the controlled action popup allowlist.",
                        remediation:
                            "Add an explicit API contract before exposing another namespace or method.",
                        roadmapOwner: "MV3 bridge owner",
                        code: .unsupportedAPI
                    ),
                ]
                + defaultPolicy.blockedDiagnostics.filter {
                    [
                        "declarativeNetRequest",
                        "identity",
                        "nativeMessaging",
                        "offscreen",
                        "sidePanel",
                        "webRequest",
                    ].contains($0.namespace)
                }
            ).sorted {
                if $0.namespace != $1.namespace {
                    return $0.namespace < $1.namespace
                }
                return $0.methodName < $1.methodName
            }
        )

    static var defaultBlockedAPIIDs: [String] {
        defaultPolicy.blockedDiagnostics.map {
            "\($0.namespace).\($0.methodName)"
        }
    }

    static func blocked(
        namespace: String,
        methodName: String,
        reason: String,
        remediation: String,
        roadmapOwner: String,
        code: ChromeMV3JSBridgeErrorCode = .productBlocked
    ) -> ChromeMV3PopupOptionsBlockedAPIDiagnostic {
        ChromeMV3PopupOptionsBlockedAPIDiagnostic(
            namespace: namespace,
            methodName: methodName,
            reason: reason,
            remediation: remediation,
            roadmapOwner: roadmapOwner,
            lastErrorCode: code.rawValue,
            lastErrorMessage: code.lastErrorMessage
        )
    }

    func blockedDiagnostic(
        namespace: String,
        methodName: String
    ) -> ChromeMV3PopupOptionsBlockedAPIDiagnostic {
        blockedDiagnostics.first {
            $0.namespace == namespace && $0.methodName == methodName
        } ?? blockedDiagnostics.first {
            $0.namespace == namespace
                && $0.methodName.hasSuffix(".*")
                && methodName.hasPrefix(
                    String($0.methodName.dropLast(2)) + "."
                )
        } ?? blockedDiagnostics.first {
            $0.namespace == namespace && $0.methodName == "*"
        } ?? blockedDiagnostics.first {
            $0.namespace == "unsupported"
        } ?? Self.blocked(
            namespace: namespace,
            methodName: methodName,
            reason:
                "The requested Chrome extension API is not in the popup/options allowlist.",
            remediation:
                "Add an explicit API contract before exposing another namespace or method.",
            roadmapOwner: "MV3 bridge owner",
            code: .unsupportedAPI
        )
    }
}

struct ChromeMV3PopupOptionsRuntimeManifestSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var manifestPayload: ChromeMV3StorageValue
    var topLevelKeyCount: Int
    var safeTopLevelFieldNames: [String]
    var manifestVersion: Int?
    var diagnostics: [String]

    static func fromGeneratedBundleRootPath(
        _ rootPath: String?
    ) -> ChromeMV3PopupOptionsRuntimeManifestSnapshot? {
        guard let rootPath, rootPath.isEmpty == false else { return nil }
        let manifestURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        return fromManifestData(data)
    }

    static func fromManifestData(
        _ data: Data
    ) -> ChromeMV3PopupOptionsRuntimeManifestSnapshot? {
        guard let decoded = try? JSONDecoder().decode(
            ChromeMV3StorageValue.self,
            from: data
        ) else { return nil }
        return fromManifestPayload(decoded)
    }

    static func fromManifestPayload(
        _ payload: ChromeMV3StorageValue
    ) -> ChromeMV3PopupOptionsRuntimeManifestSnapshot? {
        let sanitized = sanitizedManifestValue(payload)
        guard case .object(let object) = sanitized else { return nil }
        let fieldNames = safeTopLevelManifestFieldNames(object.keys)
        let manifestVersion = manifestVersionValue(object["manifest_version"])
        return ChromeMV3PopupOptionsRuntimeManifestSnapshot(
            manifestPayload: sanitized,
            topLevelKeyCount: object.count,
            safeTopLevelFieldNames: fieldNames,
            manifestVersion: manifestVersion,
            diagnostics:
                uniqueSortedPopupOptionsBridge([
                    "method=runtime.getManifest",
                    "topLevelManifestKeyCount=\(object.count)",
                    "safeTopLevelManifestFields=\(fieldNames.joined(separator: ","))",
                    "manifestVersion=\(manifestVersion.map(String.init) ?? "unknown")",
                    "succeeded=true",
                    "resultClassifier=manifestReturned",
                    "runtime.getManifest source=generated-package-manifest-json.",
                    "runtime.getManifest diagnostics omit manifest body and host filesystem paths.",
                ])
        )
    }

    private static func sanitizedManifestValue(
        _ value: ChromeMV3StorageValue
    ) -> ChromeMV3StorageValue {
        switch value {
        case .array(let values):
            return .array(values.map(sanitizedManifestValue))
        case .object(let object):
            return .object(sanitizedManifestObject(object))
        case .bool, .null, .number, .string:
            return value
        }
    }

    private static func sanitizedManifestObject(
        _ object: [String: ChromeMV3StorageValue]
    ) -> [String: ChromeMV3StorageValue] {
        object.reduce(into: [:]) { result, entry in
            guard isManifestKeyExposable(entry.key) else { return }
            result[entry.key] = sanitizedManifestValue(entry.value)
        }
    }

    private static func isManifestKeyExposable(_ key: String) -> Bool {
        let lower = key.lowercased()
        let blockedExact: Set<String> = [
            "diagnostics",
            "generatedbundlerootpath",
            "generatedmanifestpath",
            "generatedmanifestsha256",
            "generatedmetadatapath",
            "generatedresourcepath",
            "generatedrewrittenbundlepath",
            "generatorversion",
            "manifestrewritedryrundirectorypath",
            "manifestrewritedryrunreportpath",
            "manifestrewritepreviewpath",
            "manifestsha256",
            "managerstorerootpath",
            "originalbundlepath",
            "originalbundlerootpath",
            "profileid",
            "profilerootpath",
            "runtimeresourceplanpath",
            "sourcesha256",
            "storagelocalrootpath",
            "truststate",
        ]
        guard blockedExact.contains(lower) == false else { return false }
        return lower.hasPrefix("_sumi") == false
            && lower.hasPrefix("sumi_") == false
    }

    private static func safeTopLevelManifestFieldNames(
        _ keys: Dictionary<String, ChromeMV3StorageValue>.Keys
    ) -> [String] {
        keys
            .filter { key in
                key.range(
                    of: #"^[A-Za-z0-9_.:-]{1,80}$"#,
                    options: .regularExpression
                ) != nil && containsSensitiveManifestFragment(key) == false
            }
            .sorted()
    }

    private static func containsSensitiveManifestFragment(
        _ value: String
    ) -> Bool {
        let lower = value.lowercased()
        return [
            "cookie",
            "credential",
            "password",
            "secret",
            "sessionid",
            "token",
            "vault",
        ].contains { lower.contains($0) }
    }

    private static func manifestVersionValue(
        _ value: ChromeMV3StorageValue?
    ) -> Int? {
        guard case .number(let number)? = value,
              number.isFinite,
              number.rounded() == number,
              number >= 0,
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}

struct ChromeMV3PopupOptionsI18nMessageRecord:
    Codable,
    Equatable,
    Sendable
{
    var message: String
    var placeholders: [String: String]

    var foundationObject: [String: Any] {
        [
            "message": message,
            "placeholders": placeholders,
        ]
    }
}

struct ChromeMV3PopupOptionsI18nCatalogSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var uiLanguage: String
    var defaultLocaleDirectory: String?
    var localeSearchOrder: [String]
    var loadedCatalogLocales: [String]
    var catalogs:
        [String: [String: ChromeMV3PopupOptionsI18nMessageRecord]]
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "uiLanguage": uiLanguage,
            "defaultLocale": defaultLocaleDirectory as Any,
            "localeSearchOrder": localeSearchOrder,
            "loadedCatalogLocales": loadedCatalogLocales,
            "catalogs": catalogs.mapValues {
                $0.mapValues(\.foundationObject)
            },
        ]
    }

    static func fromGeneratedBundleRootPath(
        _ rootPath: String?,
        runtimeManifest: ChromeMV3PopupOptionsRuntimeManifestSnapshot?,
        uiLanguageOverride: String? = nil
    ) -> ChromeMV3PopupOptionsI18nCatalogSnapshot? {
        guard let rootPath, rootPath.isEmpty == false else { return nil }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard rootDirectoryIsUsable(rootURL) else {
            return emptySnapshot(
                uiLanguageOverride: uiLanguageOverride,
                diagnostics: [
                    "method=chrome.i18n.catalogSnapshot",
                    "generatedPackageRootUsable=false",
                    "i18nCatalogSnapshotResult=catalogRootUnavailable",
                    "No raw localized message values are recorded.",
                ]
            )
        }

        let uiLanguage = chromeUILanguage(uiLanguageOverride)
        let defaultLocaleDirectory = manifestDefaultLocaleDirectory(
            runtimeManifest
        )
        let localeSearchOrder = uniqueLocaleSearchOrder(
            uiLanguage: uiLanguage,
            defaultLocaleDirectory: defaultLocaleDirectory
        )
        let loadedCatalogs = localeSearchOrder.reduce(
            into:
                [String: [String: ChromeMV3PopupOptionsI18nMessageRecord]]()
        ) { result, localeDirectory in
            if let catalog = loadCatalog(
                rootURL: rootURL,
                localeDirectory: localeDirectory
            ), catalog.isEmpty == false {
                result[localeDirectory] = catalog
            }
        }
        let loadedCatalogLocales = localeSearchOrder.filter {
            loadedCatalogs[$0] != nil
        }
        let primaryLocale = loadedCatalogLocales.first ?? "none"
        let fallbackLocaleUsed =
            loadedCatalogLocales.first.map { firstLoaded in
                firstLoaded != localeSearchOrder.first
            } ?? false
        let catalogMessageCounts = loadedCatalogLocales.map {
            "\($0)=\(loadedCatalogs[$0]?.count ?? 0)"
        }
        let diagnostics = uniqueSortedPopupOptionsBridge([
            "method=chrome.i18n.catalogSnapshot",
            "uiLanguage=\(uiLanguage)",
            "defaultLocale=\(defaultLocaleDirectory ?? "none")",
            "primaryLocale=\(primaryLocale)",
            "fallbackLocaleUsed=\(fallbackLocaleUsed)",
            "localeSearchOrderCount=\(localeSearchOrder.count)",
            "loadedCatalogLocaleCount=\(loadedCatalogLocales.count)",
            "catalogMessageCounts=\(catalogMessageCounts.joined(separator: ","))",
            "generatedPackageRootUsable=true",
            "i18nCatalogSnapshotResult=i18nCatalogSnapshotLoaded",
            "No raw localized message values are recorded.",
        ])
        return ChromeMV3PopupOptionsI18nCatalogSnapshot(
            uiLanguage: uiLanguage,
            defaultLocaleDirectory: defaultLocaleDirectory,
            localeSearchOrder: localeSearchOrder,
            loadedCatalogLocales: loadedCatalogLocales,
            catalogs: loadedCatalogs,
            diagnostics: diagnostics
        )
    }

    private static func emptySnapshot(
        uiLanguageOverride: String?,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsI18nCatalogSnapshot {
        let uiLanguage = chromeUILanguage(uiLanguageOverride)
        return ChromeMV3PopupOptionsI18nCatalogSnapshot(
            uiLanguage: uiLanguage,
            defaultLocaleDirectory: nil,
            localeSearchOrder: [],
            loadedCatalogLocales: [],
            catalogs: [:],
            diagnostics: uniqueSortedPopupOptionsBridge(diagnostics + [
                "uiLanguage=\(uiLanguage)",
                "localeSearchOrderCount=0",
                "loadedCatalogLocaleCount=0",
            ])
        )
    }

    private static func rootDirectoryIsUsable(_ rootURL: URL) -> Bool {
        guard rootURL.path.isEmpty == false,
              isSymbolicLink(rootURL) == false
        else { return false }
        let values = try? rootURL.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private static func manifestDefaultLocaleDirectory(
        _ runtimeManifest: ChromeMV3PopupOptionsRuntimeManifestSnapshot?
    ) -> String? {
        guard let object = runtimeManifest?.manifestPayload.objectValue,
              let rawDefaultLocale = object["default_locale"]?.stringValue
        else { return nil }
        return normalizedLocaleDirectory(rawDefaultLocale)
    }

    private static func chromeUILanguage(
        _ override: String?
    ) -> String {
        let raw =
            override?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? Locale.preferredLanguages.first
            ?? Locale.current.identifier
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard normalized.range(
            of: #"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,3}$"#,
            options: .regularExpression
        ) != nil else {
            return "en-US"
        }
        let pieces = normalized.split(separator: "-").map(String.init)
        guard let language = pieces.first?.lowercased(),
              language.isEmpty == false
        else { return "en-US" }
        let tail = pieces.dropFirst().map { piece -> String in
            if piece.count == 2 {
                return piece.uppercased()
            }
            return piece
        }
        return ([language] + tail).joined(separator: "-")
    }

    private static func uniqueLocaleSearchOrder(
        uiLanguage: String,
        defaultLocaleDirectory: String?
    ) -> [String] {
        let uiDirectory = normalizedLocaleDirectory(uiLanguage)
        let languageDirectory = uiDirectory?
            .split(separator: "_")
            .first
            .map(String.init)
        return uniqueSortedPreservingOrderPopupOptionsBridge([
            uiDirectory,
            languageDirectory,
            defaultLocaleDirectory,
        ].compactMap { $0 })
    }

    private static func normalizedLocaleDirectory(
        _ rawValue: String
    ) -> String? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
        guard normalized.range(
            of: #"^[A-Za-z]{2,3}(?:_[A-Za-z0-9]{2,8}){0,3}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        let pieces = normalized.split(separator: "_").map(String.init)
        guard let language = pieces.first?.lowercased(),
              language.isEmpty == false
        else { return nil }
        let tail = pieces.dropFirst().map { piece -> String in
            if piece.count == 2 {
                return piece.uppercased()
            }
            return piece
        }
        return ([language] + tail).joined(separator: "_")
    }

    private static func loadCatalog(
        rootURL: URL,
        localeDirectory: String
    ) -> [String: ChromeMV3PopupOptionsI18nMessageRecord]? {
        guard let catalogURL = safeCatalogURL(
            rootURL: rootURL,
            localeDirectory: localeDirectory
        ) else { return nil }
        let values = try? catalogURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= 2_000_000,
              let data = try? Data(contentsOf: catalogURL),
              data.count <= 2_000_000,
              let decoded = try? JSONDecoder().decode(
                ChromeMV3StorageValue.self,
                from: data
              ),
              let rootObject = decoded.objectValue
        else { return nil }
        return parseCatalogRoot(rootObject)
    }

    private static func safeCatalogURL(
        rootURL: URL,
        localeDirectory: String
    ) -> URL? {
        guard normalizedLocaleDirectory(localeDirectory) == localeDirectory
        else { return nil }
        let localesURL = rootURL.appendingPathComponent(
            "_locales",
            isDirectory: true
        )
        let localeURL = localesURL.appendingPathComponent(
            localeDirectory,
            isDirectory: true
        )
        let catalogURL = localeURL.appendingPathComponent(
            "messages.json",
            isDirectory: false
        )
        guard url(catalogURL, isInsideRootURL: rootURL),
              isSymbolicLink(localesURL) == false,
              isSymbolicLink(localeURL) == false,
              isSymbolicLink(catalogURL) == false
        else { return nil }
        return catalogURL
    }

    private static func url(_ url: URL, isInsideRootURL rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }

    private static func parseCatalogRoot(
        _ rootObject: [String: ChromeMV3StorageValue]
    ) -> [String: ChromeMV3PopupOptionsI18nMessageRecord] {
        rootObject.reduce(into: [:]) { result, entry in
            guard let messageKey = normalizedMessageKey(entry.key),
                  let messageObject = entry.value.objectValue,
                  let message = messageObject["message"]?.stringValue
            else { return }
            let placeholders = parsePlaceholders(
                messageObject["placeholders"]?.objectValue
            )
            result[messageKey] = ChromeMV3PopupOptionsI18nMessageRecord(
                message: message,
                placeholders: placeholders
            )
        }
    }

    private static func parsePlaceholders(
        _ placeholdersObject: [String: ChromeMV3StorageValue]?
    ) -> [String: String] {
        guard let placeholdersObject else { return [:] }
        return placeholdersObject.reduce(into: [:]) { result, entry in
            guard let placeholderKey = normalizedMessageKey(entry.key),
                  let placeholderObject = entry.value.objectValue,
                  let content = placeholderObject["content"]?.stringValue
            else { return }
            result[placeholderKey] = content
        }
    }

    private static func normalizedMessageKey(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(
            of: #"^[A-Za-z0-9_@.-]{1,160}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return trimmed.lowercased()
    }
}

struct ChromeMV3PopupOptionsJSBridgeConfiguration:
    Codable,
    Equatable,
    Sendable
{
    static let productNormalTabBridgeInstallationGuard =
        "popupOptionsJSBridgeNeverInstalledInProductNormalTabWebViews"
    static let contentScriptProductAttachmentGuard =
        "popupOptionsJSBridgeDoesNotAttachProductContentScripts"

    var extensionID: String
    var profileID: String
    var surfaceID: String
    var surface: ChromeMV3ProductPopupOptionsSurface
    var extensionBaseURLString: String
    var permissionStateRootPath: String?
    var storageLocalRootPath: String? = nil
    var storageSyncRootPath: String? = nil
    var nativeMessagingFixtureHostRootPaths: [String] = []
    var nativeMessagingTrustedHostPolicyRootPath: String?
    var nativeMessagingTrustedHostApprovalRecords:
        [ChromeMV3NativeTrustedHostApprovalRecord] = []
    var nativeMessagingProductPolicy:
        ChromeMV3NativeMessagingProductPolicy = .blockedRuntimeDefault
    var moduleState: ChromeMV3ProfileHostModuleState
    var bridgeAvailable: Bool
    var popupOptionsJSBridgeAvailableInDeveloperPreview: Bool
    var popupOptionsJSBridgeAvailableInPublicProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var runtimeLoadable: Bool
    var runtimeManifest: ChromeMV3PopupOptionsRuntimeManifestSnapshot? = nil
    var i18nCatalogSnapshot:
        ChromeMV3PopupOptionsI18nCatalogSnapshot? = nil
    var manifestPermissions: [String]
    var manifestOptionalPermissions: [String]
    var manifestHostPermissions: [String]
    var manifestOptionalHostPermissions: [String]
    var activeTabGrants: [ChromeMV3ActiveTabGrant]
    var allowlist: ChromeMV3PopupOptionsAPIMethodPolicy
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surface == .actionPopup ? .actionPopup : .optionsPage
    }

    static func make(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        let surfaceID = [
            launchRecord.profileID,
            launchRecord.extensionID,
            launchRecord.surface.rawValue,
            launchRecord.generatedBundleVersionID ?? "no-version",
        ].joined(separator: ":")
        let bridgeAvailable =
            launchRecord.canOpen
                && launchRecord.gateRecord
                .popupOptionsJSBridgeAvailableInDeveloperPreview
        let runtimeManifest =
            ChromeMV3PopupOptionsRuntimeManifestSnapshot
            .fromGeneratedBundleRootPath(
                launchRecord.generatedRewrittenBundlePath
            )
        let i18nCatalogSnapshot =
            bridgeAvailable
                && launchRecord.apiMethodPolicy.exposedNamespaces
                .contains("i18n")
                && launchRecord.apiMethodPolicy.allowedMethods
                .contains("i18n.getMessage")
                && launchRecord.apiMethodPolicy.allowedMethods
                .contains("i18n.getUILanguage")
            ? ChromeMV3PopupOptionsI18nCatalogSnapshot
                .fromGeneratedBundleRootPath(
                    launchRecord.generatedRewrittenBundlePath,
                    runtimeManifest: runtimeManifest
                )
            : nil
        return ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: launchRecord.extensionID,
            profileID: launchRecord.profileID,
            surfaceID: surfaceID,
            surface: launchRecord.surface,
            extensionBaseURLString:
                "chrome-extension://\(launchRecord.extensionID)/",
            permissionStateRootPath: launchRecord.managerStoreRootPath,
            storageLocalRootPath:
                launchRecord.managerStoreRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                        .appendingPathComponent(
                            "DeveloperPreviewStorageLocal",
                            isDirectory: true
                        )
                        .path
                },
            storageSyncRootPath:
                launchRecord.managerStoreRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                        .appendingPathComponent(
                            "DeveloperPreviewStorageSyncLocalCompatibility",
                            isDirectory: true
                        )
                        .path
                },
            nativeMessagingFixtureHostRootPaths:
                launchRecord.managerStoreRootPath.map {
                    [
                        URL(fileURLWithPath: $0, isDirectory: true)
                            .appendingPathComponent(
                                "NativeMessagingFixtureHosts",
                                isDirectory: true
                            )
                            .path,
                    ]
                } ?? [],
            nativeMessagingTrustedHostPolicyRootPath:
                launchRecord.managerStoreRootPath,
            nativeMessagingTrustedHostApprovalRecords: [],
            nativeMessagingProductPolicy: .blockedRuntimeDefault,
            moduleState: bridgeAvailable ? .enabled : .disabled,
            bridgeAvailable: bridgeAvailable,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                bridgeAvailable,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            runtimeManifest: runtimeManifest,
            i18nCatalogSnapshot: i18nCatalogSnapshot,
            manifestPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestPermissions
                ),
            manifestOptionalPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestOptionalPermissions
                ),
            manifestHostPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestHostPermissions
                ),
            manifestOptionalHostPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestOptionalHostPermissions
                ),
            activeTabGrants:
                Self.activeTabGrantsForExplicitActionPopupOpen(
                    launchRecord: launchRecord,
                    bridgeAvailable: bridgeAvailable
                ),
            allowlist: launchRecord.apiMethodPolicy,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    [
                    bridgeAvailable
                        ? "Popup/options JS bridge is available only for this extension-owned developer-preview WebView."
                        : "Popup/options JS bridge is unavailable because launch gates did not pass.",
                    i18nCatalogSnapshot == nil
                        ? "chrome.i18n remains unavailable for this popup/options bridge policy."
                        : "chrome.i18n is available only for this controlled popup/options bridge policy.",
                    "Public product popup/options bridge remains unavailable.",
                    "Normal-tab runtime bridge remains unavailable.",
                    "Content-script product attachment remains unavailable.",
                    "runtimeLoadable remains false.",
                    Self.productNormalTabBridgeInstallationGuard,
                    Self.contentScriptProductAttachmentGuard,
                    ]
                    + (i18nCatalogSnapshot?.diagnostics ?? [])
                )
        )
    }

    private static func activeTabGrantsForExplicitActionPopupOpen(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord,
        bridgeAvailable: Bool
    ) -> [ChromeMV3ActiveTabGrant] {
        guard bridgeAvailable,
              launchRecord.surface == .actionPopup,
              launchRecord.manifestPermissions.contains("activeTab")
        else { return [] }
        return [
            ChromeMV3ActiveTabGrant(
                extensionID: launchRecord.extensionID,
                profileID: launchRecord.profileID,
                tabID: 1,
                scope: .origin("https://example.com"),
                reason: .actionClick,
                userGestureModeled: true,
                createdSequence: 1,
                diagnostics: [
                    "Developer-preview activeTab grant created from explicit action popup open.",
                    "Grant is scoped to the controlled synthetic active tab fixture and expires through lifecycle events.",
                ]
            ),
        ]
    }
}

struct ChromeMV3PopupOptionsJSBridgeInstallation:
    Codable,
    Equatable,
    Sendable
{
    var configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    var allowlist: ChromeMV3PopupOptionsAPIMethodPolicy
    var bridgeAvailable: Bool
    var scriptSource: String?
    var messageHandlerName: String
    var diagnostics: [String]
    #if DEBUG
    var hostDiagnosticEvents: [ChromeMV3PopupOptionsHostDiagnosticEvent] = []
    #endif

    static func make(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> ChromeMV3PopupOptionsJSBridgeInstallation {
        let configuration =
            ChromeMV3PopupOptionsJSBridgeConfiguration.make(
                launchRecord: launchRecord
            )
        let scriptSource = configuration.bridgeAvailable
            ? ChromeMV3PopupOptionsJSShimSource.source(
                configuration: configuration
            )
            : nil
        #if DEBUG
        return ChromeMV3PopupOptionsJSBridgeInstallation(
            configuration: configuration,
            allowlist: configuration.allowlist,
            bridgeAvailable: configuration.bridgeAvailable,
            scriptSource: scriptSource,
            messageHandlerName:
                ChromeMV3PopupOptionsJSShimSource.bridgeMessageHandlerName,
            diagnostics: configuration.diagnostics,
            hostDiagnosticEvents:
                ChromeMV3PopupOptionsHostDiagnostics.preloadEvents(
                    launchRecord: launchRecord
                )
        )
        #else
        return ChromeMV3PopupOptionsJSBridgeInstallation(
            configuration: configuration,
            allowlist: configuration.allowlist,
            bridgeAvailable: configuration.bridgeAvailable,
            scriptSource: scriptSource,
            messageHandlerName:
                ChromeMV3PopupOptionsJSShimSource.bridgeMessageHandlerName,
            diagnostics: configuration.diagnostics
        )
        #endif
    }
}

struct ChromeMV3PopupOptionsJSBridgeCallRecord:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var extensionID: String
    var profileID: String
    var surface: ChromeMV3ProductPopupOptionsSurface
    var sourceContext: ChromeMV3JSBridgeSourceContext
    var namespace: String
    var methodName: String
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var argumentShapeSummary: String
    var succeeded: Bool
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var serviceWorkerWakeAttempted: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var nativeHostLaunchAttempted: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var diagnostics: [String]
}

struct ChromeMV3PopupOptionsSanitizedBridgeRouteRecord:
    Codable,
    Equatable,
    Sendable
{
    var extensionIDHash: String
    var profileID: String
    var sourceContext: String
    var targetContext: String
    var apiName: String
    var safeMessageShapeClassification: String
    var safeCommandTypeActionFieldNames: [String]
    var listenerCount: Int
    var listenerInvoked: Bool
    var sendResponseCalled: Bool
    var listenerReturnedTrue: Bool
    var listenerThrew: Bool
    var portName: String?
    var portMessageCount: Int
    var resultClassifier: String
    var firstMissingAPIOrPermissionOrLifecycleError: String?
    var diagnostics: [String]
}

struct ChromeMV3PopupOptionsJSDebugRouteEventRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var eventKind: String
    var apiName: String
    var bridgeCallID: String?
    var invocationMode: String?
    var sourceContext: String
    var targetContext: String?
    var safeMessageShapeClassification: String
    var safeCommandTypeActionFieldNames: [String]
    var portName: String?
    var ageMilliseconds: Int?
    var resultClassifier: String?
    var firstMissingAPIOrPermissionOrLifecycleError: String?
    var diagnostics: [String]
}

#if DEBUG
struct ChromeMV3PopupOptionsHostDiagnosticEvent:
    Codable,
    Equatable,
    Sendable
{
    var eventKind: String
    var apiName: String
    var targetContext: String
    var safeMessageShapeClassification: String
    var resultClassifier: String?
    var firstMissingAPIOrPermissionOrLifecycleError: String?
    var diagnostics: [String]

    init(
        eventKind: String,
        apiName: String,
        targetContext: String,
        safeMessageShapeClassification: String = "hostDiagnostic",
        resultClassifier: String? = nil,
        firstMissingAPIOrPermissionOrLifecycleError: String? = nil,
        diagnostics: [String]
    ) {
        self.eventKind = eventKind
        self.apiName = apiName
        self.targetContext = targetContext
        self.safeMessageShapeClassification =
            safeMessageShapeClassification
        self.resultClassifier = resultClassifier
        self.firstMissingAPIOrPermissionOrLifecycleError =
            firstMissingAPIOrPermissionOrLifecycleError
        self.diagnostics = diagnostics
    }
}

enum ChromeMV3PopupOptionsHostDiagnostics {
    static func preloadEvents(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> [ChromeMV3PopupOptionsHostDiagnosticEvent] {
        guard launchRecord.surface == .actionPopup else { return [] }
        var events: [ChromeMV3PopupOptionsHostDiagnosticEvent] = []
        let rootURL = launchRecord.generatedRewrittenBundlePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
        }
        let pageRelativePath =
            launchRecord.normalizedPath
            ?? launchRecord.declaredPath
            ?? "unknown"
        events.append(
            ChromeMV3PopupOptionsHostDiagnosticEvent(
                eventKind: "hostPreloadResource",
                apiName: "host.popupLoad",
                targetContext: "host",
                safeMessageShapeClassification: "hostPreload:mainFrame",
                resultClassifier:
                    launchRecord.generatedResourcePath == nil
                        ? "popup main resource unavailable"
                        : "popup main resource resolved",
                firstMissingAPIOrPermissionOrLifecycleError:
                    launchRecord.generatedResourcePath == nil
                        ? "popup main resource unavailable"
                        : nil,
                diagnostics: [
                    "mainResource=\(safeRelativePath(pageRelativePath))",
                    "declaredPath=\(safeRelativePath(launchRecord.declaredPath ?? "none"))",
                    "normalizedPath=\(safeRelativePath(launchRecord.normalizedPath ?? "none"))",
                    "loadScheme=file",
                    "readAccessRoot=generatedPackageRoot",
                    "fileBackedPage=true",
                ]
            )
        )

        guard let resolution = launchRecord.resourceResolution else {
            return events
        }

        let audited = resolution.linkedResources.filter {
            $0.tagName == "script" || $0.tagName == "link"
        }
        for resource in audited {
            let normalized = safeRelativePath(
                resource.normalizedPath ?? "none"
            )
            let insideRoot =
                resource.generatedResourcePath.flatMap { path in
                    rootURL.map { pathIsInsideGeneratedRoot(path, rootURL: $0) }
                } ?? false
            let classifier =
                resourceClassifier(resource: resource, insideRoot: insideRoot)
            let firstError =
                classifier == "resource exists"
                    ? nil
                    : classifier
            var diagnostics = [
                "tag=\(safeToken(resource.tagName, fallback: "unknown"))",
                "attribute=\(safeToken(resource.attributeName ?? "none", fallback: "none"))",
                "kind=\(resource.kind.rawValue)",
                "type=\(safeToken(resource.resourceType ?? "none", fallback: "none"))",
                "rawShape=\(safeURLShape(resource.rawValue))",
                "normalizedPath=\(normalized)",
                "exists=\(resource.exists)",
                "insideGeneratedRoot=\(insideRoot)",
                "blocked=\(resource.blocked)",
            ]
            diagnostics.append(
                "rootEscape=\(resource.generatedResourcePath != nil && insideRoot == false)"
            )
            events.append(
                ChromeMV3PopupOptionsHostDiagnosticEvent(
                    eventKind: "hostPreloadResource",
                    apiName: "host.resourcePreflight",
                    targetContext: "resource",
                    safeMessageShapeClassification:
                        "resourceTag=\(safeToken(resource.tagName, fallback: "unknown"))",
                    resultClassifier: classifier,
                    firstMissingAPIOrPermissionOrLifecycleError:
                        firstError,
                    diagnostics: diagnostics
                )
            )
        }
        return events
    }

    static func navigationEvent(
        kind: String,
        apiName: String,
        url: URL?,
        readAccessURL: URL,
        resultClassifier: String,
        firstError: String? = nil,
        extraDiagnostics: [String] = []
    ) -> ChromeMV3PopupOptionsHostDiagnosticEvent {
        ChromeMV3PopupOptionsHostDiagnosticEvent(
            eventKind: kind,
            apiName: apiName,
            targetContext: "navigation",
            safeMessageShapeClassification: "navigationURLShape",
            resultClassifier: resultClassifier,
            firstMissingAPIOrPermissionOrLifecycleError: firstError,
            diagnostics:
                [
                    "urlShape=\(safeURLShape(url?.absoluteString ?? ""))",
                    "relativePath=\(relativePath(url, rootURL: readAccessURL))",
                    "readAccessRoot=generatedPackageRoot",
                    "insideReadAccessRoot=\(urlInsideRoot(url, rootURL: readAccessURL))",
                ]
                + extraDiagnostics
        )
    }

    static func safeURLShape(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "none" }
        if ChromeMV3ExtensionPageResourcePath.isRemote(trimmed) {
            return "remote:\(safeRemoteHost(trimmed))"
        }
        if trimmed.hasPrefix("file://") {
            return "file:\(safeRelativePath(lastPathComponents(trimmed)))"
        }
        if trimmed.hasPrefix("chrome-extension://") {
            return "extension:\(safeRelativePath(lastPathComponents(trimmed)))"
        }
        if trimmed.hasPrefix("sumi-extension-page-diagnostic://") {
            let path = URLComponents(string: trimmed)?.path ?? ""
            let relativePath = String(path.drop(while: { $0 == "/" }))
            return "diagnostic-extension:\(safeRelativePath(relativePath))"
        }
        return safeRelativePath(trimmed)
    }

    static func safeRelativePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "none" }
        let withoutQuery = trimmed
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init) ?? trimmed
        let pathOnly = withoutQuery
            .split(separator: "?", maxSplits: 1)
            .first
            .map(String.init) ?? withoutQuery
        let pieces = pathOnly
            .split(separator: "/")
            .filter { $0.isEmpty == false }
            .suffix(4)
            .map(String.init)
        let joined = pieces.isEmpty ? pathOnly : pieces.joined(separator: "/")
        guard joined.count <= 160,
              containsSensitiveFragment(joined) == false,
              joined.range(
                  of: #"^[A-Za-z0-9._@+\-/=:%]+$"#,
                  options: .regularExpression
              ) != nil
        else { return "redacted" }
        return joined
    }

    private static func resourceClassifier(
        resource: ChromeMV3ExtensionPageLinkedResource,
        insideRoot: Bool
    ) -> String {
        if resource.generatedResourcePath != nil && insideRoot == false {
            return "resource path escaped package root"
        }
        switch resource.kind {
        case .missingLocalResource:
            return "missing local resource"
        case .unsafeLocalPath:
            return "unsafe local resource path"
        case .remoteResource:
            return "remote resource blocked"
        case .inlineScript:
            return "inline script blocked by extension-page CSP"
        default:
            return resource.exists ? "resource exists" : "resource unavailable"
        }
    }

    private static func safeToken(
        _ value: String,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.count <= 80,
              containsSensitiveFragment(trimmed) == false,
              trimmed.range(
                  of: #"^[A-Za-z0-9._+/\-;= ]+$"#,
                  options: .regularExpression
              ) != nil
        else { return fallback }
        return trimmed
    }

    private static func relativePath(_ url: URL?, rootURL: URL) -> String {
        guard let url, url.isFileURL else { return "none" }
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(rootPrefix) else { return "outsideReadAccessRoot" }
        return safeRelativePath(String(path.dropFirst(rootPrefix.count)))
    }

    static func urlInsideRoot(_ url: URL?, rootURL: URL) -> Bool {
        guard let url, url.isFileURL else { return false }
        return pathIsInsideGeneratedRoot(url.path, rootURL: rootURL)
    }

    static func safeDiagnosticToken(_ value: String) -> String {
        safeToken(value, fallback: "redacted")
    }

    private static func pathIsInsideGeneratedRoot(
        _ path: String,
        rootURL: URL
    ) -> Bool {
        let root = rootURL.standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        return standardized == root || standardized.hasPrefix(rootPrefix)
    }

    private static func lastPathComponents(_ value: String) -> String {
        let withoutQuery = value
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init) ?? value
        let pathOnly = withoutQuery
            .split(separator: "?", maxSplits: 1)
            .first
            .map(String.init) ?? withoutQuery
        return pathOnly
            .split(separator: "/")
            .suffix(4)
            .joined(separator: "/")
    }

    private static func safeRemoteHost(_ value: String) -> String {
        guard let url = URL(string: value),
              let host = url.host,
              containsSensitiveFragment(host) == false
        else { return "remote" }
        return safeToken(host, fallback: "remote")
    }

    private static func containsSensitiveFragment(_ value: String) -> Bool {
        let lower = value.lowercased()
        return [
            "auth",
            "cookie",
            "credential",
            "password",
            "secret",
            "sessionid",
            "token",
            "vault",
        ].contains { lower.contains($0) }
    }
}
#endif

struct ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var handledRequestCount: Int
    var succeededRequestCount: Int
    var blockedRequestCount: Int
    var observedMethods: [String]
    var callRecords: [ChromeMV3PopupOptionsJSBridgeCallRecord]
    var sanitizedBridgeRouteRecords:
        [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord]
    var jsDebugRouteEvents:
        [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    var pendingUnresolvedJSDebugRoutes:
        [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    var blockedAPIs: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
    var lastAPIErrorSummary: String?
    var storageOnChangedPayloadCount: Int
    var portCount: Int
    var permissionPromptGate:
        ChromeMV3PermissionPromptGateRecord
    var permissionPromptRequests: [ChromeMV3PermissionPromptRequest]
    var permissionPromptResults:
        [ChromeMV3PermissionPromptResultRecord]
    var permissionPromptLifecycleRecords:
        [ChromeMV3PermissionPromptLifecycleRecord]
    var permissionEventDispatches:
        [ChromeMV3PermissionEventDispatchRecord]
    var contentScriptEndpointSummary:
        ChromeMV3ContentScriptEndpointRegistrySummary?
    var listenerRegistryClearedOnTeardown: Bool
    var storageListenersClearedOnTeardown: Bool
    var portStateClearedOnTeardown: Bool
    var diagnostics: [String]
}

struct ChromeMV3PopupOptionsJSBridgeHostResponse:
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
    var permissionEventPayload: ChromeMV3PermissionsAPIEventPayload?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var blockedAPIDiagnostic: ChromeMV3PopupOptionsBlockedAPIDiagnostic?
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var serviceWorkerWakeAttempted: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var nativeHostLaunchAttempted: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.popupOptionsBridgeFoundationObject
                ?? NSNull(),
            "onChangedPayload": onChangedPayloadFoundationObject,
            "permissionEventPayload": permissionEventPayloadFoundationObject,
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "blockedAPIDiagnostic": blockedDiagnosticFoundationObject,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "contentScriptAttachmentAvailableInProduct":
                contentScriptAttachmentAvailableInProduct,
            "serviceWorkerWakeAttempted": serviceWorkerWakeAttempted,
            "serviceWorkerLifecycleWakeResult":
                serviceWorkerLifecycleWakeResultFoundationObject,
            "nativeHostLaunchAttempted": nativeHostLaunchAttempted,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }

    private var onChangedPayloadFoundationObject: Any {
        guard let payload = onChangedPayload else { return NSNull() }
        return payload.popupOptionsBridgeFoundationObject
    }

    private var permissionEventPayloadFoundationObject: Any {
        guard let payload = permissionEventPayload else { return NSNull() }
        return payload.popupOptionsBridgeFoundationObject
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

    private var blockedDiagnosticFoundationObject: Any {
        guard let diagnostic = blockedAPIDiagnostic else { return NSNull() }
        return [
            "namespace": diagnostic.namespace,
            "methodName": diagnostic.methodName,
            "reason": diagnostic.reason,
            "remediation": diagnostic.remediation,
            "roadmapOwner": diagnostic.roadmapOwner,
            "lastErrorCode": diagnostic.lastErrorCode,
            "lastErrorMessage": diagnostic.lastErrorMessage,
        ]
    }
}

private struct ChromeMV3PopupOptionsBridgeInputError: Error, Equatable {
    var message: String
}

final class ChromeMV3PopupOptionsJSBridgeHandler {
    let configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    private var localStorageBroker: ChromeMV3StorageBroker
    private var sessionStorageBroker: ChromeMV3StorageBroker
    private var syncStorageBroker: ChromeMV3StorageBroker?
    private let storageOperationHandler: ChromeMV3StorageAPIOperationHandler
    private var permissionRuntimeOwner: ChromeMV3PermissionRuntimeStateOwner
    private let tabRegistry: ChromeMV3SyntheticTabRegistry
    private let contentScriptEndpointRegistry:
        ChromeMV3ContentScriptEndpointRegistry?
    private let permissionPromptPresenter:
        ChromeMV3PermissionPromptPresenting?
    private let permissionPromptGate:
        ChromeMV3PermissionPromptGateRecord
    private let permissionStateStore:
        ChromeMV3DeveloperPreviewPermissionStateStore?
    private let permissionEventDispatcher:
        ChromeMV3PermissionEventDispatching?
    private var permissionPromptRequests:
        [ChromeMV3PermissionPromptRequest] = []
    private var permissionPromptResults:
        [ChromeMV3PermissionPromptResultRecord] = []
    private var permissionPromptLifecycleRecords:
        [ChromeMV3PermissionPromptLifecycleRecord] = []
    private var permissionEventDispatches:
        [ChromeMV3PermissionEventDispatchRecord] = []
    private var permissionPersistenceDiagnostics: [String] = []
    private var storagePersistenceDiagnostics: [String] = []
    private var callRecords: [ChromeMV3PopupOptionsJSBridgeCallRecord] = []
    private var sanitizedBridgeRouteRecords:
        [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] = []
    private var jsDebugRouteEvents:
        [ChromeMV3PopupOptionsJSDebugRouteEventRecord] = []
    private var nextJSDebugRouteEventSequence = 0
    private var onChangedPayloads: [ChromeMV3StorageOnChangedEventPayload] = []
    private var syntheticPortIDs: Set<String> = []
    private var serviceWorkerLifecyclePortIDs: Set<String> = []
    private let sharedLifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private let lifecycleComponentID: String
    private let nativeMessagingLifecycleComponentID: String
    private var nativeMessagingRuntimeOwner:
        ChromeMV3NativeMessagingRuntimeOwner?
    private var tornDown = false

    init(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry? = nil,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting? = nil,
        permissionStateStore:
            ChromeMV3DeveloperPreviewPermissionStateStore? = nil,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching? = nil,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) {
        self.configuration = configuration
        self.contentScriptEndpointRegistry = contentScriptEndpointRegistry
        self.permissionPromptPresenter = permissionPromptPresenter
        self.sharedLifecycleSession = sharedLifecycleSession
        self.lifecycleComponentID =
            stableIDPopupOptionsBridge(
                prefix: "popup-options-extension-page-host",
                parts: [
                    configuration.profileID,
                    configuration.extensionID,
                    configuration.surfaceID,
                ]
            )
        self.nativeMessagingLifecycleComponentID =
            stableIDPopupOptionsBridge(
                prefix: "popup-options-native-fixture",
                parts: [
                    configuration.profileID,
                    configuration.extensionID,
                    configuration.surfaceID,
                ]
            )
        if let permissionStateStore {
            self.permissionStateStore = permissionStateStore
        } else if let rootPath = configuration.permissionStateRootPath,
                  rootPath.isEmpty == false
        {
            self.permissionStateStore =
                ChromeMV3DeveloperPreviewPermissionStateStore(
                    rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
                )
        } else {
            self.permissionStateStore = nil
        }
        self.permissionEventDispatcher = permissionEventDispatcher
        self.permissionPromptGate =
            ChromeMV3PermissionPromptGateRecord.evaluate(
                moduleEnabled: configuration.moduleState == .enabled,
                extensionEnabled: configuration.bridgeAvailable,
                developerPreviewGate:
                    configuration
                    .popupOptionsJSBridgeAvailableInDeveloperPreview,
                publicProductGate:
                    configuration
                    .popupOptionsJSBridgeAvailableInPublicProduct
            )
        let namespace = ChromeMV3StorageNamespace(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            area: .local
        )
        let sessionNamespace = ChromeMV3StorageNamespace(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            area: .session
        )
        var storageBroker = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode:
                Self.storagePersistenceMode(configuration: configuration)
        )
        var storageDiagnostics =
            Self.storagePersistenceDiagnostics(configuration: configuration)
        do {
            if try storageBroker.loadHostSnapshotIfPresent() {
                storageDiagnostics.append(
                    "Loaded existing developer-preview storage.local snapshot for this profile/extension namespace."
                )
            }
        } catch {
            storageDiagnostics.append(
                "Developer-preview storage.local snapshot load failed; using empty in-memory state for this popup session."
            )
        }
        self.localStorageBroker = storageBroker
        self.sessionStorageBroker = ChromeMV3StorageBroker(
            namespace: sessionNamespace,
            persistenceMode: .inMemory
        )
        self.storagePersistenceDiagnostics =
            uniqueSortedPopupOptionsBridge(storageDiagnostics)
        self.storageOperationHandler =
            ChromeMV3StorageAPIOperationHandler(
                state:
                    configuration.bridgeAvailable
                        ? .developerPreviewPopupOptionsBridge(
                            syncLocalCompatibilityBrokerAllowed:
                                configuration.allowlist.allowedMethods
                                .contains("storage.sync.get")
                        )
                        : .disabledModule
            )
        if let persisted = self.permissionStateStore?.loadRecord(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID
        ) {
            self.permissionRuntimeOwner =
                ChromeMV3PermissionRuntimeStateOwner(
                    snapshot: persisted.permissionRuntimeSnapshot
                )
            self.permissionPromptRequests = persisted.promptRequests
            self.permissionPromptResults = persisted.promptResults
            self.permissionPromptLifecycleRecords =
                persisted.promptLifecycleRecords
            self.permissionPersistenceDiagnostics = [
                "Loaded persisted developer-preview permission state for popup/options bridge.",
            ]
        } else {
            self.permissionRuntimeOwner =
                ChromeMV3PermissionRuntimeStateOwner(
                    permissionStore:
                        ChromeMV3PermissionDecisionStore(
                            snapshot:
                                ChromeMV3PermissionDecisionStoreSnapshot(
                                    extensionID: configuration.extensionID,
                                    profileID: configuration.profileID,
                                    declaredAPIPermissions:
                                        configuration.manifestPermissions,
                                    declaredHostPermissions:
                                        configuration.manifestHostPermissions,
                                    optionalAPIPermissions:
                                        configuration
                                        .manifestOptionalPermissions,
                                    optionalHostPermissions:
                                        configuration
                                        .manifestOptionalHostPermissions
                                )
                        ),
                    activeTabStore:
                        ChromeMV3ActiveTabGrantStore.from(
                            extensionID: configuration.extensionID,
                            profileID: configuration.profileID,
                            grants: configuration.activeTabGrants
                        )
                )
        }
        self.tabRegistry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: false
            )
        permissionEventDispatcher?.registerChromeMV3PermissionEventPage(
            surfaceID: configuration.surfaceID,
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            surface: configuration.surface,
            dispatchHandler: nil
        )
        attachSharedLifecycleComponentsIfNeeded()
    }

    private static func storagePersistenceMode(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    ) -> ChromeMV3StorageBrokerPersistenceMode {
        guard configuration.bridgeAvailable,
              let rootPath = configuration.storageLocalRootPath,
              rootPath.isEmpty == false
        else { return .inMemory }
        return .hostBacked(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
    }

    private static func syncStoragePersistenceMode(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    ) -> ChromeMV3StorageBrokerPersistenceMode {
        guard configuration.bridgeAvailable,
              configuration.allowlist.allowedMethods
              .contains("storage.sync.get"),
              let rootPath = configuration.storageSyncRootPath,
              rootPath.isEmpty == false
        else { return .inMemory }
        return .hostBacked(rootURL: URL(fileURLWithPath: rootPath, isDirectory: true))
    }

    private static func storagePersistenceDiagnostics(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    ) -> [String] {
        guard configuration.bridgeAvailable else {
            return [
                "storage.local, storage.session, and storage.sync brokers remain disabled because the popup/options bridge gate is closed.",
            ]
        }
        let syncExposed =
            configuration.allowlist.allowedMethods.contains(
                "storage.sync.get"
            )
        let syncDiagnostics = syncExposed
            ? [
                "storage.sync uses syncBackend=localCompatibility only in the controlled popup/options bridge.",
                "storage.sync is lazy and no broker snapshot is loaded until a storage.sync method is called.",
                "storage.sync has no cloud sync, Sumi account sync, or cross-device propagation.",
                "storage.sync is scoped to this profile ID, extension ID, and sync area.",
                "Private/off-record tabs are rejected before controlled popup launch; no off-record sync compatibility storage root is written.",
            ]
            : [
                "storage.sync is not exposed by this popup/options bridge policy.",
            ]
        let sessionDiagnostics = [
            "storage.session uses memory-only state for this controlled popup/options bridge lifetime.",
            "storage.session is scoped to this profile ID, extension ID, and session area.",
            "storage.session has no host-backed snapshot URL and is never persisted to disk.",
            "Private/off-record tabs are rejected before controlled popup launch; no off-record session storage root is written.",
        ]
        guard let rootPath = configuration.storageLocalRootPath,
              rootPath.isEmpty == false
        else {
            return [
                "storage.local uses memory-only state because no profile storage root is available.",
                "Private/off-record controlled popup storage is not persisted to disk.",
                "storage.local remains scoped to this profile ID, extension ID, and local area.",
            ] + sessionDiagnostics + syncDiagnostics
        }
        return [
            "storage.local uses a developer-preview host-backed broker scoped by profile ID, extension ID, and local area.",
            "storage.local values are persisted only in the controlled popup developer-preview storage root.",
            "No raw storage keys or values are included in popup/storage diagnostics.",
            "Private/off-record tabs are rejected before controlled popup launch; no off-record storage root is written.",
        ] + sessionDiagnostics + syncDiagnostics
    }

    var diagnosticsSnapshot:
        ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    {
        let blocked = callRecords.filter { $0.succeeded == false }
        let lastAPIErrorSummary: String?
        if let lastBlocked = blocked.last,
           let message = lastBlocked.lastErrorMessage
        {
            lastAPIErrorSummary =
                "\(lastBlocked.namespace).\(lastBlocked.methodName): \(message)"
        } else {
            lastAPIErrorSummary = nil
        }
        return ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot(
            handledRequestCount: callRecords.count,
            succeededRequestCount:
                callRecords.filter(\.succeeded).count,
            blockedRequestCount: blocked.count,
            observedMethods:
                uniqueSortedPopupOptionsBridge(
                    callRecords.map { "\($0.namespace).\($0.methodName)" }
                ),
            callRecords: callRecords,
            sanitizedBridgeRouteRecords: sanitizedBridgeRouteRecords,
            jsDebugRouteEvents: jsDebugRouteEvents,
            pendingUnresolvedJSDebugRoutes:
                jsDebugRouteEvents.filter {
                    $0.eventKind == "pendingTimeout"
                        || $0.resultClassifier == "unknown pending promise"
                },
            blockedAPIs:
                uniqueBlockedDiagnostics(
                    blocked.map {
                        configuration.allowlist.blockedDiagnostic(
                            namespace: $0.namespace,
                            methodName: $0.methodName
                        )
                    }
                ),
            lastAPIErrorSummary: lastAPIErrorSummary,
            storageOnChangedPayloadCount: onChangedPayloads.count,
            portCount: syntheticPortIDs.count,
            permissionPromptGate: permissionPromptGate,
            permissionPromptRequests: permissionPromptRequests,
            permissionPromptResults: permissionPromptResults,
            permissionPromptLifecycleRecords:
                permissionPromptLifecycleRecords,
            permissionEventDispatches:
                uniquePermissionEventDispatches(
                    permissionEventDispatches
                        + (permissionEventDispatcher?
                            .permissionEventDispatchRecords ?? [])
                ),
            contentScriptEndpointSummary:
                contentScriptEndpointRegistry?.summary,
            listenerRegistryClearedOnTeardown: tornDown,
            storageListenersClearedOnTeardown: tornDown,
            portStateClearedOnTeardown: tornDown,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    configuration.diagnostics
                        + permissionPersistenceDiagnostics
                        + storagePersistenceDiagnostics
                        + [
                            "Popup/options bridge diagnostics are scoped to one WebKit host.",
                            "No normal-tab bridge installation is represented by this snapshot.",
                        ]
                )
        )
    }

    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    {
        permissionRuntimeOwner.snapshot
    }

    var permissionBroker: ChromeMV3PermissionBroker {
        permissionRuntimeOwner.permissionBroker
    }

    @discardableResult
    func grantActiveTabFromExplicitUserAction(
        tabID: Int = 1,
        sourceSurface: ChromeMV3PermissionPromptSourceSurface = .actionClick,
        sequence: Int = 0
    ) -> ChromeMV3ActiveTabRuntimeGrantResult {
        let tab = tabRegistry.tab(id: tabID)
        let result = ChromeMV3DeveloperPreviewActiveTabUX.grant(
            request:
                ChromeMV3ActiveTabUXRequest(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    tabID: tabID,
                    url: tab?.url ?? "",
                    sourceSurface: sourceSurface,
                    explicitUserGesture: true,
                    sequence: sequence
                ),
            gateRecord: permissionPromptGate,
            owner: &permissionRuntimeOwner
        )
        persistPermissionState(
            diagnostics: [
                result.granted
                    ? "activeTab grant persisted after explicit user action."
                    : "Blocked activeTab grant result persisted for diagnostics.",
            ]
        )
        return result
    }

    @discardableResult
    func applyPermissionLifecycleEvent(
        _ event: ChromeMV3PermissionLifecycleEvent
    ) -> ChromeMV3PermissionRuntimeLifecycleApplication {
        let application = permissionRuntimeOwner.applyLifecycleEvent(event)
        invalidateContentScriptEndpoints(
            reason:
                "Permission lifecycle event invalidated stale content-script endpoints."
        )
        persistPermissionState(diagnostics: application.diagnostics)
        return application
    }

    func handle(_ body: Any) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        #if DEBUG
        if let debugResponse = handleJSDebugEvent(body) {
            return debugResponse
        }
        #endif
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            return response(
                request: nil,
                namespace: "unsupported",
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                diagnostics: [error.message]
            )
        }
    }

    @MainActor
    func handleAsync(
        _ body: Any
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        #if DEBUG
        if let debugResponse = handleJSDebugEvent(body) {
            return debugResponse
        }
        #endif
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return await handleAsync(request)
        case .failure(let error):
            return response(
                request: nil,
                namespace: "unsupported",
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                diagnostics: [error.message]
            )
        }
    }

    #if DEBUG
    private func handleJSDebugEvent(
        _ body: Any
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse? {
        guard let raw = body as? [String: Any],
              raw["namespace"] as? String == "__sumiDebug",
              raw["methodName"] as? String == "event"
        else { return nil }

        recordJSDebugRouteEvent(raw)
        let bridgeCallID =
            sanitizedJSDebugString(raw["bridgeCallID"], maxLength: 180)
            ?? stableIDPopupOptionsBridge(
                prefix: "popup-options-js-debug-event",
                parts: [
                    configuration.surfaceID,
                    String(nextJSDebugRouteEventSequence),
                ]
            )
        return ChromeMV3PopupOptionsJSBridgeHostResponse(
            bridgeCallID: bridgeCallID,
            namespace: "__sumiDebug",
            methodName: "event",
            succeeded: true,
            resultPayload: .null,
            onChangedPayload: nil,
            permissionEventPayload: nil,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            callbackWouldSetLastError: false,
            promiseWouldReject: false,
            blockedAPIDiagnostic: nil,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            serviceWorkerWakeAttempted: false,
            serviceWorkerLifecycleWakeResult: nil,
            nativeHostLaunchAttempted: false,
            runtimeLoadable: false,
            diagnostics: [
                "DEBUG-only controlled popup route diagnostic accepted.",
                "No raw message body, storage value, credential, vault, token, cookie, or form value was accepted.",
            ]
        )
    }

    func recordHostDiagnosticEvent(
        _ event: ChromeMV3PopupOptionsHostDiagnosticEvent
    ) {
        recordJSDebugRouteEvent([
            "namespace": "__sumiDebug",
            "methodName": "event",
            "eventKind": event.eventKind,
            "apiName": event.apiName,
            "sourceContext": configuration.sourceContext.rawValue,
            "targetContext": event.targetContext,
            "safeMessageShapeClassification":
                event.safeMessageShapeClassification,
            "safeCommandTypeActionFieldNames": [],
            "resultClassifier": event.resultClassifier as Any,
            "firstMissingAPIOrPermissionOrLifecycleError":
                event.firstMissingAPIOrPermissionOrLifecycleError as Any,
            "diagnostics": event.diagnostics,
        ])
    }

    func recordHostDiagnosticEvents(
        _ events: [ChromeMV3PopupOptionsHostDiagnosticEvent]
    ) {
        events.forEach(recordHostDiagnosticEvent)
    }

    private func recordJSDebugRouteEvent(_ raw: [String: Any]) {
        nextJSDebugRouteEventSequence += 1
        let eventKind =
            sanitizedJSDebugString(
                raw["eventKind"],
                allowedValues: Self.allowedJSDebugEventKinds
            ) ?? "unknown"
        let apiName =
            sanitizedJSDebugString(raw["apiName"], maxLength: 96)
            ?? "unknown"
        let record = ChromeMV3PopupOptionsJSDebugRouteEventRecord(
            sequence: nextJSDebugRouteEventSequence,
            eventKind: eventKind,
            apiName: apiName,
            bridgeCallID:
                sanitizedJSDebugString(
                    raw["bridgeCallID"],
                    maxLength: 180
                ),
            invocationMode:
                sanitizedJSDebugString(
                    raw["invocationMode"],
                    allowedValues: Self.allowedJSDebugInvocationModes
                ),
            sourceContext:
                sanitizedJSDebugString(
                    raw["sourceContext"],
                    allowedValues:
                        Set(ChromeMV3JSBridgeSourceContext.allCases.map(\.rawValue))
                ) ?? configuration.sourceContext.rawValue,
            targetContext:
                sanitizedJSDebugString(
                    raw["targetContext"],
                    allowedValues: Self.allowedJSDebugTargetContexts
                ),
            safeMessageShapeClassification:
                sanitizedJSDebugString(
                    raw["safeMessageShapeClassification"],
                    maxLength: 240
                ) ?? "shape=unknown",
            safeCommandTypeActionFieldNames:
                sanitizedJSDebugFieldNames(
                    raw["safeCommandTypeActionFieldNames"]
                ),
            portName: sanitizedJSDebugPortName(raw["portName"]),
            ageMilliseconds:
                sanitizedJSDebugAgeMilliseconds(raw["ageMilliseconds"]),
            resultClassifier:
                sanitizedJSDebugString(
                    raw["resultClassifier"],
                    maxLength: 96
                ),
            firstMissingAPIOrPermissionOrLifecycleError:
                sanitizedJSDebugString(
                    raw["firstMissingAPIOrPermissionOrLifecycleError"],
                    maxLength: 180
                ),
            diagnostics:
                sanitizedJSDebugDiagnostics(raw["diagnostics"])
        )
        jsDebugRouteEvents.append(record)
        if jsDebugRouteEvents.count > 800 {
            jsDebugRouteEvents.removeFirst(
                jsDebugRouteEvents.count - 800
            )
        }
    }

    private func sanitizedJSDebugString(
        _ value: Any?,
        allowedValues: Set<String>? = nil,
        maxLength: Int = 120
    ) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.count <= maxLength,
              Self.containsSensitiveJSDebugFragment(trimmed) == false
        else { return nil }
        if let allowedValues {
            return allowedValues.contains(trimmed) ? trimmed : nil
        }
        guard trimmed.unicodeScalars.allSatisfy({
            CharacterSet.controlCharacters.contains($0) == false
        }) else { return nil }
        return trimmed
    }

    private func sanitizedJSDebugAgeMilliseconds(_ value: Any?) -> Int? {
        let intValue: Int?
        if let number = value as? NSNumber {
            intValue = number.intValue
        } else {
            intValue = value as? Int
        }
        guard let intValue, intValue >= 0, intValue <= 600_000 else {
            return nil
        }
        return intValue
    }

    private func sanitizedJSDebugFieldNames(_ value: Any?) -> [String] {
        guard let fields = value as? [String] else { return [] }
        return uniqueSortedPopupOptionsBridge(
            fields.filter {
                Self.safeJSDebugFieldNames.contains($0)
                    && Self.containsSensitiveJSDebugFragment($0) == false
            }
        )
    }

    private func sanitizedJSDebugPortName(_ value: Any?) -> String? {
        guard let portName = sanitizedJSDebugString(value, maxLength: 80),
              portName.range(
                of: #"^[A-Za-z][A-Za-z0-9_.:-]{0,79}$"#,
                options: .regularExpression
              ) != nil
        else { return nil }
        return portName
    }

    private func sanitizedJSDebugDiagnostics(_ value: Any?) -> [String] {
        guard let diagnostics = value as? [String] else { return [] }
        return uniqueSortedPopupOptionsBridge(
            diagnostics.compactMap {
                sanitizedJSDebugString($0, maxLength: 220)
            }
        )
    }

    private nonisolated static func containsSensitiveJSDebugFragment(
        _ value: String
    ) -> Bool {
        let lower = value.lowercased()
        return sensitiveJSDebugFragments.contains {
            lower.contains($0)
        }
    }

    private nonisolated static let allowedJSDebugEventKinds: Set<String> = [
        "bridgeCallStarted",
        "bridgeCallResolved",
        "bridgeCallRejected",
        "callbackLastError",
        "extensionMethodCalled",
        "extensionNamespaceAccessed",
        "missingAPIAccess",
        "pendingTimeout",
        "portDisconnected",
        "portListenerAdded",
        "portListenerRemoved",
        "portMessageBridgeFailed",
        "portMessageCalled",
        "portMessageDelivered",
        "portMessageQueued",
        "portOnDisconnectDispatched",
        "portOnMessageDispatched",
        "postBootstrapCheckpoint",
        "promiseRejected",
        "consoleError",
        "consoleWarn",
        "cspViolation",
        "environmentProbe",
        "hostNavigationAction",
        "hostNavigationFailure",
        "hostNavigationFinish",
        "hostNavigationResponse",
        "hostPreloadResource",
        "resourceLoaded",
        "resourceLoadError",
        "resourceTimingSnapshot",
        "scriptError",
        "unhandledRejection",
        "webContentProcessTerminated",
    ]

    private nonisolated static let allowedJSDebugInvocationModes:
        Set<String> = [
            "callback",
            "fireAndForget",
            "promise",
        ]

    private nonisolated static let allowedJSDebugTargetContexts: Set<String> = [
        "backgroundPage",
        "contentScript",
        "console",
        "csp",
        "dom",
        "extensionPage",
        "host",
        "i18n",
        "manifest",
        "nativeApplication",
        "nativeApplicationPort",
        "navigation",
        "platform",
        "resource",
        "serviceWorker",
        "storage.local",
        "storage.managed",
        "storage.session",
        "storage.sync",
        "tabs",
        "unknown",
    ]

    private nonisolated static let safeJSDebugFieldNames: Set<String> = [
        "action",
        "command",
        "kind",
        "messageType",
        "method",
        "name",
        "operation",
        "requestType",
        "type",
    ]

    private nonisolated static let sensitiveJSDebugFragments: Set<String> = [
        "auth",
        "cookie",
        "credential",
        "password",
        "secret",
        "sessionid",
        "token",
        "vault",
    ]
    #endif

    @MainActor
    func handleAsync(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.bridgeAvailable
        else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                diagnostics: [
                    "Popup/options JS bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }
        guard methodAllowedByPolicy(request) else {
            return blockedByAllowlist(request)
        }
        switch (request.namespace, request.methodName) {
        case ("tabs", "sendMessage"):
            return await tabsSendMessageAsync(request)
        default:
            return handle(request)
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.bridgeAvailable
        else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                diagnostics: [
                    "Popup/options JS bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }
        guard methodAllowedByPolicy(request) else {
            return blockedByAllowlist(request)
        }

        switch (request.namespace, request.methodName) {
        case ("runtime", "sendMessage"):
            return runtimeSendMessage(request)
        case ("runtime", "connect"):
            return runtimeConnect(request)
        case ("runtime", "getManifest"):
            return runtimeGetManifest(request)
        case ("runtime", "getURL"):
            return runtimeGetURL(request)
        case ("runtime", "port.postMessage"):
            return runtimePortPostMessage(request)
        case ("runtime", "port.disconnect"):
            return runtimePortDisconnect(request)
        case ("runtime", "sendNativeMessage"):
            return runtimeSendNativeMessage(request)
        case ("runtime", let method) where method == "connect" + "Native":
            return runtimeConnectNative(request)
        case ("runtime", "nativePort.postMessage"):
            return runtimeNativePortPostMessage(request)
        case ("runtime", "nativePort.disconnect"):
            return runtimeNativePortDisconnect(request)
        case ("storage", "local.get"),
             ("storage", "local.set"),
             ("storage", "local.remove"),
             ("storage", "local.clear"),
             ("storage", "local.getBytesInUse"),
             ("storage", "session.get"),
             ("storage", "session.set"),
             ("storage", "session.remove"),
             ("storage", "session.clear"),
             ("storage", "session.getBytesInUse"),
             ("storage", "sync.get"),
             ("storage", "sync.set"),
             ("storage", "sync.remove"),
             ("storage", "sync.clear"),
             ("storage", "sync.getBytesInUse"):
            return storageArea(request)
        case ("permissions", "contains"):
            return permissionsContains(request)
        case ("permissions", "getAll"):
            return permissionsGetAll(request)
        case ("permissions", "request"):
            return permissionsRequest(request)
        case ("permissions", "remove"):
            return permissionsRemove(request)
        case ("permissions", "__sumiPermissionEventListenerCount"):
            return permissionsEventListenerCountChanged(request)
        case ("tabs", "query"):
            return tabsQuery(request)
        case ("tabs", "getCurrent"):
            return tabsGetCurrent(request)
        case ("tabs", "sendMessage"):
            return tabsSendMessage(request)
        case ("tabs", "connect"):
            return tabsConnect(request)
        case ("tabs", "port.postMessage"):
            return tabsPortPostMessage(request)
        case ("tabs", "port.disconnect"):
            return tabsPortDisconnect(request)
        case ("scripting", "executeScript"):
            return blocked(request, namespace: "scripting")
        case ("nativeMessaging", _),
             ("declarativeNetRequest", _),
             ("webRequest", _),
             ("sidePanel", _),
             ("offscreen", _),
             ("identity", _):
            return blocked(request, namespace: request.namespace)
        default:
            let namespaceKnown = [
                "runtime",
                "storage",
                "permissions",
                "tabs",
                "scripting",
            ].contains(request.namespace)
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    (namespaceKnown
                        ? ChromeMV3JSBridgeErrorCode.methodUnsupported
                        : ChromeMV3JSBridgeErrorCode.namespaceUnsupported)
                    .lastErrorMessage,
                lastErrorCode:
                    (namespaceKnown
                        ? ChromeMV3JSBridgeErrorCode.methodUnsupported
                        : ChromeMV3JSBridgeErrorCode.namespaceUnsupported)
                    .rawValue,
                blockedAPIDiagnostic:
                    configuration.allowlist.blockedDiagnostic(
                        namespace: namespaceKnown
                            ? request.namespace
                            : "unsupported",
                        methodName: namespaceKnown
                            ? request.methodName
                            : "*"
                    ),
                diagnostics: [
                    "Unsupported popup/options bridge route: \(request.namespace).\(request.methodName).",
                ]
            )
        }
    }

    private func methodAllowedByPolicy(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Bool {
        let identifier = "\(request.namespace).\(request.methodName)"
        return configuration.allowlist.allowedMethods.contains(identifier)
    }

    private func blockedByAllowlist(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let diagnostic = configuration.allowlist.blockedDiagnostic(
            namespace: request.namespace,
            methodName: request.methodName
        )
        return response(
            request: request,
            succeeded: false,
            lastErrorMessage: diagnostic.lastErrorMessage,
            lastErrorCode: diagnostic.lastErrorCode,
            blockedAPIDiagnostic: diagnostic,
            diagnostics: [
                diagnostic.reason,
                diagnostic.remediation,
                "Popup/options bridge host policy blocked \(request.namespace).\(request.methodName).",
                "Roadmap owner: \(diagnostic.roadmapOwner).",
            ]
        )
    }

    func handleServiceWorkerTabsRequest(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.bridgeAvailable
        else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Service-worker tabs bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }
        switch (request.namespace, request.methodName) {
        case ("tabs", "query"):
            return tabsQuery(request, sourceContextOverride: .serviceWorker)
        case ("tabs", "sendMessage"):
            return tabsSendMessage(
                request,
                sourceContextOverride: .serviceWorker
            )
        default:
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported.rawValue,
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Only tabs.query and tabs.sendMessage are exposed to the modeled service-worker tab/content-script bridge in this increment.",
                ]
            )
        }
    }

    @MainActor
    func handleServiceWorkerTabsRequestAsync(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.bridgeAvailable
        else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Service-worker tabs bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }
        switch (request.namespace, request.methodName) {
        case ("tabs", "query"):
            return tabsQuery(request, sourceContextOverride: .serviceWorker)
        case ("tabs", "sendMessage"):
            return await tabsSendMessageAsync(
                request,
                sourceContextOverride: .serviceWorker
            )
        default:
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported.rawValue,
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Only tabs.query and tabs.sendMessage are exposed to the modeled service-worker tab/content-script bridge in this increment.",
                ]
            )
        }
    }

    func tearDown() {
        localStorageBroker = ChromeMV3StorageBroker(
            namespace: localStorageBroker.namespace
        )
        sessionStorageBroker = ChromeMV3StorageBroker(
            namespace: sessionStorageBroker.namespace,
            persistenceMode: .inMemory
        )
        syncStorageBroker = nil
        callRecords.removeAll()
        jsDebugRouteEvents.removeAll()
        nextJSDebugRouteEventSequence = 0
        onChangedPayloads.removeAll()
        for portID in serviceWorkerLifecyclePortIDs {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        serviceWorkerLifecyclePortIDs.removeAll()
        syntheticPortIDs.removeAll()
        nativeMessagingRuntimeOwner?.tearDownForProfileClose()
        nativeMessagingRuntimeOwner = nil
        permissionPromptRequests.removeAll()
        permissionPromptResults.removeAll()
        permissionPromptLifecycleRecords.removeAll()
        permissionEventDispatches.removeAll()
        permissionPersistenceDiagnostics.removeAll()
        permissionEventDispatcher?
            .unregisterChromeMV3PermissionEventPage(
                surfaceID: configuration.surfaceID
            )
        sharedLifecycleSession?.detachComponent(
            componentID: lifecycleComponentID,
            reason: .reset
        )
        sharedLifecycleSession?.detachComponent(
            componentID: nativeMessagingLifecycleComponentID,
            reason: .reset
        )
        tabRegistry.tearDown()
        tornDown = true
    }

    private func attachSharedLifecycleComponentsIfNeeded() {
        guard let sharedLifecycleSession else { return }
        sharedLifecycleSession.attachComponent(
            kind: .extensionPageHostHarness,
            componentID: lifecycleComponentID,
            eventSurfaces: [
                .runtimeOnMessage,
                .runtimeOnConnect,
                .storageOnChanged,
                .permissionsOnAdded,
                .permissionsOnRemoved,
            ],
            keepaliveSources: [.runtimePort],
            diagnostics: [
                "Popup/options host attached to the local experimental shared lifecycle session.",
                "The default runtime remains off unless a caller passes this session explicitly.",
            ]
        )
        sharedLifecycleSession.attachComponent(
            kind: .nativeMessagingFixtureRuntime,
            componentID: nativeMessagingLifecycleComponentID,
            eventSurfaces: [
                .nativePortOnMessage,
                .nativePortOnDisconnect,
            ],
            keepaliveSources: [.nativeMessagingPort],
            diagnostics: [
                "Trusted native-messaging fixture attached to the local experimental shared lifecycle session.",
                "Arbitrary native host discovery remains unavailable.",
            ]
        )
    }

    private func routeServiceWorkerLifecycleEvent(
        source: ChromeMV3ServiceWorkerEventSource,
        payload: ChromeMV3StorageValue?,
        payloadSummary: String,
        componentID: String? = nil,
        componentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentKind =
                .extensionPageHostHarness,
        sourceContext: ChromeMV3RuntimeMessagingContextKind? = nil,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerInternalWakeResult? {
        sharedLifecycleSession?.routeEvent(
            reason: source.wakeReason,
            listenerEvent: source.listenerEvent,
            sourceComponentID: componentID ?? lifecycleComponentID,
            sourceComponentKind: componentKind,
            payload: payload,
            payloadSummary: payloadSummary,
            sourceContext:
                sourceContext ?? configuration.sourceContext.runtimeContext,
            keepaliveKind: keepaliveKind,
            portID: portID
        )
    }

    private func popupServiceWorkerSenderMetadata()
        -> ChromeMV3ServiceWorkerEventSenderMetadata
    {
        ChromeMV3ServiceWorkerEventSenderMetadata(
            tabID: nil,
            frameID: nil,
            documentID: nil,
            sourceURL: configuration.extensionBaseURLString,
            urlRedacted: false,
            redactionState: "extension-owned popup/options sender URL"
        )
    }

    private func dispatchServiceWorkerJSListener(
        source: ChromeMV3ServiceWorkerEventSource,
        arguments: [ChromeMV3StorageValue],
        payloadSummary: String,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerJSListenerDispatchResult? {
        sharedLifecycleSession?.dispatchRegisteredJSListener(
            source: source,
            arguments: arguments,
            sender: popupServiceWorkerSenderMetadata(),
            payloadSummary: payloadSummary,
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .extensionPageHostHarness,
            keepaliveKind: keepaliveKind,
            portID: portID
        )
    }

    private func runtimeLastErrorContract(
        for resultKind: ChromeMV3ServiceWorkerJSDispatchResultKind
    ) -> ChromeMV3RuntimeLastErrorContract {
        switch resultKind {
        case .noListener, .noReceiver:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .noReceivingEnd)
        case .blockedByPermission:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .permissionDenied)
        case .blockedByGate:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .serviceWorkerUnavailable)
        case .delivered, .listenerError, .promiseRejected,
             .sendResponseTimeoutDiagnostic, .unsupportedListenerMode:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .timeout)
        }
    }

    private func runtimeSendMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.isEmpty == false else {
            return invalidArguments(
                request,
                "runtime.sendMessage requires a message argument."
            )
        }
        guard request.arguments.count <= 2 else {
            return invalidArguments(
                request,
                "runtime.sendMessage external-extension overload is not available in popup/options developer preview."
            )
        }
        if let jsResult = dispatchServiceWorkerJSListener(
            source: .popupOptionsRuntimeMessage,
            arguments: [request.arguments[0]],
            payloadSummary: "popup/options runtime.sendMessage"
        ) {
            if jsResult.dispatched {
                return response(
                    request: request,
                    succeeded: true,
                    payload: jsResult.responsePayload ?? .null,
                    serviceWorkerLifecycleWakeResult:
                        jsResult.lifecycleWakeResult,
                    diagnostics:
                        jsResult.diagnostics
                        + [
                            "runtime.sendMessage dispatched to a captured service-worker runtime.onMessage JavaScript listener.",
                        ]
                )
            }
            let contract = runtimeLastErrorContract(for: jsResult.resultKind)
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    jsResult.lastErrorMessage
                    ?? contract.futureLastErrorMessage,
                lastErrorCode: contract.error.rawValue,
                serviceWorkerLifecycleWakeResult: jsResult.lifecycleWakeResult,
                diagnostics:
                    jsResult.diagnostics
                    + contract.diagnostics
                    + [
                        "runtime.sendMessage reached a captured service-worker JavaScript listener dispatcher but did not receive a response.",
                    ]
            )
        }
        if let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .popupOptionsRuntimeMessage,
            payload: request.arguments[0],
            payloadSummary: "popup/options runtime.sendMessage"
        ) {
            guard lifecycleResult.dispatched else {
                let contract = ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        lifecycleResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    lastErrorCode: contract.error.rawValue,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics:
                        lifecycleResult.diagnostics
                        + contract.diagnostics
                        + [
                            "runtime.sendMessage reached the local experimental service-worker lifecycle but no listener accepted it.",
                        ]
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: lifecycleResult.responsePayload ?? .null,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + [
                        "runtime.sendMessage routed through the local experimental shared lifecycle session.",
                    ]
            )
        }
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind:
                configuration.sourceContext == .actionPopup
                    ? .actionPopupToServiceWorker
                    : .optionsPageToServiceWorker,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID
        )
        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: ChromeMV3RuntimeMessageDispatcherInput.make(
                route: route,
                listenerRegistrySnapshot:
                    ChromeMV3RuntimeModelListenerRegistrySnapshot.make(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        endpoints: [],
                        diagnostics: [
                            "Popup/options bridge does not synthesize a service-worker receiver.",
                        ]
                    ),
                permissionBrokerSnapshot:
                    permissionRuntimeOwner.permissionBroker,
                serviceWorkerLifecycleSnapshot:
                    .blocked(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    ),
                moduleState: configuration.moduleState,
                dispatchMode: .modelOnly,
                responseMode:
                    request.invocationMode == .callback
                        ? .callback
                        : .promise,
                expectsResponse: true,
                userGestureAvailable:
                    configuration.sourceContext == .actionPopup,
                nativeHostName: nil,
                seed: request.bridgeCallID
            )
        )
        if let error = result.selectedLastError {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: error.futureLastErrorMessage,
                lastErrorCode: error.error.rawValue,
                diagnostics:
                    result.diagnostics
                        + [
                            "runtime.sendMessage did not wake a service worker; no receiver is currently modeled.",
                        ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.responsePayload ?? .null,
            diagnostics:
                result.diagnostics
                    + [
                        "runtime.sendMessage routed through existing dispatcher model without service-worker wake.",
                    ]
        )
    }

    private func runtimeConnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let connectName = request.arguments.first?.objectValue?["name"]?
            .stringValue ?? ""
        let portID = stableIDPopupOptionsBridge(
            prefix: "popup-options-runtime-port",
            parts: [
                configuration.surfaceID,
                request.bridgeCallID,
                String(syntheticPortIDs.count + 1),
            ]
        )
        let connectPayload = ChromeMV3StorageValue.object([
            "portID": .string(portID),
            "name": .string(connectName),
        ])
        if let jsResult = dispatchServiceWorkerJSListener(
            source: .popupOptionsRuntimeConnect,
            arguments: [connectPayload],
            payloadSummary: "popup/options runtime.connect",
            keepaliveKind: .runtimePort,
            portID: portID
        ) {
            guard jsResult.dispatched else {
                let contract = runtimeLastErrorContract(
                    for: jsResult.resultKind
                )
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        jsResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    lastErrorCode: contract.error.rawValue,
                    serviceWorkerLifecycleWakeResult:
                        jsResult.lifecycleWakeResult,
                diagnostics:
                    jsResult.diagnostics
                    + runtimePortLifecycleDiagnostics(
                        portName: connectName,
                        listenerInvoked: false,
                        lifecycleSessionID:
                            jsResult.lifecycleWakeResult?.sessionID,
                        listenerCount:
                            runtimeOnConnectListenerCount(),
                        onMessageListenerCount:
                            runtimeOnMessageListenerCount()
                    )
                    + contract.diagnostics
                    + [
                        "runtime.connect reached a captured service-worker JavaScript runtime.onConnect dispatcher but no Port was opened.",
                    ]
                )
            }
            syntheticPortIDs.insert(portID)
            serviceWorkerLifecyclePortIDs.insert(portID)
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "portKind": .string("serviceWorkerRuntimePort"),
                    "name": .string(connectName),
                    "canOpenRuntimePortNow": .bool(true),
                    "canWakeServiceWorkerNow": .bool(true),
                    "runtimeLoadable": .bool(false),
                ]),
                serviceWorkerLifecycleWakeResult:
                    jsResult.lifecycleWakeResult,
                diagnostics:
                    jsResult.diagnostics
                    + runtimePortLifecycleDiagnostics(
                        portName: connectName,
                        listenerInvoked: true,
                        lifecycleSessionID:
                            jsResult.lifecycleWakeResult?.sessionID,
                        listenerCount:
                            runtimeOnConnectListenerCount(),
                        onMessageListenerCount:
                            runtimeOnMessageListenerCount()
                    )
                    + [
                        "runtime.connect delivered a named Port to captured service-worker runtime.onConnect JavaScript listener(s).",
                        "Port ID \(portID) is bound for later runtime Port.postMessage and disconnect delivery.",
                    ]
            )
        }
        if let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .popupOptionsRuntimeConnect,
            payload: connectPayload,
            payloadSummary: "popup/options runtime.connect",
            keepaliveKind: .runtimePort,
            portID: portID
        ) {
            guard lifecycleResult.dispatched else {
                let contract = ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        lifecycleResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    lastErrorCode: contract.error.rawValue,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + runtimePortLifecycleDiagnostics(
                        portName: connectName,
                        listenerInvoked: false,
                        lifecycleSessionID: lifecycleResult.sessionID,
                        listenerCount:
                            runtimeOnConnectListenerCount(),
                        onMessageListenerCount:
                            runtimeOnMessageListenerCount()
                    )
                    + contract.diagnostics
                    + [
                        "runtime.connect reached the local experimental service-worker lifecycle but no listener accepted it.",
                        ]
                )
            }
            syntheticPortIDs.insert(portID)
            serviceWorkerLifecyclePortIDs.insert(portID)
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "portKind": .string("serviceWorkerRuntimePort"),
                    "canOpenRuntimePortNow": .bool(true),
                    "canWakeServiceWorkerNow": .bool(true),
                    "runtimeLoadable": .bool(false),
                ]),
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + runtimePortLifecycleDiagnostics(
                        portName: connectName,
                        listenerInvoked: true,
                        lifecycleSessionID: lifecycleResult.sessionID,
                        listenerCount:
                            runtimeOnConnectListenerCount(),
                        onMessageListenerCount:
                            runtimeOnMessageListenerCount()
                    )
                    + [
                        "runtime.connect opened a local experimental service-worker Port keepalive.",
                    ]
            )
        }
        syntheticPortIDs.insert(portID)
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "portKind": .string("popupOptionsSyntheticPort"),
                "canOpenRuntimePortNow": .bool(false),
                "canWakeServiceWorkerNow": .bool(false),
                "runtimeLoadable": .bool(false),
            ]),
            diagnostics: [
                "lifecycleSession=none",
                "listenerCount=0",
                "listenerInvoked=false",
                "senderMetadata=extensionPage;tabId=none;frameId=none;documentId=none;urlRedacted=false",
                "portName=callerProvided",
                "runtime.connect returned a popup/options-scoped synthetic Port object.",
                "No service-worker wake or real runtime Port was opened.",
            ]
        )
    }

    private func runtimePortLifecycleDiagnostics(
        portName: String,
        listenerInvoked: Bool,
        lifecycleSessionID: String?,
        listenerCount: Int,
        onMessageListenerCount: Int?
    ) -> [String] {
        [
            "lifecycleSession=\(lifecycleSessionID ?? sharedLifecycleSession?.key.lifecycleSessionID ?? "none")",
            "listenerCount=\(listenerCount)",
            "listenerInvoked=\(listenerInvoked)",
            "onMessageListenerCount=\(onMessageListenerCount.map(String.init) ?? "unknown")",
            "senderMetadata=extensionPage;tabId=none;frameId=none;documentId=none;urlRedacted=false",
            portName.isEmpty
                ? "portName=empty"
                : "portName=callerProvided",
        ]
    }

    private func runtimeOnConnectListenerCount() -> Int {
        sharedLifecycleSession?.runtimeOwner.listenerRegistry.summary
            .listenerCountsByEvent[
                ChromeMV3ServiceWorkerSyntheticListenerEvent
                    .runtimeOnConnect
                    .rawValue
            ] ?? 0
    }

    private func runtimeOnMessageListenerCount() -> Int {
        sharedLifecycleSession?.runtimeOwner.listenerRegistry.summary
            .listenerCountsByEvent[
                ChromeMV3ServiceWorkerSyntheticListenerEvent
                    .runtimeOnMessage
                    .rawValue
            ] ?? 0
    }

    private func runtimePortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime Port postMessage requires portID and message arguments."
            )
        }
        guard serviceWorkerLifecyclePortIDs.contains(portID),
              let sharedLifecycleSession
        else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No open popup/options service-worker runtime Port exists for \(portID).",
                ]
            )
        }
        let delivery = sharedLifecycleSession.deliverRuntimePortMessage(
            portID: portID,
            message: request.arguments[1],
            source: .popupOptionsRuntimeConnect,
            sender: popupServiceWorkerSenderMetadata(),
            payloadSummary:
                "popup/options service-worker runtime Port.postMessage",
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .extensionPageHostHarness
        )
        if delivery.connected == false {
            serviceWorkerLifecyclePortIDs.remove(portID)
            syntheticPortIDs.remove(portID)
        }
        guard delivery.delivered else {
            let contract = ChromeMV3RuntimeLastErrorContract
                .contract(for: .noReceivingEnd)
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    delivery.lastErrorMessage
                    ?? contract.futureLastErrorMessage,
                lastErrorCode: contract.error.rawValue,
                serviceWorkerLifecycleWakeResult:
                    delivery.lifecycleWakeResult,
                diagnostics:
                    delivery.diagnostics
                    + contract.diagnostics
                    + [
                        "popup/options Port.postMessage did not reach a captured service-worker Port.",
                    ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: runtimePortDeliveryPayload(
                delivery,
                direction: "popupOptionsToServiceWorker"
            ),
            serviceWorkerLifecycleWakeResult:
                delivery.lifecycleWakeResult,
            diagnostics:
                delivery.diagnostics
                + [
                    "popup/options Port.postMessage reached service-worker Port.onMessage.",
                ]
        )
    }

    private func runtimePortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime Port disconnect requires one portID argument."
            )
        }
        let wasOpen = serviceWorkerLifecyclePortIDs.remove(portID) != nil
        syntheticPortIDs.remove(portID)
        let delivery = sharedLifecycleSession?.disconnectRuntimePort(
            portID: portID,
            source: .popupOptionsRuntimeConnect,
            sender: popupServiceWorkerSenderMetadata(),
            payloadSummary:
                "popup/options service-worker runtime Port.disconnect",
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .extensionPageHostHarness,
            reason: "Port.disconnect called by popup/options."
        )
        if delivery == nil, wasOpen {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: runtimePortDeliveryPayload(
                delivery
                    ?? ChromeMV3ServiceWorkerRuntimePortDeliveryResult(
                        portID: portID,
                        delivered: wasOpen,
                        connected: false,
                        postedMessages: [],
                        onMessageListenerCount: 0,
                        onDisconnectListenerCount: 0,
                        disconnectReason:
                            wasOpen
                                ? "Port.disconnect called by popup/options."
                                : "Port not found.",
                        lastErrorMessage: nil,
                        lifecycleWakeResult: nil,
                        diagnostics: [
                            wasOpen
                                ? "Popup/options runtime Port keepalive was released without a captured service-worker Port dispatcher."
                                : "Popup/options runtime Port disconnect was a no-op because the Port was already closed.",
                        ]
                    ),
                direction: "popupOptionsToServiceWorker"
            ),
            diagnostics:
                (delivery?.diagnostics ?? [])
                + [
                    "popup/options Port.disconnect propagated through the local experimental service-worker Port path when a captured dispatcher was present.",
                ]
        )
    }

    private func runtimeGetURL(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count <= 1 else {
            return invalidArguments(
                request,
                "runtime.getURL accepts at most one path argument."
            )
        }
        let path = request.arguments.first?.stringValue ?? ""
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return response(
            request: request,
            succeeded: true,
            payload: .string(configuration.extensionBaseURLString + normalizedPath),
            diagnostics: [
                "runtime.getURL returned a deterministic chrome-extension URL string for the extension-owned page.",
            ]
        )
    }

    private func runtimeGetManifest(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.isEmpty else {
            return invalidArguments(
                request,
                "runtime.getManifest does not accept arguments."
            )
        }
        guard let runtimeManifest = configuration.runtimeManifest else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    "Chrome MV3 generated manifest snapshot is unavailable for this popup/options page.",
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.contextNotLoaded.rawValue,
                diagnostics: [
                    "method=runtime.getManifest",
                    "topLevelManifestKeyCount=0",
                    "safeTopLevelManifestFields=",
                    "manifestVersion=unknown",
                    "succeeded=false",
                    "resultClassifier=manifestUnavailable",
                    "runtime.getManifest did not fabricate a manifest when the generated-package manifest snapshot was unavailable.",
                    "runtime.getManifest diagnostics omit manifest body and host filesystem paths.",
                ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: runtimeManifest.manifestPayload,
            diagnostics:
                runtimeManifest.diagnostics
                + [
                    "runtime.getManifest returned a generated-package manifest payload for this extension-owned page.",
                    "runtime.getManifest did not wake service workers or launch native hosts.",
                ]
        )
    }

    private func runtimeSendNativeMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let hostName = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime.sendNativeMessage requires host name and message arguments."
            )
        }
        let owner = nativeMessagingOwner()
        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: request.arguments[1]
        )
        guard result.succeeded else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: result.lastErrorMessage,
                lastErrorCode: result.lastErrorCode?.rawValue
                    ?? ChromeMV3JSBridgeErrorCode.productBlocked.rawValue,
                blockedAPIDiagnostic:
                    configuration.allowlist.blockedDiagnostic(
                        namespace: "runtime",
                        methodName: request.methodName
                    ),
                nativeHostLaunchAttempted:
                    result.lifecycle.processLaunchAttempted,
                diagnostics:
                    result.diagnostics
                    + [
                        "runtime.sendNativeMessage used trusted-host product preflight before any fixture host launch.",
                    ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.response ?? .null,
            nativeHostLaunchAttempted:
                result.lifecycle.processLaunchAttempted,
            diagnostics:
                result.diagnostics
                + [
                    "runtime.sendNativeMessage completed through an approved developer-preview fixture host.",
                    "Stable native messaging remains unavailable.",
                ]
        )
    }

    private func runtimeConnectNative(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1,
              let hostName = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime.connectNative requires one host name argument."
            )
        }
        let owner = nativeMessagingOwner()
        let result = owner.connectNative(hostName: hostName)
        guard result.succeeded, let portID = result.portID else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: result.lastErrorMessage,
                lastErrorCode: result.lastErrorCode?.rawValue
                    ?? ChromeMV3JSBridgeErrorCode.productBlocked.rawValue,
                blockedAPIDiagnostic:
                    configuration.allowlist.blockedDiagnostic(
                        namespace: "runtime",
                        methodName: request.methodName
                    ),
                nativeHostLaunchAttempted:
                    result.lifecycle.processLaunchAttempted,
                diagnostics:
                    result.diagnostics
                    + [
                        "runtime.connectNative used trusted-host product preflight before any fixture host launch.",
                    ]
            )
        }
        syntheticPortIDs.insert(portID)
        let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .nativeMessagingConnect,
            payload: .object([
                "portID": .string(portID),
                "hostName": .string(hostName),
            ]),
            payloadSummary: "trusted native-messaging fixture connectNative",
            componentID: nativeMessagingLifecycleComponentID,
            componentKind: .nativeMessagingFixtureRuntime,
            sourceContext: .nativeApplication,
            keepaliveKind: .nativeMessagingPort,
            portID: portID
        )
        if lifecycleResult != nil {
            serviceWorkerLifecyclePortIDs.insert(portID)
        }
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "hostName": .string(hostName),
                "portKind": .string("nativeMessagingTrustedFixturePort"),
                "canOpenRuntimePortNow": .bool(false),
                "canWakeServiceWorkerNow": .bool(lifecycleResult != nil),
                "runtimeLoadable": .bool(false),
            ]),
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            nativeHostLaunchAttempted:
                result.lifecycle.processLaunchAttempted,
            diagnostics:
                result.diagnostics
                + (lifecycleResult?.diagnostics ?? [])
                + [
                    "runtime.connectNative opened a developer-preview trusted fixture Port.",
                    lifecycleResult == nil
                        ? "No service-worker keepalive is started without a shared lifecycle session."
                        : "Native fixture Port was mirrored into the local experimental service-worker lifecycle.",
                ]
        )
    }

    private func runtimeNativePortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "native Port postMessage requires portID and message arguments."
            )
        }
        guard let owner = nativeMessagingRuntimeOwner else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No native messaging runtime owner exists for this popup/options page."
                ]
            )
        }
        let result = owner.postMessage(
            portID: portID,
            message: request.arguments[1]
        )
        if result.succeeded == false {
            syntheticPortIDs.remove(portID)
        }
        let lifecycleResult =
            result.succeeded
                ? routeServiceWorkerLifecycleEvent(
                    source: .nativeMessagingMessage,
                    payload: .object([
                        "portID": .string(result.portID),
                        "hostName": .string(result.hostName),
                        "message": request.arguments[1],
                    ]),
                    payloadSummary:
                        "trusted native-messaging fixture Port.postMessage",
                    componentID: nativeMessagingLifecycleComponentID,
                    componentKind: .nativeMessagingFixtureRuntime,
                    sourceContext: .nativeApplication,
                    portID: portID
                )
                : nil
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: .object([
                "portID": .string(result.portID),
                "hostName": .string(result.hostName),
                "response": result.response ?? .null,
            ]),
            lastErrorMessage: result.lastErrorMessage,
            lastErrorCode: result.lastErrorCode?.rawValue,
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            nativeHostLaunchAttempted:
                result.lifecycle.processLaunchAttempted,
            diagnostics:
                result.diagnostics
                + (lifecycleResult?.diagnostics ?? [])
        )
    }

    private func runtimeNativePortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "native Port disconnect requires one portID argument."
            )
        }
        guard let owner = nativeMessagingRuntimeOwner else {
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "disconnected": .bool(false),
                    "disconnectReason": .string(
                        "No native messaging runtime owner is available."
                    ),
                ]),
                diagnostics: [
                    "Native Port disconnect was a deterministic no-op because no owner exists."
                ]
            )
        }
        let result = owner.disconnect(
            portID: portID,
            reason: .nativeHostExited
        )
        syntheticPortIDs.remove(portID)
        if serviceWorkerLifecyclePortIDs.remove(portID) != nil {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "hostName": result.hostName.map(ChromeMV3StorageValue.string)
                    ?? .null,
                "disconnected": .bool(result.disconnected),
                "activePortCountAfterDisconnect":
                    .number(Double(result.activePortCountAfterDisconnect)),
            ]),
            nativeHostLaunchAttempted:
                result.lifecycle?.processLaunchAttempted ?? false,
            diagnostics:
                result.diagnostics
                + [
                    "Native fixture Port disconnect releases any mirrored local experimental service-worker keepalive.",
                ]
        )
    }

    private func runtimePortDeliveryPayload(
        _ delivery: ChromeMV3ServiceWorkerRuntimePortDeliveryResult,
        direction: String
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "portID": .string(delivery.portID),
            "delivered": .bool(delivery.delivered),
            "connected": .bool(delivery.connected),
            "disconnected": .bool(delivery.connected == false),
            "direction": .string(direction),
            "postedMessages": .array(delivery.postedMessages),
            "onMessageListenerCount":
                .number(Double(delivery.onMessageListenerCount)),
            "onDisconnectListenerCount":
                .number(Double(delivery.onDisconnectListenerCount)),
        ]
        if let disconnectReason = delivery.disconnectReason {
            object["disconnectReason"] = .string(disconnectReason)
        }
        return .object(object)
    }

    private func preparedSyncStorageBroker() -> ChromeMV3StorageBroker {
        if let syncStorageBroker {
            return syncStorageBroker
        }
        let namespace = ChromeMV3StorageNamespace(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            area: .sync
        )
        var broker = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode:
                Self.syncStoragePersistenceMode(configuration: configuration),
            syncBackend: .localCompatibility
        )
        var diagnostics = [
            "storage.sync localCompatibility broker activated by a gated controlled popup/options storage.sync call.",
            "syncBackend=localCompatibility",
            "No cloud sync, Sumi account sync, or cross-device propagation is claimed.",
        ]
        do {
            if try broker.loadHostSnapshotIfPresent() {
                diagnostics.append(
                    "Loaded existing developer-preview storage.sync localCompatibility snapshot for this profile/extension namespace."
                )
            }
        } catch {
            diagnostics.append(
                "Developer-preview storage.sync localCompatibility snapshot load failed; using empty in-memory state for this popup session."
            )
        }
        storagePersistenceDiagnostics =
            uniqueSortedPopupOptionsBridge(
                storagePersistenceDiagnostics + diagnostics
            )
        return broker
    }

    private func storageArea(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch storageInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let area = input.area
            let areaName = area.chromeAreaName
            let envelope: ChromeMV3StorageAPIOperationResultEnvelope
            switch area {
            case .local:
                envelope = storageOperationHandler.handle(
                    input,
                    broker: &localStorageBroker
                )
            case .session:
                envelope = storageOperationHandler.handle(
                    input,
                    broker: &sessionStorageBroker
                )
            case .sync:
                var broker = preparedSyncStorageBroker()
                envelope = storageOperationHandler.handle(
                    input,
                    broker: &broker
                )
                syncStorageBroker = broker
            case .managed:
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        ChromeMV3StorageErrorCode.areaUnsupported.rawValue,
                    lastErrorCode:
                        ChromeMV3StorageErrorCode.areaUnsupported.rawValue,
                    diagnostics: [
                        "Only storage.local and storage.session are routable by the popup/options storage bridge.",
                    ]
                )
            }
            if envelope.succeeded == false {
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        envelope.futureLastErrorContract?
                        .futureRuntimeLastErrorMessage
                        ?? ChromeMV3JSBridgeErrorCode.invalidArguments
                        .lastErrorMessage,
                    lastErrorCode:
                        envelope.futureLastErrorContract?.code.rawValue
                        ?? ChromeMV3JSBridgeErrorCode.invalidArguments
                        .rawValue,
                    diagnostics:
                        storageLifecycleDiagnostics(
                            request: request,
                            area: area,
                            envelope: envelope,
                            resultPayload: nil,
                            onChangedPayload: nil,
                            serviceWorkerWakeAttempted: false
                        )
                )
            }
            let resultPayload = storageResultPayload(from: envelope)
            let onChanged = popupOnChangedPayload(from: envelope)
            if let onChanged {
                onChangedPayloads.append(onChanged)
            }
            let lifecycleResult = onChanged.flatMap {
                routeServiceWorkerLifecycleEvent(
                    source: .storageChanged,
                    payload: storageOnChangedLifecyclePayload($0),
                    payloadSummary: "popup/options storage.onChanged",
                    sourceContext: configuration.sourceContext.runtimeContext
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: resultPayload,
                onChangedPayload: onChanged,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics:
                        storageLifecycleDiagnostics(
                            request: request,
                            area: area,
                            envelope: envelope,
                            resultPayload: resultPayload,
                            onChangedPayload: onChanged,
                            serviceWorkerWakeAttempted: lifecycleResult != nil
                        )
                        + (lifecycleResult?.diagnostics ?? [])
                        + [
                            "storage.\(areaName) operation used the existing storage operation handler.",
                            lifecycleResult == nil
                                ? "storage.onChanged dispatch is in-page only without a shared lifecycle session."
                                : "storage.onChanged routed through the local experimental service-worker lifecycle.",
                        ]
            )
        }
    }

    private func permissionsContains(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch permissionsInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let result = permissionRuntimeOwner.contains(input: input)
            return response(
                request: request,
                succeeded: true,
                payload: .bool(result.wouldReturn),
                diagnostics: result.diagnostics
            )
        }
    }

    private func permissionsGetAll(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.isEmpty else {
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
            diagnostics: result.diagnostics
        )
    }

    private func permissionsRequest(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch permissionsInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let requestResult = ChromeMV3PermissionsAPIContractEvaluator
                .request(
                    input: input,
                    permissionStore: permissionRuntimeOwner.permissionStore,
                    activeTabStore: permissionRuntimeOwner.activeTabStore
                )
            if requestResult.wouldBeAllowedByModel {
                let application = permissionRuntimeOwner.request(input: input)
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(application.returnedBoolean),
                    permissionEventPayload: nil,
                    diagnostics:
                        application.diagnostics
                            + [
                                "permissions.request returned true because the requested permissions were already granted.",
                                "No prompt was displayed and no new grant was created.",
                            ]
                )
            }

            let promptRequest = ChromeMV3PermissionPromptRequest.make(
                sequence: permissionPromptRequests.count
                    + permissionPromptResults.count
                    + 1,
                extensionName: configuration.extensionID,
                sourceSurface:
                    configuration.sourceContext.permissionPromptSourceSurface,
                input: input,
                requestResult: requestResult,
                permissionStore: permissionRuntimeOwner.permissionStore,
                gateRecord: permissionPromptGate
            )
            permissionPromptRequests.append(promptRequest)
            appendPromptLifecycle(
                promptRequest,
                stage: .promptCreated,
                diagnostics: [
                    "chrome.permissions.request created a developer-preview prompt request record.",
                ]
            )

            guard requestResult.wouldRequirePrompt,
                  promptRequest.promptEligibility.canPrompt
            else {
                let application = permissionRuntimeOwner.request(input: input)
                let blockedResult = promptRequest.result(
                    .blocked,
                    diagnostics: promptRequest.promptEligibility.diagnostics
                )
                permissionPromptResults.append(blockedResult)
                appendPromptLifecycle(
                    promptRequest,
                    stage: .blocked,
                    resultDisposition: .blocked,
                    diagnostics: blockedResult.diagnostics
                )
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: .notProvided,
                    promptRequest: promptRequest,
                    promptResultRecord: blockedResult
                )
                persistPermissionState(diagnostics: diagnostic.diagnostics)
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: diagnostic.message,
                    lastErrorCode: diagnostic.code,
                    diagnostics:
                        application.diagnostics + diagnostic.diagnostics
                )
            }

            guard let permissionPromptPresenter else {
                let unavailable = promptRequest.result(
                    .unavailable,
                    diagnostics: [
                        "Permission prompt required, but no developer-preview presenter is installed.",
                    ]
                )
                permissionPromptResults.append(unavailable)
                appendPromptLifecycle(
                    promptRequest,
                    stage: .blocked,
                    resultDisposition: .unavailable,
                    diagnostics: unavailable.diagnostics
                )
                let application = permissionRuntimeOwner.request(input: input)
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: .notProvided,
                    promptRequest: promptRequest,
                    promptResultRecord: unavailable
                )
                persistPermissionState(diagnostics: diagnostic.diagnostics)
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: diagnostic.message,
                    lastErrorCode: diagnostic.code,
                    diagnostics:
                        application.diagnostics + diagnostic.diagnostics
                )
            }

            appendPromptLifecycle(
                promptRequest,
                stage: .promptPresented,
                diagnostics: [
                    "Developer-preview permission prompt presenter was invoked.",
                ]
            )
            let promptResultRecord =
                permissionPromptPresenter
                .presentChromeMV3PermissionPrompt(promptRequest)
            permissionPromptResults.append(promptResultRecord)
            appendPromptLifecycle(
                promptRequest,
                stage: lifecycleStage(for: promptResultRecord.disposition),
                resultDisposition: promptResultRecord.disposition,
                diagnostics: promptResultRecord.diagnostics
            )

            switch promptResultRecord.disposition {
            case .accepted:
                let application = permissionRuntimeOwner.request(
                    input: input,
                    modeledPromptResult: .accepted,
                    productPromptResult: promptResultRecord
                )
                let dispatchRecord = dispatchPermissionEventIfNeeded(
                    application.result.eventPayloadIfAccepted,
                    sourceSurfaceID: configuration.surfaceID
                )
                invalidateContentScriptEndpoints(
                    reason:
                        "chrome.permissions.request granted host/API access for popup/options bridge."
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .downstreamInvalidated,
                    resultDisposition: .accepted,
                    diagnostics:
                        dispatchRecord?.diagnostics
                        ?? [
                            "No permissions.onAdded dispatch payload was available for downstream invalidation diagnostics.",
                        ]
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: .accepted,
                    diagnostics: application.diagnostics
                )
                persistPermissionState(diagnostics: application.diagnostics)
                let lifecycleResult =
                    application.result.eventPayloadIfAccepted.flatMap {
                        routeServiceWorkerLifecycleEvent(
                            source: .permissionsAdded,
                            payload: permissionsLifecyclePayload($0),
                            payloadSummary:
                                "popup/options permissions.onAdded",
                            sourceContext:
                                configuration.sourceContext.runtimeContext
                        )
                    }
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(application.returnedBoolean),
                    permissionEventPayload:
                        application.result.eventPayloadIfAccepted,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics:
                        application.diagnostics
                            + promptResultRecord.diagnostics
                            + (dispatchRecord?.diagnostics ?? [])
                            + (lifecycleResult?.diagnostics ?? [])
                            + [
                                "permissions.request used an explicit developer-preview product prompt result.",
                            ]
                )
            case .denied:
                let application = permissionRuntimeOwner.request(
                    input: input,
                    modeledPromptResult: .denied,
                    productPromptResult: promptResultRecord
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: .denied,
                    diagnostics: application.diagnostics
                )
                persistPermissionState(diagnostics: application.diagnostics)
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(false),
                    permissionEventPayload: nil,
                    diagnostics:
                        application.diagnostics
                            + promptResultRecord.diagnostics
                            + [
                                "permissions.request was denied by explicit developer-preview product prompt result.",
                            ]
                )
            case .dismissed:
                let application = permissionRuntimeOwner.request(
                    input: input,
                    modeledPromptResult: .dismissed,
                    productPromptResult: promptResultRecord
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: .dismissed,
                    diagnostics: application.diagnostics
                )
                persistPermissionState(diagnostics: application.diagnostics)
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(false),
                    permissionEventPayload: nil,
                    diagnostics:
                        application.diagnostics
                            + promptResultRecord.diagnostics
                            + [
                                "permissions.request was dismissed by explicit developer-preview product prompt result.",
                            ]
                )
            case .blocked, .unavailable:
                let application = permissionRuntimeOwner.request(input: input)
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: .notProvided,
                    promptRequest: promptRequest,
                    promptResultRecord: promptResultRecord
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: promptResultRecord.disposition,
                    diagnostics: diagnostic.diagnostics
                )
                persistPermissionState(diagnostics: diagnostic.diagnostics)
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: diagnostic.message,
                    lastErrorCode: diagnostic.code,
                    diagnostics:
                        application.diagnostics + diagnostic.diagnostics
                )
            }
        }
    }

    private func permissionsRemove(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch permissionsInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let application = permissionRuntimeOwner.remove(input: input)
            guard application.returnedBoolean else {
                let diagnostic = permissionRemoveFailure(
                    result: application.result
                )
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: diagnostic.message,
                    lastErrorCode: diagnostic.code,
                    diagnostics:
                        application.diagnostics + diagnostic.diagnostics
                )
            }
            invalidateContentScriptEndpoints(
                reason:
                    "chrome.permissions.remove revoked host/API access for popup/options bridge."
            )
            if input.permissions.contains("nativeMessaging") {
                nativeMessagingRuntimeOwner?.tearDownForExtensionDisable()
                nativeMessagingRuntimeOwner = nil
                syntheticPortIDs.removeAll()
            }
            let dispatchRecord = dispatchPermissionEventIfNeeded(
                application.result.eventPayloadIfApplied,
                sourceSurfaceID: configuration.surfaceID
            )
            persistPermissionState(diagnostics: application.diagnostics)
            let lifecycleResult =
                application.result.eventPayloadIfApplied.flatMap {
                    routeServiceWorkerLifecycleEvent(
                        source: .permissionsRemoved,
                        payload: permissionsLifecyclePayload($0),
                        payloadSummary: "popup/options permissions.onRemoved",
                        sourceContext: configuration.sourceContext.runtimeContext
                    )
                }
            return response(
                request: request,
                succeeded: true,
                payload: .bool(true),
                permissionEventPayload:
                    application.result.eventPayloadIfApplied,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    application.diagnostics
                    + (dispatchRecord?.diagnostics ?? [])
                    + (lifecycleResult?.diagnostics ?? [])
            )
        }
    }

    private func permissionsEventListenerCountChanged(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let eventName = request.arguments[0].stringValue,
              let listenerCount = request.arguments[1].intValue
        else {
            return invalidArguments(
                request,
                "permissions event listener count updates require eventName and listenerCount."
            )
        }
        let eventKind: ChromeMV3PermissionsAPIEventKind?
        switch eventName {
        case "onAdded":
            eventKind = .onAdded
        case "onRemoved":
            eventKind = .onRemoved
        default:
            eventKind = nil
        }
        guard let eventKind else {
            return invalidArguments(
                request,
                "Unsupported permissions event listener name."
            )
        }
        permissionEventDispatcher?
            .updateChromeMV3PermissionEventListenerCount(
                surfaceID: configuration.surfaceID,
                profileID: configuration.profileID,
                extensionID: configuration.extensionID,
                surface: configuration.surface,
                eventKind: eventKind,
                listenerCount: listenerCount
            )
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "eventName": .string(eventName),
                "listenerCount": .number(Double(max(0, listenerCount))),
                "registeredOpenPage": .bool(permissionEventDispatcher != nil),
            ]),
            diagnostics: [
                "Popup/options page reported permissions.\(eventName) listener count.",
                "Listener tracking is used only for already-open page event dispatch.",
            ]
        )
    }

    private func tabsQuery(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        sourceContextOverride: ChromeMV3JSBridgeSourceContext? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count <= 1 else {
            return invalidArguments(
                request,
                "tabs.query accepts one queryInfo object."
            )
        }
        guard let queryInfo = request.arguments.first?.objectValue
            ?? (request.arguments.isEmpty ? [:] : nil)
        else {
            return invalidArguments(
                request,
                "tabs.query queryInfo must be an object."
            )
        }
        if let registry = contentScriptEndpointRegistry {
            let result = ChromeMV3ContentScriptTabsMessagingBridge.query(
                registry: registry,
                request:
                    ChromeMV3ContentScriptTabsQueryRequest(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        sourceContext:
                            sourceContextOverride
                                ?? configuration.sourceContext,
                        queryInfo: queryInfo,
                        permissionBroker:
                            permissionRuntimeOwner.permissionBroker,
                        activeTabID: nil
                    )
            )
            return response(
                request: request,
                succeeded: true,
                payload: .array(result.tabs),
                sourceContext: sourceContextOverride,
                diagnostics:
                    result.diagnostics
                        + [
                            "tabs.query used the captured content-script endpoint registry for the active eligible tab only.",
                            "No broad product tab enumeration occurred.",
                        ]
            )
        }
        let result = tabRegistry.query(
            queryInfo,
            permissionBroker: permissionRuntimeOwner.permissionBroker
        )
        return response(
            request: request,
            succeeded: true,
            payload: .array(result.tabs),
            diagnostics:
                result.diagnostics
                    + [
                        "tabs.query used a product-gated/redacted model and did not attach a normal-tab bridge.",
                ]
        )
    }

    private func tabsGetCurrent(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.isEmpty else {
            return invalidArguments(
                request,
                "tabs.getCurrent does not accept arguments other than an optional callback."
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: nil,
            diagnostics: [
                "method=tabs.getCurrent namespace=chrome/browser result=undefined redaction=notApplicable sourceContext=\(configuration.sourceContext.rawValue)",
                "tabs.getCurrent was called from a controlled action popup non-tab context; Chrome documents popup views as returning undefined.",
                "No active-tab lookup, broad tab enumeration, or synthetic Tab object was returned.",
            ]
        )
    }

    private func tabsSendMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        sourceContextOverride: ChromeMV3JSBridgeSourceContext? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count >= 2 else {
            return invalidArguments(
                request,
                "tabs.sendMessage requires tabId and message arguments."
            )
        }
        guard request.arguments.count <= 3 else {
            return invalidArguments(
                request,
                "tabs.sendMessage accepts at most tabId, message, and options."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return invalidArguments(
                request,
                "tabs.sendMessage tabId must be an integer."
            )
        }
        let options = request.arguments.count == 3
            ? request.arguments[2].objectValue
            : [:]
        if request.arguments.count == 3, options == nil {
            return invalidArguments(
                request,
                "tabs.sendMessage options must be an object."
            )
        }
        let frameID = options?["frameId"]?.intValue
        let documentID = options?["documentId"]?.stringValue
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs.sendMessage target tab/frame/document.",
                    "Endpoint lookup classification: endpointMissing.",
                ]
            )
        }
        let result = ChromeMV3ContentScriptTabsMessagingBridge.sendMessage(
            registry: registry,
            request:
                ChromeMV3ContentScriptTabsSendMessageRequest(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    sourceContext:
                        sourceContextOverride ?? configuration.sourceContext,
                    extensionBaseURLString:
                        configuration.extensionBaseURLString,
                    tabID: tabID,
                    frameID: frameID,
                    documentID: documentID,
                    message: request.arguments[1],
                    permissionBroker:
                        permissionRuntimeOwner.permissionBroker,
                    responseMode:
                        request.invocationMode == .callback
                            ? .callback
                            : .promise,
                    userGestureAvailable:
                        (sourceContextOverride ?? configuration.sourceContext)
                            == .actionPopup,
                    bridgeCallID: request.bridgeCallID
                )
        )
        if let error = result.selectedLastError {
            return runtimeLastErrorResponse(
                request,
                contract: error,
                diagnostics: result.diagnostics
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.responsePayload ?? .null,
            sourceContext: sourceContextOverride,
            diagnostics:
                result.diagnostics
                    + [
                        "tabs.sendMessage routed to a registered developer-preview content-script endpoint.",
                        "No arbitrary scripting.executeScript path was used.",
                    ]
        )
    }

    @MainActor
    private func tabsSendMessageAsync(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        sourceContextOverride: ChromeMV3JSBridgeSourceContext? = nil
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count >= 2 else {
            return invalidArguments(
                request,
                "tabs.sendMessage requires tabId and message arguments."
            )
        }
        guard request.arguments.count <= 3 else {
            return invalidArguments(
                request,
                "tabs.sendMessage accepts at most tabId, message, and options."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return invalidArguments(
                request,
                "tabs.sendMessage tabId must be an integer."
            )
        }
        let options = request.arguments.count == 3
            ? request.arguments[2].objectValue
            : [:]
        if request.arguments.count == 3, options == nil {
            return invalidArguments(
                request,
                "tabs.sendMessage options must be an object."
            )
        }
        let frameID = options?["frameId"]?.intValue
        let documentID = options?["documentId"]?.stringValue
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs.sendMessage target tab/frame/document.",
                    "Endpoint lookup classification: endpointMissing.",
                ]
            )
        }
        let result = await ChromeMV3ContentScriptTabsMessagingBridge
            .sendMessageAsync(
                registry: registry,
                request:
                    ChromeMV3ContentScriptTabsSendMessageRequest(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        sourceContext:
                            sourceContextOverride
                                ?? configuration.sourceContext,
                        extensionBaseURLString:
                            configuration.extensionBaseURLString,
                        tabID: tabID,
                        frameID: frameID,
                        documentID: documentID,
                        message: request.arguments[1],
                        permissionBroker:
                            permissionRuntimeOwner.permissionBroker,
                        responseMode:
                            request.invocationMode == .callback
                                ? .callback
                                : .promise,
                        userGestureAvailable:
                            (sourceContextOverride ?? configuration.sourceContext)
                                == .actionPopup,
                        bridgeCallID: request.bridgeCallID
                    )
            )
        if let error = result.selectedLastError {
            return runtimeLastErrorResponse(
                request,
                contract: error,
                diagnostics: result.diagnostics
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.responsePayload ?? .null,
            sourceContext: sourceContextOverride,
            diagnostics:
                result.diagnostics
                    + [
                        "tabs.sendMessage routed to a registered developer-preview content-script endpoint.",
                        "No arbitrary scripting.executeScript path was used.",
                    ]
        )
    }

    private func tabsConnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count >= 1 else {
            return invalidArguments(
                request,
                "tabs.connect requires a tabId argument."
            )
        }
        guard request.arguments.count <= 2 else {
            return invalidArguments(
                request,
                "tabs.connect accepts at most tabId and connectInfo."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return invalidArguments(
                request,
                "tabs.connect tabId must be an integer."
            )
        }
        let connectInfo = request.arguments.count == 2
            ? request.arguments[1].objectValue
            : [:]
        if request.arguments.count == 2, connectInfo == nil {
            return invalidArguments(
                request,
                "tabs.connect connectInfo must be an object."
            )
        }
        let frameID = connectInfo?["frameId"]?.intValue
        let documentID = connectInfo?["documentId"]?.stringValue
        let name = connectInfo?["name"]?.stringValue ?? ""
        if let permissionFailure = tabPermissionFailure(
            request: request,
            tabID: tabID,
            requestName: "tabs.connect"
        ) {
            return permissionFailure
        }
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs.connect target tab/frame/document.",
                    "Endpoint lookup classification: endpointMissing.",
                ]
            )
        }
        let lookup = registry.targetEndpointLookup(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID
        )
        guard let endpoint = lookup.endpoint else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics:
                    lookup.diagnostics
                    + [
                        "No content-script endpoint exists for tabs.connect target tab/frame/document."
                    ]
            )
        }
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .tabsConnect,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabID: endpoint.tabID,
            frameID: endpoint.frameID,
            documentID: endpoint.documentID,
            sourceURL: configuration.extensionBaseURLString,
            targetURL: endpoint.frameTarget.urlString
        )
        let permission = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: permissionRuntimeOwner.permissionBroker,
            userGestureAvailable:
                configuration.sourceContext == .actionPopup
        )
        guard permission.allowedForFutureDispatch else {
            return runtimeLastErrorResponse(
                request,
                error: runtimeError(permission),
                diagnostics:
                    permission.brokerDiagnostics
                        + [permission.diagnosticReason]
            )
        }
        guard let port = registry.openPortIfAvailable(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabID: endpoint.tabID,
            frameID: endpoint.frameID,
            documentID: endpoint.documentID,
            name: name
        ) else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics:
                    lookup.diagnostics
                    + [
                        "Target content-script endpoint is present but has no runtime.onConnect listener."
                    ]
            )
        }
        syntheticPortIDs.insert(port.portID)
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(port.portID),
                "portKind": .string("contentScriptEndpointPort"),
                "endpointID": .string(port.endpointID),
                "sender": senderPayload(port.sender),
                "canOpenRuntimePortNow": .bool(true),
                "canWakeServiceWorkerNow": .bool(false),
                "runtimeLoadable": .bool(false),
            ]),
            diagnostics:
                lookup.diagnostics
                    + port.diagnostics
                    + [
                        "tabs.connect created a modeled Port to a content-script endpoint.",
                        "No product service-worker wake or native host launch occurred.",
                    ]
        )
    }

    private func tabsPortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2 else {
            return invalidArguments(
                request,
                "tabs Port postMessage requires portID and message arguments."
            )
        }
        guard let portID = request.arguments[0].stringValue else {
            return invalidArguments(
                request,
                "tabs Port postMessage portID must be a string."
            )
        }
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs Port delivery."
                ]
            )
        }
        let delivery = registry.deliverPopupOptionsPortMessage(
            portID: portID,
            payload: request.arguments[1]
        )
        guard delivery.delivered else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: delivery.diagnostics
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: portDeliveryPayload(delivery),
            diagnostics:
                delivery.diagnostics
                    + [
                        "popup/options Port.postMessage reached the modeled content-script endpoint.",
                        "No service-worker keepalive was opened for Port delivery.",
                    ]
        )
    }

    private func tabsPortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1 else {
            return invalidArguments(
                request,
                "tabs Port disconnect requires one portID argument."
            )
        }
        guard let portID = request.arguments[0].stringValue else {
            return invalidArguments(
                request,
                "tabs Port disconnect portID must be a string."
            )
        }
        guard let registry = contentScriptEndpointRegistry else {
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "disconnected": .bool(false),
                    "disconnectReason": .string(
                        "No content-script endpoint registry is available."
                    ),
                ]),
                diagnostics: [
                    "tabs Port disconnect was a deterministic no-op because no endpoint registry is available."
                ]
            )
        }
        let delivery = registry.disconnectPort(
            portID: portID,
            reason: "Port.disconnect called by popup/options."
        )
        syntheticPortIDs.remove(portID)
        return response(
            request: request,
            succeeded: true,
            payload: portDeliveryPayload(delivery),
            diagnostics:
                delivery.diagnostics
                    + [
                        "popup/options Port.disconnect deterministically notified both modeled endpoints when present.",
                    ]
        )
    }

    private func portDeliveryPayload(
        _ delivery: ChromeMV3ContentScriptPortDeliveryResult
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "portID": .string(delivery.portID),
            "direction": .string(delivery.direction.rawValue),
            "delivered": .bool(delivery.delivered),
            "payload": delivery.payload ?? .null,
        ]
        if let endpointID = delivery.endpointID {
            object["endpointID"] = .string(endpointID)
        }
        if let reason = delivery.disconnectReason {
            object["disconnectReason"] = .string(reason)
        }
        return .object(object)
    }

    private func senderPayload(
        _ sender: ChromeMV3ContentScriptSenderMetadata
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "id": .string(sender.extensionID),
            "extensionID": .string(sender.extensionID),
            "profileID": .string(sender.profileID),
            "tabId": .number(Double(sender.tabID)),
            "frameId": .number(Double(sender.frameID)),
            "documentId": .string(sender.documentID),
            "navigationSequence": .number(Double(sender.navigationSequence)),
            "lifecycleSessionID": .string(sender.lifecycleSessionID),
            "endpointID": .string(sender.endpointID),
            "urlRedacted": .bool(sender.urlRedacted),
            "originRedacted": .bool(sender.originRedacted),
        ]
        if let parentFrameID = sender.parentFrameID {
            object["parentFrameId"] = .number(Double(parentFrameID))
        }
        if let url = sender.url {
            object["url"] = .string(url)
        }
        if let origin = sender.origin {
            object["origin"] = .string(origin)
        }
        if let redactionReason = sender.redactionReason {
            object["redactionReason"] = .string(redactionReason)
        }
        return .object(object)
    }

    private func invalidateContentScriptEndpoints(reason: String) {
        contentScriptEndpointRegistry?.invalidateForPermissionChange(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            permissionBroker: permissionRuntimeOwner.permissionBroker,
            reason: reason
        )
    }

    private func nativeMessagingOwner()
        -> ChromeMV3NativeMessagingRuntimeOwner
    {
        if let owner = nativeMessagingRuntimeOwner,
           owner.activePortCount > 0
        {
            return owner
        }
        let owner = ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                fixtureHostRootPaths:
                    configuration.nativeMessagingFixtureHostRootPaths,
                moduleState: configuration.moduleState,
                explicitInternalNativeMessagingBridgeAllowed:
                    configuration.bridgeAvailable,
                permissionState: nativeMessagingPermissionState(),
                productPolicy: configuration.nativeMessagingProductPolicy,
                trustedHostApprovalRecords:
                    nativeMessagingTrustedHostRecords()
            )
        )
        nativeMessagingRuntimeOwner = owner
        return owner
    }

    private func nativeMessagingPermissionState()
        -> ChromeMV3NativeMessagingPermissionState
    {
        let decision = permissionRuntimeOwner.permissionBroker
            .apiPermissionDecision("nativeMessaging")
        if decision.hasPermission {
            return .grantedByManifest
        }
        if decision.unsupported {
            return .unsupported
        }
        if decision.deferred || decision.wouldNeedPrompt {
            return .deferred
        }
        if decision.denied || decision.revoked {
            return .denied
        }
        return .missing
    }

    private func nativeMessagingTrustedHostRecords()
        -> [ChromeMV3NativeTrustedHostApprovalRecord]
    {
        var records = configuration.nativeMessagingTrustedHostApprovalRecords
        if let rootPath = configuration.nativeMessagingTrustedHostPolicyRootPath,
           rootPath.isEmpty == false
        {
            let store = ChromeMV3NativeTrustedHostPolicyStore(
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
            )
            records.append(
                contentsOf:
                    store.loadSnapshot(
                        profileID: configuration.profileID,
                        extensionID: configuration.extensionID
                    )
                    .records
            )
        }
        return records.sorted {
            if $0.hostName != $1.hostName {
                return $0.hostName < $1.hostName
            }
            return $0.approvalSequence < $1.approvalSequence
        }
    }

    private func appendPromptLifecycle(
        _ request: ChromeMV3PermissionPromptRequest,
        stage: ChromeMV3PermissionPromptLifecycleStage,
        resultDisposition:
            ChromeMV3PermissionPromptResultDisposition? = nil,
        diagnostics: [String]
    ) {
        permissionPromptLifecycleRecords.append(
            ChromeMV3PermissionPromptLifecycleRecord(
                request: request,
                stage: stage,
                resultDisposition: resultDisposition,
                diagnostics: diagnostics
            )
        )
        permissionPromptLifecycleRecords.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            if $0.requestID != $1.requestID {
                return $0.requestID < $1.requestID
            }
            return $0.stage < $1.stage
        }
    }

    private func lifecycleStage(
        for disposition: ChromeMV3PermissionPromptResultDisposition
    ) -> ChromeMV3PermissionPromptLifecycleStage {
        switch disposition {
        case .accepted:
            return .accepted
        case .denied:
            return .denied
        case .dismissed:
            return .dismissed
        case .blocked, .unavailable:
            return .blocked
        }
    }

    private func dispatchPermissionEventIfNeeded(
        _ payload: ChromeMV3PermissionsAPIEventPayload?,
        sourceSurfaceID: String?
    ) -> ChromeMV3PermissionEventDispatchRecord? {
        guard let payload else { return nil }
        guard let permissionEventDispatcher else {
            let registry = ChromeMV3PermissionEventDispatchRegistry()
            let record = registry.dispatchChromeMV3PermissionEvent(
                payload,
                sourceSurfaceID: sourceSurfaceID
            )
            permissionEventDispatches.append(record)
            return record
        }
        let record = permissionEventDispatcher
            .dispatchChromeMV3PermissionEvent(
                payload,
                sourceSurfaceID: sourceSurfaceID
            )
        permissionEventDispatches.append(record)
        return record
    }

    private func persistPermissionState(diagnostics: [String]) {
        guard let permissionStateStore else { return }
        do {
            _ = try permissionStateStore.save(
                owner: permissionRuntimeOwner,
                gateRecord: permissionPromptGate,
                promptRequests: permissionPromptRequests,
                promptResults: permissionPromptResults,
                promptLifecycleRecords: permissionPromptLifecycleRecords,
                diagnostics: diagnostics
            )
            permissionPersistenceDiagnostics =
                uniqueSortedPopupOptionsBridge(
                    permissionPersistenceDiagnostics
                        + [
                            "Persisted developer-preview permission state sidecar for popup/options bridge.",
                        ]
                )
        } catch {
            permissionPersistenceDiagnostics =
                uniqueSortedPopupOptionsBridge(
                    permissionPersistenceDiagnostics
                        + [
                            "Failed to persist developer-preview permission state: \(error.localizedDescription)",
                        ]
                )
        }
    }

    private func runtimeLastErrorResponse(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        error: ChromeMV3RuntimeLastErrorCase,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        runtimeLastErrorResponse(
            request,
            contract:
                ChromeMV3RuntimeLastErrorContract.contract(for: error),
            diagnostics: diagnostics
        )
    }

    private func tabPermissionFailure(
        request: ChromeMV3RuntimeJSBridgeHostRequest,
        tabID: Int,
        requestName: String
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse? {
        guard let tab = tabRegistry.tab(id: tabID) else {
            return nil
        }
        let decision = permissionRuntimeOwner.permissionBroker
            .hostAccessDecision(url: tab.url, tabID: tab.id)
        guard decision.hasHostAccess == false else { return nil }
        let error: ChromeMV3RuntimeLastErrorCase
        if decision.missingReason == .permissionDenied
            || decision.missingReason == .permissionRevoked
        {
            error = .permissionDenied
        } else if decision.missingReason == .activeTabMissing
                    || permissionRuntimeOwner.permissionBroker
                    .activeTabPermissionDeclared
        {
            error = .activeTabMissing
        } else {
            error = .hostPermissionMissing
        }
        return runtimeLastErrorResponse(
            request,
            error: error,
            diagnostics:
                decision.diagnostics
                    + [
                        "\(requestName) target failed host/activeTab permission checks before endpoint lookup.",
                        "Permission denied and noReceivingEnd are kept distinct.",
                    ]
        )
    }

    private func runtimeLastErrorResponse(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        contract: ChromeMV3RuntimeLastErrorContract,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        response(
            request: request,
            succeeded: false,
            lastErrorMessage: contract.futureLastErrorMessage,
            lastErrorCode: contract.error.rawValue,
            diagnostics: diagnostics + contract.diagnostics
        )
    }

    private func runtimeError(
        _ permission: ChromeMV3RuntimeMessagingPermissionDecision
    ) -> ChromeMV3RuntimeLastErrorCase {
        switch permission.missingGrantReason {
        case .missingActiveTabGrant, .activeTabGrantExpired,
             .userGestureRequired:
            return .activeTabMissing
        case .missingHostPermission:
            return .hostPermissionMissing
        case .missingTabPermission, .permissionDenied:
            return .permissionDenied
        case .nativeMessagingBlocked:
            return .nativeMessagingBlocked
        case .none:
            return .permissionDenied
        }
    }

    private func blocked(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        namespace: String,
        code: ChromeMV3JSBridgeErrorCode = .productBlocked,
        message: String? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let diagnostic = configuration.allowlist.blockedDiagnostic(
            namespace: namespace,
            methodName: request.methodName
        )
        return response(
            request: request,
            succeeded: false,
            lastErrorMessage:
                message ?? diagnostic.lastErrorMessage,
            lastErrorCode:
                code == .productBlocked
                    ? diagnostic.lastErrorCode
                    : code.rawValue,
            blockedAPIDiagnostic: diagnostic,
            diagnostics: [
                diagnostic.reason,
                diagnostic.remediation,
                "Roadmap owner: \(diagnostic.roadmapOwner).",
            ]
        )
    }

    private func invalidArguments(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ message: String
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
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
        namespace: String? = nil,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        onChangedPayload: ChromeMV3StorageOnChangedEventPayload? = nil,
        permissionEventPayload: ChromeMV3PermissionsAPIEventPayload? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        blockedAPIDiagnostic:
            ChromeMV3PopupOptionsBlockedAPIDiagnostic? = nil,
        serviceWorkerLifecycleWakeResult:
            ChromeMV3ServiceWorkerInternalWakeResult? = nil,
        nativeHostLaunchAttempted: Bool = false,
        sourceContext: ChromeMV3JSBridgeSourceContext? = nil,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let resolvedNamespace = request?.namespace ?? namespace ?? "unsupported"
        let resolvedMethod = request?.methodName ?? methodName ?? "unknown"
        let mode = request?.invocationMode ?? .promise
        let serviceWorkerWakeAttempted =
            serviceWorkerLifecycleWakeResult != nil
        let response = ChromeMV3PopupOptionsJSBridgeHostResponse(
            bridgeCallID:
                request?.bridgeCallID
                ?? stableIDPopupOptionsBridge(
                    prefix: "popup-options-js-response",
                    parts: [resolvedNamespace, resolvedMethod]
                ),
            namespace: resolvedNamespace,
            methodName: resolvedMethod,
            succeeded: succeeded,
            resultPayload: payload,
            onChangedPayload: onChangedPayload,
            permissionEventPayload: permissionEventPayload,
            lastErrorMessage: succeeded ? nil : lastErrorMessage,
            lastErrorCode: succeeded ? nil : lastErrorCode,
            callbackWouldSetLastError:
                mode == .callback && succeeded == false,
            promiseWouldReject:
                mode == .promise && succeeded == false,
            blockedAPIDiagnostic: blockedAPIDiagnostic,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            serviceWorkerWakeAttempted: serviceWorkerWakeAttempted,
            serviceWorkerLifecycleWakeResult:
                serviceWorkerLifecycleWakeResult,
            nativeHostLaunchAttempted: nativeHostLaunchAttempted,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    configuration.diagnostics
                        + diagnostics
                        + (serviceWorkerLifecycleWakeResult?.diagnostics ?? [])
                        + [
                            "Popup/options bridge handled the call inside an extension-owned WebKit host.",
                            bridgeAttemptDiagnostic(
                                serviceWorkerWakeAttempted:
                                    serviceWorkerWakeAttempted,
                                nativeHostLaunchAttempted:
                                    nativeHostLaunchAttempted
                            ),
                        ]
                )
        )
        callRecords.append(
            ChromeMV3PopupOptionsJSBridgeCallRecord(
                bridgeCallID: response.bridgeCallID,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                surface: configuration.surface,
                sourceContext: sourceContext ?? configuration.sourceContext,
                namespace: resolvedNamespace,
                methodName: resolvedMethod,
                invocationMode: mode,
                argumentShapeSummary:
                    argumentShapeSummary(for: request),
                succeeded: succeeded,
                lastErrorCode: response.lastErrorCode,
                lastErrorMessage: response.lastErrorMessage,
                serviceWorkerWakeAttempted: serviceWorkerWakeAttempted,
                serviceWorkerLifecycleWakeResult:
                    serviceWorkerLifecycleWakeResult,
                nativeHostLaunchAttempted: nativeHostLaunchAttempted,
                normalTabRuntimeBridgeAvailable: false,
                contentScriptAttachmentAvailableInProduct: false,
                diagnostics: response.diagnostics
            )
        )
        #if DEBUG
            recordSanitizedBridgeRoute(
                request: request,
                response: response,
                sourceContext: sourceContext ?? configuration.sourceContext
            )
        #endif
        return response
    }

    private func storageLifecycleDiagnostics(
        request: ChromeMV3RuntimeJSBridgeHostRequest,
        area: ChromeMV3StorageAreaKind,
        envelope: ChromeMV3StorageAPIOperationResultEnvelope,
        resultPayload: ChromeMV3StorageValue?,
        onChangedPayload: ChromeMV3StorageOnChangedEventPayload?,
        serviceWorkerWakeAttempted: Bool
    ) -> [String] {
        let extensionIDHash = stableIDPopupOptionsBridge(
            prefix: "extension",
            parts: [configuration.extensionID]
        )
        let profileIDHash = stableIDPopupOptionsBridge(
            prefix: "profile",
            parts: [configuration.profileID]
        )
        let areaName = area.chromeAreaName
        return uniqueSortedPopupOptionsBridge(
            storagePersistenceDiagnostics
                + storageOperationHandler.state.diagnostics
                + [
                    "storage.\(areaName) developer-preview bridge handled method=\(request.methodName) area=\(areaName) backend=\(storageBackendDiagnostic(area)) keyShape=\(storageKeySelectorShape(request: request)) keyCount=\(storageKeyCount(request: request)) valueShape=\(storageMutationValueShape(request: request)) resultShape=\(storageDiagnosticValueShape(resultPayload)) resultClassifier=\(storageResultClassifier(envelope: envelope)).",
                    "storage.\(areaName) scope is profileIDHash=\(profileIDHash);extensionIDHash=\(extensionIDHash);area=\(areaName).",
                    "storage.\(areaName) changedKeyCount=\(envelope.changedKeys.count);onChangedPayload=\(onChangedPayload == nil ? "none" : "shapeOnly").",
                    storageBackendDetailDiagnostic(area),
                    serviceWorkerWakeAttempted
                        ? "storage.onChanged attempted local experimental service-worker lifecycle routing."
                        : "storage.onChanged did not attempt service-worker wake for this operation.",
                    "Callback-scoped runtime.lastError and Promise rejection behavior are preserved by the popup bridge response envelope.",
                    "No raw storage keys or values are included in popup/storage diagnostics.",
                    "No native host launch occurred for storage.\(areaName).",
                ]
        )
    }

    private func storageBackendDiagnostic(
        _ area: ChromeMV3StorageAreaKind
    ) -> String {
        switch area {
        case .local:
            return "profileLocal"
        case .session:
            return "memorySession"
        case .sync:
            return "localCompatibility"
        case .managed:
            return "unsupported"
        }
    }

    private func storageBackendDetailDiagnostic(
        _ area: ChromeMV3StorageAreaKind
    ) -> String {
        switch area {
        case .sync:
            return "storage.sync backend=localCompatibility; no cloud sync, Sumi account sync, or cross-device propagation is claimed."
        case .local:
            return "storage.local backend=profileLocal."
        case .session:
            return "storage.session backend=memorySession."
        case .managed:
            return "storage.managed backend=unsupported."
        }
    }

    private func storageArgumentShapeSummary(
        for request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> String {
        "storage;method=\(request.methodName);keyShape=\(storageKeySelectorShape(request: request));keyCount=\(storageKeyCount(request: request));valueShape=\(storageMutationValueShape(request: request))"
    }

    private func isStorageRoute(
        namespace: String,
        methodName: String
    ) -> Bool {
        namespace == "storage"
            && (
                methodName.hasPrefix("local.")
                    || methodName.hasPrefix("session.")
                    || methodName.hasPrefix("sync.")
            )
    }

    private func storageAreaName(
        methodName: String
    ) -> String? {
        if methodName.hasPrefix("local.") {
            return "local"
        }
        if methodName.hasPrefix("session.") {
            return "session"
        }
        if methodName.hasPrefix("sync.") {
            return "sync"
        }
        return nil
    }

    private func storageOperationName(
        methodName: String
    ) -> String {
        if let dot = methodName.firstIndex(of: ".") {
            return String(methodName[methodName.index(after: dot)...])
        }
        return methodName
    }

    private func storageKeySelectorShape(
        request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> String {
        switch storageOperationName(methodName: request.methodName) {
        case "clear":
            return request.arguments.isEmpty ? "none" : "unexpected"
        case "set":
            return request.arguments.first?.objectValue == nil
                ? "invalid"
                : "objectKeys"
        case "get", "getBytesInUse", "remove":
            return storageKeySelectorShape(value: request.arguments.first)
        default:
            return "unsupported"
        }
    }

    private func storageKeySelectorShape(
        value: ChromeMV3StorageValue?
    ) -> String {
        guard let value else { return "omitted" }
        switch value {
        case .null:
            return "all"
        case .string:
            return "singleString"
        case .array:
            return "stringArray"
        case .object:
            return "objectDefaults"
        case .bool, .number:
            return "invalid"
        }
    }

    private func storageKeyCount(
        request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Int {
        switch storageOperationName(methodName: request.methodName) {
        case "clear":
            return 0
        case "set":
            return request.arguments.first?.objectValue?.count ?? 0
        case "get", "getBytesInUse", "remove":
            return storageKeyCount(value: request.arguments.first)
        default:
            return 0
        }
    }

    private func storageKeyCount(value: ChromeMV3StorageValue?) -> Int {
        guard let value else { return 0 }
        switch value {
        case .null:
            return 0
        case .string:
            return 1
        case .array(let values):
            return values.count
        case .object(let object):
            return object.count
        case .bool, .number:
            return 0
        }
    }

    private func storageMutationValueShape(
        request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> String {
        guard storageOperationName(methodName: request.methodName) == "set",
              let object = request.arguments.first?.objectValue
        else { return "none" }
        let shapes = uniqueSortedPopupOptionsBridge(
            object.values.map(storageValueTypeShape)
        )
        return "object:keyCount=\(object.count);valueTypes=\(shapes.joined(separator: ","))"
    }

    private func storageValueTypeShape(
        _ value: ChromeMV3StorageValue
    ) -> String {
        switch value {
        case .array(let values):
            return "array:length=\(values.count)"
        case .bool:
            return "bool"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object(let object):
            return "object:keyCount=\(object.count)"
        case .string(let string):
            return "string:length=\(string.count)"
        }
    }

    private func storageDiagnosticValueShape(
        _ value: ChromeMV3StorageValue?
    ) -> String {
        guard let value else { return "none" }
        switch value {
        case .array(let values):
            return "array:length=\(values.count)"
        case .bool:
            return "bool"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object(let object):
            return "object:keyCount=\(object.count)"
        case .string(let string):
            return "string:length=\(string.count)"
        }
    }

    private func storageResultClassifier(
        envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> String {
        if envelope.succeeded {
            return storageResultClassifierName(
                areaName: envelope.area.chromeAreaName
            )
        }
        return envelope.futureLastErrorContract?.code.rawValue
            ?? ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue
    }

    private func storageResultClassifierName(areaName: String) -> String {
        switch areaName {
        case "local":
            return "storageLocalBrokerSucceeded"
        case "session":
            return "storageSessionBrokerSucceeded"
        case "sync":
            return "storageSyncLocalCompatibilitySucceeded"
        default:
            return "storageBrokerSucceeded"
        }
    }

    #if DEBUG
    private func recordSanitizedBridgeRoute(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        response: ChromeMV3PopupOptionsJSBridgeHostResponse,
        sourceContext: ChromeMV3JSBridgeSourceContext
    ) {
        let apiName = "\(response.namespace).\(response.methodName)"
        guard isDebugSnapshotRoute(apiName) else { return }
        let diagnostics = response.diagnostics
        sanitizedBridgeRouteRecords.append(
            ChromeMV3PopupOptionsSanitizedBridgeRouteRecord(
                extensionIDHash:
                    stableIDPopupOptionsBridge(
                        prefix: "extension",
                        parts: [configuration.extensionID]
                    ),
                profileID: configuration.profileID,
                sourceContext: sourceContext.rawValue,
                targetContext:
                    sanitizedTargetContext(
                        namespace: response.namespace,
                        methodName: response.methodName,
                        sourceContext: sourceContext
                    ),
                apiName: apiName,
                safeMessageShapeClassification:
                    safeMessageShapeClassification(
                        request: request,
                        response: response
                    ),
                safeCommandTypeActionFieldNames:
                    safeCommandTypeActionFieldNames(request: request),
                listenerCount:
                    diagnosticIntValue(
                        diagnostics,
                        keys: ["listenerCount", "onMessageListenerCount"]
                    ) ?? 0,
                listenerInvoked:
                    diagnosticBoolValue(diagnostics, key: "listenerInvoked")
                        ?? diagnostics.contains {
                            $0.contains("listener accepted")
                                || $0.contains("reached a content-script runtime.onMessage listener")
                                || $0.contains("dispatched to a captured service-worker")
                        },
                sendResponseCalled:
                    diagnosticBoolValue(diagnostics, key: "sendResponseCalled")
                        ?? false,
                listenerReturnedTrue:
                    diagnosticBoolValue(
                        diagnostics,
                        key: "listenerReturnedTrue"
                    ) ?? false,
                listenerThrew:
                    diagnosticBoolValue(diagnostics, key: "listenerThrew")
                        ?? diagnostics.contains {
                            $0.localizedCaseInsensitiveContains("listener threw")
                        },
                portName: safePortName(request: request),
                portMessageCount: sanitizedPortMessageCount(
                    request: request,
                    response: response
                ),
                resultClassifier:
                    resultClassifier(
                        response: response,
                        diagnostics: diagnostics
                    ),
                firstMissingAPIOrPermissionOrLifecycleError:
                    firstMissingAPIOrPermissionOrLifecycleError(
                        response: response,
                        diagnostics: diagnostics
                    ),
                diagnostics:
                    uniqueSortedPopupOptionsBridge(
                        diagnostics.filter(sanitizedRouteDiagnostic)
                    )
            )
        )
    }

    private func isDebugSnapshotRoute(_ apiName: String) -> Bool {
        [
            "runtime.sendMessage",
            "runtime.connect",
            "runtime.getManifest",
            "runtime.port.postMessage",
            "runtime.port.disconnect",
            "tabs.getCurrent",
            "tabs.query",
            "tabs.sendMessage",
            "tabs.connect",
            "tabs.port.postMessage",
            "tabs.port.disconnect",
            "storage.local.clear",
            "storage.local.get",
            "storage.local.getBytesInUse",
            "storage.local.remove",
            "storage.local.set",
            "storage.session.clear",
            "storage.session.get",
            "storage.session.getBytesInUse",
            "storage.session.remove",
            "storage.session.set",
            "storage.sync.clear",
            "storage.sync.get",
            "storage.sync.getBytesInUse",
            "storage.sync.remove",
            "storage.sync.set",
        ].contains(apiName)
    }

    private func sanitizedTargetContext(
        namespace: String,
        methodName: String,
        sourceContext: ChromeMV3JSBridgeSourceContext
    ) -> String {
        if sourceContext == .serviceWorker {
            switch (namespace, methodName) {
            case ("tabs", "query"):
                return "tabs"
            case ("tabs", "getCurrent"):
                return "tabs"
            case ("tabs", "sendMessage"):
                return "contentScript"
            default:
                return "unknown"
            }
        }
        switch (namespace, methodName) {
        case ("storage", "local.clear"), ("storage", "local.get"),
             ("storage", "local.getBytesInUse"), ("storage", "local.remove"),
             ("storage", "local.set"):
            return "storage.local"
        case ("storage", "session.clear"), ("storage", "session.get"),
             ("storage", "session.getBytesInUse"),
             ("storage", "session.remove"), ("storage", "session.set"):
            return "storage.session"
        case ("storage", "sync.clear"), ("storage", "sync.get"),
             ("storage", "sync.getBytesInUse"), ("storage", "sync.remove"),
             ("storage", "sync.set"):
            return "storage.sync"
        case ("runtime", "getManifest"):
            return "manifest"
        case ("runtime", "sendMessage"), ("runtime", "connect"),
             ("runtime", "port.postMessage"), ("runtime", "port.disconnect"):
            return "serviceWorker"
        case ("tabs", "getCurrent"):
            return "tabs"
        case ("tabs", "query"):
            return "tabs"
        case ("tabs", "sendMessage"), ("tabs", "connect"),
             ("tabs", "port.postMessage"), ("tabs", "port.disconnect"):
            return "contentScript"
        default:
            return "unknown"
        }
    }

    private func safeMessageShapeClassification(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        response: ChromeMV3PopupOptionsJSBridgeHostResponse
    ) -> String {
        if isStorageRoute(
            namespace: response.namespace,
            methodName: response.methodName
        ) {
            let requestShape =
                request.map { storageArgumentShapeSummary(for: $0) }
                ?? "arguments:none"
            return "request=\(requestShape);response=\(sanitizedStorageValueShape(response.resultPayload))"
        }
        let requestShape = sanitizedArgumentShapeSummary(for: request)
        let responseShape = storageValueShape(response.resultPayload)
        return "request=\(requestShape);response=\(responseShape)"
    }

    private func sanitizedArgumentShapeSummary(
        for request: ChromeMV3RuntimeJSBridgeHostRequest?
    ) -> String {
        guard let arguments = request?.arguments else {
            return "arguments:none"
        }
        guard arguments.isEmpty == false else {
            return "arguments:0"
        }
        return arguments.enumerated().map { index, value in
            "arg\(index)=\(sanitizedStorageValueShape(value))"
        }.joined(separator: ";")
    }

    private func sanitizedStorageValueShape(
        _ value: ChromeMV3StorageValue?
    ) -> String {
        guard let value else { return "none" }
        return sanitizedStorageValueShape(value)
    }

    private func sanitizedStorageValueShape(
        _ value: ChromeMV3StorageValue
    ) -> String {
        switch value {
        case .array(let values):
            return "array:length=\(values.count)"
        case .bool:
            return "bool"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object(let object):
            let safeFields = safeCommandTypeActionFieldNames(
                request:
                    ChromeMV3RuntimeJSBridgeHostRequest(
                        bridgeCallID: "shape-only",
                        namespace: "shape",
                        methodName: "shape",
                        invocationMode: .promise,
                        arguments: [.object(object)],
                        listenerID: nil,
                        eventName: nil,
                        portID: nil,
                        diagnostics: []
                    )
            )
            let suffix = safeFields.isEmpty
                ? ""
                : ";safeFields=\(safeFields.joined(separator: ","))"
            return "object:keyCount=\(object.keys.count)\(suffix)"
        case .string(let string):
            return "string:length=\(string.count)"
        }
    }

    private func storageValueShape(_ value: ChromeMV3StorageValue?) -> String {
        guard let value else { return "none" }
        return storageValueShape(value)
    }

    private func safeCommandTypeActionFieldNames(
        request: ChromeMV3RuntimeJSBridgeHostRequest?
    ) -> [String] {
        let safeNames = Set([
            "action",
            "command",
            "kind",
            "messageType",
            "name",
            "operation",
            "requestType",
            "type",
        ])
        let names = request?.arguments.flatMap {
            safeFieldNames(in: $0, safeNames: safeNames)
        } ?? []
        return uniqueSortedPopupOptionsBridge(names)
    }

    private func safeFieldNames(
        in value: ChromeMV3StorageValue,
        safeNames: Set<String>
    ) -> [String] {
        switch value {
        case .object(let object):
            return object.keys.filter { safeNames.contains($0) }
        case .array(let values):
            return values.flatMap {
                safeFieldNames(in: $0, safeNames: safeNames)
            }
        case .bool, .null, .number, .string:
            return []
        }
    }

    private func safePortName(
        request: ChromeMV3RuntimeJSBridgeHostRequest?
    ) -> String? {
        guard let request else { return nil }
        let candidate: String?
        if request.namespace == "tabs",
           request.methodName == "connect",
           request.arguments.count > 1
        {
            candidate = request.arguments[1].objectValue?["name"]?
                .stringValue
        } else if request.methodName == "connect" {
            candidate = request.arguments.first?.objectValue?["name"]?
                .stringValue
        } else {
            candidate = nil
        }
        guard let candidate, candidate.count <= 80,
              candidate.range(
                of: #"(?i)(token|secret|password|credential|cookie|auth)"#,
                options: .regularExpression
              ) == nil
        else { return nil }
        return candidate
    }

    private func sanitizedPortMessageCount(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        response: ChromeMV3PopupOptionsJSBridgeHostResponse
    ) -> Int {
        guard let request else { return 0 }
        if request.methodName.contains("port.postMessage") {
            return response.succeeded ? 1 : 0
        }
        if request.methodName == "connect" {
            return 0
        }
        return 0
    }

    private func resultClassifier(
        response: ChromeMV3PopupOptionsJSBridgeHostResponse,
        diagnostics: [String]
    ) -> String {
        if isStorageRoute(
            namespace: response.namespace,
            methodName: response.methodName
        ) {
            return response.succeeded
                ? storageResultClassifierName(
                    areaName:
                        storageAreaName(methodName: response.methodName)
                        ?? "storage"
                )
                : (response.lastErrorCode ?? "storageBrokerBlocked")
        }
        if let explicit = diagnosticStringValue(
            diagnostics,
            key: "resultClassifier"
        ) {
            return explicit
        }
        if response.succeeded {
            return "listenerRespondedSync"
        }
        if diagnostics.contains(where: {
            $0.localizedCaseInsensitiveContains("listener threw")
        }) {
            return "listenerThrew"
        }
        if diagnostics.contains(where: {
            $0.contains("listener(s) returned without sendResponse")
                || $0.contains("listener returned no response")
        }) {
            return "listenerPresentButNoResponse"
        }
        if response.lastErrorCode == ChromeMV3RuntimeLastErrorCase
            .noReceivingEnd.rawValue
        {
            return "noReceivingEnd"
        }
        return response.lastErrorCode ?? "blocked"
    }

    private func firstMissingAPIOrPermissionOrLifecycleError(
        response: ChromeMV3PopupOptionsJSBridgeHostResponse,
        diagnostics: [String]
    ) -> String? {
        if let lastError = response.lastErrorMessage {
            return lastError
        }
        let needles = [
            "missing",
            "permission",
            "blocked",
            "unavailable",
            "unsupported",
            "lifecycle",
            "no receiving end",
            "no receiver",
            "no listener",
        ]
        return diagnostics.first { diagnostic in
            let lower = diagnostic.lowercased()
            return needles.contains { lower.contains($0) }
        }
    }

    private func diagnosticBoolValue(
        _ diagnostics: [String],
        key: String
    ) -> Bool? {
        guard let raw = diagnosticStringValue(diagnostics, key: key) else {
            return nil
        }
        if raw == "true" { return true }
        if raw == "false" { return false }
        return nil
    }

    private func diagnosticIntValue(
        _ diagnostics: [String],
        keys: [String]
    ) -> Int? {
        for key in keys {
            if let raw = diagnosticStringValue(diagnostics, key: key),
               let value = Int(raw)
            {
                return value
            }
        }
        return nil
    }

    private func diagnosticStringValue(
        _ diagnostics: [String],
        key: String
    ) -> String? {
        let pattern = "\(key)="
        for diagnostic in diagnostics {
            guard let range = diagnostic.range(of: pattern) else {
                continue
            }
            let suffix = diagnostic[range.upperBound...]
            return String(
                suffix.prefix {
                    $0 != " " && $0 != ";" && $0 != "," && $0 != "."
                }
            )
        }
        return nil
    }

    private func sanitizedRouteDiagnostic(_ diagnostic: String) -> Bool {
        let lower = diagnostic.lowercased()
        let blocked = [
            "password",
            "credential",
            "cookie",
            "token",
            "vault",
            "auth payload",
            "form value",
            "sessionid",
        ]
        return blocked.contains { lower.contains($0) } == false
    }
    #endif

    private func argumentShapeSummary(
        for request: ChromeMV3RuntimeJSBridgeHostRequest?
    ) -> String {
        if let request,
           isStorageRoute(
               namespace: request.namespace,
               methodName: request.methodName
           )
        {
            return storageArgumentShapeSummary(for: request)
        }
        guard let arguments = request?.arguments else {
            return "arguments:none"
        }
        guard arguments.isEmpty == false else {
            return "arguments:0"
        }
        return arguments.enumerated().map { index, value in
            "arg\(index)=\(storageValueShape(value))"
        }.joined(separator: ";")
    }

    private func storageValueShape(_ value: ChromeMV3StorageValue) -> String {
        switch value {
        case .array(let values):
            return "array:length=\(values.count)"
        case .bool:
            return "bool"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object(let object):
            return "object:keyCount=\(object.keys.count);keys=\(object.keys.sorted().joined(separator: ","))"
        case .string(let string):
            return "string:length=\(string.count)"
        }
    }

    private func bridgeAttemptDiagnostic(
        serviceWorkerWakeAttempted: Bool,
        nativeHostLaunchAttempted: Bool
    ) -> String {
        if serviceWorkerWakeAttempted && nativeHostLaunchAttempted {
            return "Local experimental service-worker routing and trusted native-host fixture launch were both attempted."
        }
        if serviceWorkerWakeAttempted {
            return "Local experimental service-worker routing was attempted; runtimeLoadable remains false."
        }
        if nativeHostLaunchAttempted {
            return "Native host launch was attempted only after trusted developer-preview preflight passed."
        }
        return "No normal-tab bridge, product content-script attachment, service-worker wake, native host launch, or runtimeLoadable change occurred."
    }

    private func storageInput(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3StorageAPIOperationInput,
        ChromeMV3PopupOptionsBridgeInputError
    > {
        let area: ChromeMV3StorageAreaKind
        switch storageAreaName(methodName: request.methodName) {
        case "local":
            area = .local
        case "session":
            area = .session
        case "sync":
            area = .sync
        default:
            return .failure(.init(message: "Unsupported storage area."))
        }
        let areaName = area.chromeAreaName
        let method = storageOperationName(methodName: request.methodName)
        let operation: ChromeMV3StorageOperationKind
        switch method {
        case "get":
            operation = .get
            guard request.arguments.count <= 1 else {
                return .failure(.init(
                    message:
                        "storage.\(areaName).get accepts at most one key selector."
                ))
            }
        case "set":
            operation = .set
            guard request.arguments.count == 1,
                  request.arguments[0].objectValue != nil
            else {
                return .failure(.init(
                    message:
                        "storage.\(areaName).set requires one object argument."
                ))
            }
        case "remove":
            operation = .remove
            guard request.arguments.count == 1 else {
                return .failure(.init(
                    message:
                        "storage.\(areaName).remove requires a key or key array."
                ))
            }
        case "clear":
            operation = .clear
            guard request.arguments.isEmpty else {
                return .failure(.init(
                    message:
                        "storage.\(areaName).clear does not accept arguments."
                ))
            }
        case "getBytesInUse":
            operation = .getBytesInUse
            guard request.arguments.count <= 1 else {
                return .failure(.init(
                    message:
                        "storage.\(areaName).getBytesInUse accepts at most one key selector."
                ))
            }
        default:
            return .failure(.init(
                message: "Unsupported storage.\(areaName) method."
            ))
        }

        let selector: ChromeMV3StorageAPIKeySelector?
        switch operation {
        case .get, .getBytesInUse:
            switch storageSelector(
                request.arguments.first,
                defaultWhenMissing: .omitted
            ) {
            case .success(let value):
                selector = value
            case .failure(let error):
                return .failure(error)
            }
        case .remove:
            switch storageSelector(
                request.arguments.first,
                defaultWhenMissing: .invalidType("missing")
            ) {
            case .success(let value):
                selector = value
            case .failure(let error):
                return .failure(error)
            }
        default:
            selector = nil
        }
        return .success(
            ChromeMV3StorageAPIOperationInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                area: area,
                operation: operation,
                invocationMode:
                    request.invocationMode == .callback
                        ? .callback
                        : .promise,
                keySelector: selector,
                values: request.arguments.first?.objectValue ?? [:],
                sourceContext: configuration.sourceContext.storageContext,
                diagnostics: [
                    "Popup/options bridge normalized storage.\(areaName) request.",
                ]
            )
        )
    }

    private func storageSelector(
        _ value: ChromeMV3StorageValue?,
        defaultWhenMissing: ChromeMV3StorageAPIKeySelector
    ) -> Result<
        ChromeMV3StorageAPIKeySelector,
        ChromeMV3PopupOptionsBridgeInputError
    > {
        guard let value else { return .success(defaultWhenMissing) }
        switch value {
        case .null:
            return .success(.allKeys)
        case .string(let key):
            return .success(.singleString(key))
        case .array(let values):
            var keys: [String] = []
            for entry in values {
                guard let key = entry.stringValue else {
                    return .failure(.init(
                        message: "Storage key arrays must contain strings."
                    ))
                }
                keys.append(key)
            }
            return .success(.stringArray(keys))
        case .object(let defaults):
            return .success(.defaults(defaults))
        case .bool, .number:
            return .failure(.init(
                message: "Unsupported storage key selector type."
            ))
        }
    }

    private func permissionsInput(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3PermissionsAPIRequestInput,
        ChromeMV3PopupOptionsBridgeInputError
    > {
        guard request.arguments.count == 1,
              let object = request.arguments.first?.objectValue
        else {
            return .failure(.init(
                message:
                    "permissions.\(request.methodName) requires one permissions object."
            ))
        }
        let permissions = stringArray(
            object["permissions"],
            fieldName: "permissions"
        )
        if let error = permissions.error {
            return .failure(.init(message: error))
        }
        let origins = stringArray(object["origins"], fieldName: "origins")
        if let error = origins.error {
            return .failure(.init(message: error))
        }
        return .success(
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                sourceContext: configuration.sourceContext.permissionsContext,
                userGestureModeled:
                    object["__sumiUserGestureModeled"]?.boolValue
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
        return (uniqueSortedPopupOptionsBridge(values), nil)
    }

    private func permissionRequestFailure(
        result: ChromeMV3PermissionsAPIRequestResult,
        promptResult: ChromeMV3ModeledPermissionPromptResult,
        promptRequest: ChromeMV3PermissionPromptRequest? = nil,
        promptResultRecord:
            ChromeMV3PermissionPromptResultRecord? = nil
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions.map(\.classification)
        let promptDiagnostics =
            (promptRequest?.diagnostics ?? [])
            + (promptResultRecord?.diagnostics ?? [])
        if promptResultRecord?.disposition == .unavailable
            || (result.wouldRequirePrompt
                && promptResult == .notProvided
                && promptResultRecord == nil)
        {
            return (
                ChromeMV3JSBridgeErrorCode.productUIUnavailable.rawValue,
                "Permission prompt required, but product permission UI is unavailable in popup/options developer preview.",
                uniqueSortedPopupOptionsBridge(
                    promptDiagnostics
                        + [
                            "Install a developer-preview permission prompt presenter before requesting optional permissions.",
                            "No permission was granted silently.",
                        ]
                )
            )
        }
        if classifications.contains(.missingUserGesture) {
            return (
                "promptRequiredUserGestureMissing",
                "chrome.permissions.request requires a modeled user gesture.",
                ["Request was blocked because no modeled user gesture was supplied."]
            )
        }
        if classifications.contains(.notDeclaredOptional) {
            return (
                "permissionNotDeclaredOptional",
                "Requested permission or origin is not declared optional.",
                ["Only declared optional permissions can be granted."]
            )
        }
        if promptResultRecord?.disposition == .blocked {
            return (
                ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
                "Permission request was blocked by developer-preview permission prompt policy.",
                uniqueSortedPopupOptionsBridge(
                    promptDiagnostics
                        + ["Permission request was blocked before prompting."]
                )
            )
        }
        if result.wouldRequirePrompt && promptResult == .denied {
            return (
                ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
                "Permission request was denied by the developer-preview prompt result.",
                ["Permission request denial was returned deterministically."]
            )
        }
        return (
            ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
            "chrome.permissions.request was rejected by internal permission state.",
            ["Permission request was not grantable by the popup/options bridge."]
        )
    }

    private func permissionRemoveFailure(
        result: ChromeMV3PermissionsAPIRemoveResult
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions.map(\.classification)
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
        return (
            ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
            "chrome.permissions.remove was rejected by internal permission state.",
            ["Permission remove was not applicable."]
        )
    }

    private func storageResultPayload(
        from envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageValue? {
        if envelope.operation == .get {
            return .object(envelope.resultPayload.values)
        }
        if envelope.resultPayload.values.isEmpty == false {
            return .object(envelope.resultPayload.values)
        }
        if let bytes = envelope.resultPayload.bytesInUse {
            return .number(Double(bytes))
        }
        return envelope.resultPayload.voidResult ? .null : nil
    }

    private func popupOnChangedPayload(
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
            serviceWorkerWakeRequired: sharedLifecycleSession != nil,
            blockers:
                sharedLifecycleSession == nil
                    ? [
                        "Popup/options storage.onChanged dispatch is in-page only.",
                        "No service-worker wake is performed without a shared lifecycle session.",
                        "No product normal-tab listener is registered.",
                    ]
                    : [
                        "Popup/options storage.onChanged also routes to the local experimental service-worker lifecycle.",
                        "The default runtime remains off.",
                    ],
            serviceWorkerWakePreflight: nil
        )
    }

    private func storageOnChangedLifecyclePayload(
        _ payload: ChromeMV3StorageOnChangedEventPayload
    ) -> ChromeMV3StorageValue {
        var changes: [String: ChromeMV3StorageValue] = [:]
        for change in payload.changes {
            var object: [String: ChromeMV3StorageValue] = [:]
            if let oldValue = change.oldValue {
                object["oldValue"] = oldValue
            }
            if let newValue = change.newValue {
                object["newValue"] = newValue
            }
            changes[change.key] = .object(object)
        }
        return .object([
            "areaName": .string(payload.areaName),
            "changes": .object(changes),
            "changedKeys":
                .array(payload.changedKeys.map(ChromeMV3StorageValue.string)),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
        ])
    }

    private func permissionsLifecyclePayload(
        _ payload: ChromeMV3PermissionsAPIEventPayload
    ) -> ChromeMV3StorageValue {
        .object([
            "eventKind": .string(payload.eventKind.rawValue),
            "source": .string(payload.source.rawValue),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
            "permissions":
                .array(payload.permissions.map(ChromeMV3StorageValue.string)),
            "origins":
                .array(payload.origins.map(ChromeMV3StorageValue.string)),
        ])
    }
}

enum ChromeMV3PopupOptionsJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3PopupOptions"

    static func source(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    ) -> String {
        #if DEBUG
        let controlledNavigatorCompatibilitySurface =
            configuration.sourceContext == .actionPopup
            && configuration.allowlist
                == ChromeMV3PopupOptionsAPIMethodPolicy
                .controlledActionPopupPolicy
        let controlledTabsGetCurrentCompatibilitySurface =
            controlledNavigatorCompatibilitySurface
            && configuration.allowlist.allowedMethods
                .contains("tabs.getCurrent")
        let controlledExtensionGetBackgroundPageCompatibilitySurface =
            controlledNavigatorCompatibilitySurface
            && configuration.allowlist.allowedMethods
                .contains("extension.getBackgroundPage")
        let controlledRuntimeOnMessageCompatibilitySurface =
            configuration.allowlist.allowedMethods
                .contains("runtime.onMessage")
        let tabsGetCurrentSource =
            controlledTabsGetCurrentCompatibilitySurface
                ? """
          Object.defineProperty(tabs, "getCurrent", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("tabs", "getCurrent", [], cb);
            },
            enumerable: true
          });
        """
                : ""
        let runtimeOnMessageSource =
            controlledRuntimeOnMessageCompatibilitySurface
                ? """
          const runtimeOnMessage = makeEvent("runtime.onMessage", {
            runtimeOnMessage: true
          });
          Object.defineProperty(runtime, "onMessage", {
            get() {
              runtimeOnMessage.__sumiDebugAccess();
              return runtimeOnMessage;
            },
            enumerable: true
          });
        """
                : ""
        #else
        let controlledNavigatorCompatibilitySurface = false
        let controlledTabsGetCurrentCompatibilitySurface = false
        let controlledExtensionGetBackgroundPageCompatibilitySurface = false
        let controlledRuntimeOnMessageCompatibilitySurface = false
        let tabsGetCurrentSource = ""
        let runtimeOnMessageSource = ""
        #endif
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "sourceContext": configuration.sourceContext.rawValue,
            "controlledNavigatorCompatibilitySurface":
                controlledNavigatorCompatibilitySurface,
            "controlledTabsGetCurrentCompatibilitySurface":
                controlledTabsGetCurrentCompatibilitySurface,
            "controlledExtensionGetBackgroundPageCompatibilitySurface":
                controlledExtensionGetBackgroundPageCompatibilitySurface,
            "controlledRuntimeOnMessageCompatibilitySurface":
                controlledRuntimeOnMessageCompatibilitySurface,
            "extensionBaseURLString": configuration.extensionBaseURLString,
            "runtimeManifest":
                configuration.runtimeManifest?.manifestPayload
                .popupOptionsBridgeFoundationObject ?? NSNull(),
            "runtimeManifestAvailable": configuration.runtimeManifest != nil,
            "i18nCatalog":
                configuration.i18nCatalogSnapshot?.foundationObject
                ?? NSNull(),
            "i18nExposed":
                configuration.allowlist.exposedNamespaces.contains("i18n")
                && configuration.allowlist.allowedMethods
                .contains("i18n.getMessage")
                && configuration.allowlist.allowedMethods
                .contains("i18n.getUILanguage"),
            "storageSessionExposed":
                configuration.allowlist.exposedNamespaces
                .contains("storage.session")
                && configuration.allowlist.allowedMethods
                .contains("storage.session.get"),
            "storageSyncExposed":
                configuration.allowlist.exposedNamespaces
                .contains("storage.sync")
                && configuration.allowlist.allowedMethods
                .contains("storage.sync.get"),
            "storageLocalOnChangedExposed":
                configuration.allowlist.allowedMethods
                .contains("storage.local.onChanged"),
            "storageSessionOnChangedExposed":
                configuration.allowlist.allowedMethods
                .contains("storage.session.onChanged"),
            "storageSyncOnChangedExposed":
                configuration.allowlist.allowedMethods
                .contains("storage.sync.onChanged"),
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        #if DEBUG
        let debugSupportSource = debugSupportSource()
        #else
        let debugSupportSource = debugSupportNoopSource()
        #endif
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          const storage = {};
          const local = {};
          const session = {};
          const sync = {};
          const i18n = {};
          const permissions = {};
          const tabs = {};
          const scripting = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;
          let nextPortNumber = 0;
          const portState = new WeakMap();

          \(debugSupportSource)

          function unavailable(namespace, methodName) {
            return {
              bridgeCallID: "popup-options-unavailable",
              namespace,
              methodName,
              succeeded: false,
              resultPayload: null,
              onChangedPayload: null,
              permissionEventPayload: null,
              lastErrorMessage: "Popup/options JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["Popup/options JS bridge handler is unavailable."]
            };
          }

          function bridgePost(namespace, methodName, invocationMode, args, extra) {
            const handler = globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[bridgeName];
            if (!handler || typeof handler.postMessage !== "function") {
              const unavailableResponse = unavailable(namespace, methodName);
              debugMissingAPI(
                debugAPIName(namespace, methodName),
                "unknown pending promise",
                debugTargetContext(namespace, methodName)
              );
              return Promise.resolve(unavailableResponse);
            }
            nextBridgeCallNumber += 1;
            const bridgeCallID = [
              "popup-options-js",
              config.surfaceID,
              namespace,
              methodName,
              String(nextBridgeCallNumber)
            ].join("-");
            const request = Object.assign({
              namespace,
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID,
              arguments: args || []
            }, extra || {});
            debugBridgeStart(
              namespace,
              methodName,
              invocationMode,
              request.arguments,
              bridgeCallID
            );
            try {
              return Promise.resolve(handler.postMessage(request))
                .then((response) => {
                  debugBridgeResolved(response);
                  return response;
                }, (error) => {
                  debugBridgeRejected(namespace, methodName, bridgeCallID, error);
                  throw error;
                });
            } catch (error) {
              debugBridgeRejected(namespace, methodName, bridgeCallID, error);
              return Promise.reject(error);
            }
          }

          function toJSONCompatible(value) {
            if (value === undefined) {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function deepCloneJSONCompatible(value) {
            return JSON.parse(JSON.stringify(value));
          }

          function deepFreezeJSONCompatible(value) {
            if (!value || typeof value !== "object" || Object.isFrozen(value)) {
              return value;
            }
            Object.keys(value).forEach((key) => {
              deepFreezeJSONCompatible(value[key]);
            });
            return Object.freeze(value);
          }

          const runtimeManifestTemplate =
            config.runtimeManifestAvailable
              && config.runtimeManifest
              && typeof config.runtimeManifest === "object"
              && !Array.isArray(config.runtimeManifest)
                ? deepFreezeJSONCompatible(
                    deepCloneJSONCompatible(config.runtimeManifest)
                  )
                : null;

          const i18nCatalogTemplate =
            config.i18nCatalog
              && typeof config.i18nCatalog === "object"
              && !Array.isArray(config.i18nCatalog)
                ? deepFreezeJSONCompatible(
                    deepCloneJSONCompatible(config.i18nCatalog)
                  )
                : deepFreezeJSONCompatible({
                    uiLanguage: "en-US",
                    defaultLocale: null,
                    localeSearchOrder: [],
                    loadedCatalogLocales: [],
                    catalogs: {}
                  });

          function i18nUILanguage() {
            const language = i18nCatalogTemplate.uiLanguage;
            return typeof language === "string" && language
              ? language
              : "en-US";
          }

          function i18nLocaleSearchOrder() {
            const order = i18nCatalogTemplate.localeSearchOrder;
            return Array.isArray(order)
              ? order.filter((locale) => typeof locale === "string" && locale)
              : [];
          }

          function i18nCatalogs() {
            const catalogs = i18nCatalogTemplate.catalogs;
            return catalogs && typeof catalogs === "object" && !Array.isArray(catalogs)
              ? catalogs
              : {};
          }

          function i18nDefaultLocale() {
            const locale = i18nCatalogTemplate.defaultLocale;
            return typeof locale === "string" && locale ? locale : null;
          }

          function i18nNormalizeMessageKey(value) {
            if (typeof value !== "string") {
              return null;
            }
            const trimmed = value.trim();
            if (!/^[A-Za-z0-9_@.-]{1,160}$/.test(trimmed)) {
              return null;
            }
            return trimmed.toLowerCase();
          }

          function i18nLoadedLocaleCount() {
            const loaded = i18nCatalogTemplate.loadedCatalogLocales;
            return Array.isArray(loaded) ? loaded.length : 0;
          }

          function i18nMessageKeyShape(messageName) {
            if (typeof messageName !== "string") {
              return "messageNameType=" + typeof messageName;
            }
            return "messageNameLength=" + String(messageName.length);
          }

          function i18nSubstitutionShape(rawSubstitutions) {
            if (rawSubstitutions === undefined) {
              return "substitutions:0";
            }
            if (typeof rawSubstitutions === "string") {
              return "substitutions:string";
            }
            if (Array.isArray(rawSubstitutions)) {
              return "substitutions:array:length=" + String(rawSubstitutions.length);
            }
            return "substitutions:type=" + typeof rawSubstitutions;
          }

          function i18nParseSubstitutions(rawSubstitutions) {
            if (rawSubstitutions === undefined) {
              return { valid: true, values: [], shape: "substitutions:0" };
            }
            if (typeof rawSubstitutions === "string") {
              return {
                valid: true,
                values: [rawSubstitutions],
                shape: "substitutions:string"
              };
            }
            if (Array.isArray(rawSubstitutions)) {
              if (rawSubstitutions.length > 9) {
                return {
                  valid: false,
                  values: [],
                  shape: "substitutions:array:length=" + String(rawSubstitutions.length)
                };
              }
              return {
                valid: true,
                values: rawSubstitutions.map((value) => {
                  if (value === undefined || value === null) {
                    return "";
                  }
                  return String(value);
                }),
                shape: "substitutions:array:length=" + String(rawSubstitutions.length)
              };
            }
            return {
              valid: false,
              values: [],
              shape: "substitutions:type=" + typeof rawSubstitutions
            };
          }

          function i18nLookupMessage(messageName) {
            const key = i18nNormalizeMessageKey(messageName);
            if (!key) {
              return null;
            }
            const catalogs = i18nCatalogs();
            const searchOrder = i18nLocaleSearchOrder();
            for (const locale of searchOrder) {
              const catalog = catalogs[locale];
              if (
                catalog
                && typeof catalog === "object"
                && Object.prototype.hasOwnProperty.call(catalog, key)
              ) {
                const record = catalog[key];
                if (record && typeof record.message === "string") {
                  return { key, locale, record };
                }
              }
            }
            return { key, locale: null, record: null };
          }

          function i18nResolveSubstitutionContent(content, substitutions) {
            if (typeof content !== "string" || content.length === 0) {
              return "";
            }
            const sentinel = "\\u0000SumiI18nDollar\\u0000";
            return content
              .replace(/\\$\\$/g, sentinel)
              .replace(/\\$([1-9])/g, (_match, index) => {
                return substitutions[Number(index) - 1] || "";
              })
              .replace(new RegExp(sentinel, "g"), "$");
          }

          function i18nFormatMessage(record, substitutions, options) {
            const sentinel = "\\u0000SumiI18nDollar\\u0000";
            let message = String(record.message || "");
            if (options && typeof options === "object" && options.escapeLt === true) {
              message = message.replace(/</g, "&lt;");
            }
            const placeholders =
              record.placeholders
              && typeof record.placeholders === "object"
              && !Array.isArray(record.placeholders)
                ? record.placeholders
                : {};
            return message
              .replace(/\\$\\$/g, sentinel)
              .replace(/\\$([A-Za-z0-9_@.-]+)\\$/g, (match, rawName) => {
                const name = String(rawName || "").toLowerCase();
                if (!Object.prototype.hasOwnProperty.call(placeholders, name)) {
                  return match;
                }
                return i18nResolveSubstitutionContent(
                  placeholders[name],
                  substitutions
                );
              })
              .replace(/\\$([1-9])/g, (_match, index) => {
                return substitutions[Number(index) - 1] || "";
              })
              .replace(new RegExp(sentinel, "g"), "$");
          }

          function i18nBidiInfo() {
            const language = i18nUILanguage().split("-", 1)[0].toLowerCase();
            const rtl = ["ar", "fa", "he", "iw", "ur"].includes(language);
            return rtl
              ? { dir: "rtl", reversedDir: "ltr", startEdge: "right", endEdge: "left" }
              : { dir: "ltr", reversedDir: "rtl", startEdge: "left", endEdge: "right" };
          }

          function i18nPredefinedMessage(messageName) {
            if (typeof messageName !== "string" || messageName.indexOf("@@") !== 0) {
              return null;
            }
            const name = messageName.toLowerCase();
            const bidi = i18nBidiInfo();
            if (name === "@@extension_id") {
              return config.extensionID;
            }
            if (name === "@@ui_locale") {
              return i18nUILanguage().replace(/-/g, "_");
            }
            if (name === "@@bidi_dir") {
              return bidi.dir;
            }
            if (name === "@@bidi_reversed_dir") {
              return bidi.reversedDir;
            }
            if (name === "@@bidi_start_edge") {
              return bidi.startEdge;
            }
            if (name === "@@bidi_end_edge") {
              return bidi.endEdge;
            }
            return null;
          }

          function i18nDebugRecord(methodName, record) {
            debugI18nCall(methodName, Object.assign({
              uiLanguage: i18nUILanguage(),
              defaultLocale: i18nDefaultLocale() || "none",
              localeSearchOrderCount: i18nLocaleSearchOrder().length,
              loadedCatalogLocaleCount: i18nLoadedLocaleCount()
            }, record || {}));
          }

          function invokeCallback(callback, message, args) {
            lastErrorValue = message ? { message } : undefined;
            try {
              callback.apply(undefined, args || []);
            } finally {
              lastErrorValue = undefined;
            }
          }

          function dispatchDisconnect(state, port, message) {
            const previousLastError = lastErrorValue;
            lastErrorValue = message ? { message } : undefined;
            try {
              state.onDisconnect.dispatch(port);
            } finally {
              lastErrorValue = previousLastError;
            }
          }

          function rejectFromResponse(response) {
            const error = new Error(response.lastErrorMessage || "Popup/options JS bridge call failed.");
            try {
              Object.defineProperty(error, "__sumiBridgeResponseRejected", {
                value: true,
                configurable: false
              });
            } catch (_) {
            }
            return Promise.reject(error);
          }

          function callbackArgs(namespace, methodName, response) {
            if (!response.succeeded) {
              return [];
            }
            if (namespace === "storage" && methodName.endsWith(".get")) {
              return [response.resultPayload || {}];
            }
            if (namespace === "storage" && methodName.endsWith(".getBytesInUse")) {
              return [Number(response.resultPayload || 0)];
            }
            if (namespace === "permissions" || methodName === "query") {
              return [response.resultPayload];
            }
            if (namespace === "tabs" && methodName === "getCurrent") {
              return [
                response.resultPayload === null || response.resultPayload === undefined
                  ? undefined
                  : response.resultPayload
              ];
            }
            if (namespace === "runtime" && methodName === "sendMessage") {
              return [response.resultPayload];
            }
            if (namespace === "runtime" && methodName === "sendNativeMessage") {
              return [response.resultPayload];
            }
            return [];
          }

          function promiseValue(namespace, methodName, response) {
            if (namespace === "storage" && methodName.endsWith(".get")) {
              return response.resultPayload || {};
            }
            if (namespace === "storage" && methodName.endsWith(".getBytesInUse")) {
              return Number(response.resultPayload || 0);
            }
            if (namespace === "storage") {
              return undefined;
            }
            if (namespace === "tabs" && methodName === "getCurrent") {
              return response.resultPayload === null || response.resultPayload === undefined
                ? undefined
                : response.resultPayload;
            }
            return response.resultPayload;
          }

          function callbackOrPromise(namespace, methodName, args, callback) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = (args || []).map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 popup/options JavaScript arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = bridgePost(namespace, methodName, mode, bridgeArgs)
              .then((response) => {
                if (response.succeeded && namespace === "storage") {
                  dispatchSyntheticStorageEvent(response);
                }
                if (response.succeeded && namespace === "permissions") {
                  dispatchSyntheticPermissionEvent(response);
                }
                return response;
              });
            if (callback) {
              promise.then((response) => {
                if (response.succeeded) {
                  debugCallbackLastError(namespace, methodName, null);
                  invokeCallback(callback, null, callbackArgs(namespace, methodName, response));
                } else {
                  debugCallbackLastError(namespace, methodName, response.lastErrorMessage);
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              }).catch((error) => {
                const message = error && (error.message || String(error));
                debugCallbackLastError(namespace, methodName, message);
                invokeCallback(callback, message || "Popup/options JS bridge call failed.", []);
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return promiseValue(namespace, methodName, response);
              }
              debugPromiseRejected(namespace, methodName, response.lastErrorMessage);
              return rejectFromResponse(response);
            }).catch((error) => {
              if (!error || error.__sumiBridgeResponseRejected !== true) {
                debugPromiseRejected(namespace, methodName, error && (error.message || String(error)));
              }
              throw error;
            });
          }

          function notifyPermissionListenerCount(eventName, count) {
            if (eventName !== "onAdded" && eventName !== "onRemoved") {
              return;
            }
            bridgePost(
              "permissions",
              "__sumiPermissionEventListenerCount",
              "fireAndForget",
              [eventName, count]
            ).catch(() => {});
          }

          function makeEvent(eventName, options) {
            const listeners = [];
            const eventOptions = options || {};
            const storageAreaName = eventOptions.storageAreaName || null;
            const isStorageAreaEvent = !!storageAreaName;
            const isRuntimeOnMessageEvent =
              eventOptions.runtimeOnMessage === true;
            let accessLogged = false;
            function notifyListenerCountChanged(resultClassifier) {
              notifyPermissionListenerCount(eventName, listeners.length);
              if (isRuntimeOnMessageEvent) {
                debugRuntimeOnMessageEvent(resultClassifier, listeners.length, [
                  "eventObjectPresent=true",
                  "listenerCount=" + String(listeners.length),
                  "listenerRegistryScope=pageSession;profile;extension",
                  "sourceContext=" + config.sourceContext,
                  "targetContext=extensionPage",
                  "senderMetadataShape=none",
                  "responseClassifier=registrationOnly",
                  "inboundRoute=notWired",
                  "No raw message bodies, storage values, form values, URLs, or private payloads are recorded."
                ]);
              }
              if (isStorageAreaEvent) {
                debugStorageEvent("extensionMethodCalled", {
                  apiName: "chrome.storage." + storageAreaName + ".onChanged",
                  targetContext: "storage." + storageAreaName,
                  safeMessageShapeClassification: "storageEventListener",
                  resultClassifier,
                  diagnostics: [
                    "area=" + storageAreaName,
                    "eventObjectPresent=true",
                    "listenerCount=" + String(listeners.length),
                    "changedKeyCount=0",
                    "valueShape=none",
                    "resultClassifier=" + resultClassifier,
                    "No raw storage keys or values are recorded."
                  ]
                });
              }
            }
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                  notifyListenerCountChanged("listener added");
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                  notifyListenerCountChanged("listener removed");
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              hasListeners() {
                return listeners.length > 0;
              },
              __sumiListenerCount() {
                return listeners.length;
              },
              __sumiDebugAccess() {
                if (!isRuntimeOnMessageEvent || accessLogged) {
                  return;
                }
                accessLogged = true;
                debugRuntimeOnMessageEvent("event object present", listeners.length, [
                  "eventObjectPresent=true",
                  "listenerCount=" + String(listeners.length),
                  "listenerRegistryScope=pageSession;profile;extension",
                  "sourceContext=" + config.sourceContext,
                  "targetContext=extensionPage",
                  "senderMetadataShape=none",
                  "responseClassifier=registrationOnly",
                  "inboundRoute=notWired",
                  "No raw message bodies, storage values, form values, URLs, or private payloads are recorded."
                ]);
              },
              __sumiDispatch() {
                const args = Array.prototype.slice.call(arguments);
                const snapshot = listeners.slice();
                snapshot.forEach((listener) => listener.apply(undefined, args));
                return {
                  listenerCount: snapshot.length,
                  listenerInvoked: snapshot.length > 0
                };
              }
            });
          }

          const storageOnChanged = makeEvent("storage.onChanged");
          const storageAreaOnChanged = {
            local: config.storageLocalOnChangedExposed
              ? makeEvent("storage.local.onChanged", { storageAreaName: "local" })
              : null,
            session: config.storageSessionOnChangedExposed
              ? makeEvent("storage.session.onChanged", { storageAreaName: "session" })
              : null,
            sync: config.storageSyncOnChangedExposed
              ? makeEvent("storage.sync.onChanged", { storageAreaName: "sync" })
              : null
          };
          const permissionsOnAdded = makeEvent("onAdded");
          const permissionsOnRemoved = makeEvent("onRemoved");

          function normalizeOnChangedPayload(payload) {
            if (
              !payload
              || !["local", "session", "sync"].includes(payload.areaName)
              || !Array.isArray(payload.changes)
            ) {
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
            if (payload && Object.keys(payload.changes).length > 0) {
              const changedKeyCount = Object.keys(payload.changes).length;
              const globalDispatch =
                storageOnChanged.__sumiDispatch(payload.changes, payload.areaName);
              const areaEvent = storageAreaOnChanged[payload.areaName] || null;
              const areaDispatch = areaEvent
                ? areaEvent.__sumiDispatch(payload.changes, payload.areaName)
                : { listenerCount: 0, listenerInvoked: false };
              debugStorageEvent("extensionMethodCalled", {
                apiName: "chrome.storage." + payload.areaName + ".onChanged",
                targetContext: "storage." + payload.areaName,
                safeMessageShapeClassification: "storageEventDispatch",
                resultClassifier: areaEvent
                  ? "storage area onChanged dispatched"
                  : "storage area onChanged unavailable",
                diagnostics: [
                  "area=" + payload.areaName,
                  "eventObjectPresent=" + String(!!areaEvent),
                  "listenerCount=" + String(areaDispatch.listenerCount),
                  "globalListenerCount=" + String(globalDispatch.listenerCount),
                  "changedKeyCount=" + String(changedKeyCount),
                  "valueShape=" + debugStorageChangeValueShape(payload.changes),
                  "resultClassifier=" + (
                    areaEvent
                      ? "storage area onChanged dispatched"
                      : "storage area onChanged unavailable"
                  ),
                  "No raw storage keys or values are recorded."
                ]
              });
            }
          }

          function normalizePermissionEvent(rawPayload) {
            if (!rawPayload || typeof rawPayload !== "object") {
              return null;
            }
            return {
              eventKind: rawPayload.eventKind,
              permissions: Array.isArray(rawPayload.permissions)
                ? rawPayload.permissions.slice().sort()
                : [],
              origins: Array.isArray(rawPayload.origins)
                ? rawPayload.origins.slice().sort()
                : []
            };
          }

          function dispatchSyntheticPermissionEvent(response) {
            const payload = normalizePermissionEvent(response && response.permissionEventPayload);
            if (!payload) {
              return;
            }
            globalThis.__sumiDispatchChromeMV3PermissionEvent(payload);
          }

          Object.defineProperty(globalThis, "__sumiDispatchChromeMV3PermissionEvent", {
            value(rawPayload) {
              const payload = normalizePermissionEvent(rawPayload);
              if (!payload) {
                return { dispatched: false, listenerCount: 0, eventKind: "" };
              }
              const target = payload.eventKind === "onAdded"
                ? permissionsOnAdded
                : (payload.eventKind === "onRemoved" ? permissionsOnRemoved : null);
              if (!target) {
                return { dispatched: false, listenerCount: 0, eventKind: payload.eventKind };
              }
              const listenerCount = target.hasListeners() ? 1 : 0;
              if (!target.hasListeners()) {
                return { dispatched: false, listenerCount: 0, eventKind: payload.eventKind };
              }
              target.__sumiDispatch({
                permissions: payload.permissions,
                origins: payload.origins
              });
              return {
                dispatched: true,
                listenerCount,
                eventKind: payload.eventKind
              };
            },
            configurable: false
          });

          function optionalKeysAndCallback(first, second) {
            if (typeof first === "function") {
              return { keys: undefined, callback: first };
            }
            return {
              keys: first,
              callback: typeof second === "function" ? second : null
            };
          }

          function makePortEvent(eventName, stateProvider) {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                  const state = stateProvider ? stateProvider() : null;
                  debugPortEvent("portListenerAdded", {
                    apiName: eventName,
                    portName: state ? debugSafePortName(state.name) : null,
                    resultClassifier: "listener added",
                    diagnostics: [
                      "Port event listener added; listenerCount=" + String(listeners.length)
                    ]
                  });
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                  const state = stateProvider ? stateProvider() : null;
                  debugPortEvent("portListenerRemoved", {
                    apiName: eventName,
                    portName: state ? debugSafePortName(state.name) : null,
                    resultClassifier: "listener removed",
                    diagnostics: [
                      "Port event listener removed; listenerCount=" + String(listeners.length)
                    ]
                  });
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              dispatch() {
                const args = Array.prototype.slice.call(arguments);
                const state = stateProvider ? stateProvider() : null;
                debugPortEvent(
                  eventName === "Port.onMessage"
                    ? "portOnMessageDispatched"
                    : "portOnDisconnectDispatched",
                  {
                    apiName: eventName,
                    portName: state ? debugSafePortName(state.name) : null,
                    safeMessageShapeClassification: debugArgsShape(args),
                    resultClassifier:
                      listeners.length > 0
                        ? "Port response delivered"
                        : "Port response not delivered",
                    diagnostics: [
                      "Port event dispatched; listenerCount=" + String(listeners.length)
                    ]
                  }
                );
                listeners.slice().forEach((listener) => listener.apply(undefined, args));
              }
            });
          }

          function createPort(name, delivery) {
            const port = {};
            const state = {
              id: null,
              name: name || "",
              disconnected: false,
              delivery: delivery || null,
              sender: null,
              pendingMessages: [],
              deliveredMessageCount: 0,
              onMessage: null,
              onDisconnect: null
            };
            state.onMessage = makePortEvent("Port.onMessage", () => state);
            state.onDisconnect = makePortEvent("Port.onDisconnect", () => state);
            function markDisconnected(message) {
              if (state.disconnected) {
                return;
              }
              state.disconnected = true;
              state.pendingMessages = [];
              debugPortEvent("portDisconnected", {
                apiName: "Port.disconnect",
                portName: debugSafePortName(state.name),
                resultClassifier: message ? "lastError" : "disconnected",
                firstMissingAPIOrPermissionOrLifecycleError:
                  debugSanitizedMessage(message),
                diagnostics: [
                  message
                    ? "Port disconnected with runtime.lastError."
                    : "Port disconnected."
                ]
              });
              dispatchDisconnect(state, port, message || null);
            }
            function dispatchPostedMessages(payload) {
              const messages = payload && Array.isArray(payload.postedMessages)
                ? payload.postedMessages
                : [];
              const nextMessages = messages.slice(state.deliveredMessageCount);
              state.deliveredMessageCount = messages.length;
              nextMessages.forEach((postedMessage) => {
                state.onMessage.dispatch(postedMessage, port);
              });
              if (payload && payload.connected === false) {
                markDisconnected(null);
              }
            }
            function sendNativePortMessage(message) {
              debugPortEvent("portMessageCalled", {
                apiName: "Port.postMessage",
                portName: debugSafePortName(state.name),
                safeMessageShapeClassification: debugValueShape(message, 0),
                resultClassifier: "called",
                diagnostics: ["Port.postMessage called by popup."]
              });
              if (!state.delivery || !state.delivery.namespace || !state.delivery.postMessage) {
                state.onMessage.dispatch(message, port);
                return;
              }
              if (!state.id) {
                state.pendingMessages.push(message);
                debugPortEvent("portMessageQueued", {
                  apiName: "Port.postMessage",
                  portName: debugSafePortName(state.name),
                  safeMessageShapeClassification: debugValueShape(message, 0),
                  resultClassifier: "queued",
                  diagnostics: ["Port.postMessage queued until bridge Port ID resolves."]
                });
                return;
              }
              bridgePost(
                state.delivery.namespace,
                state.delivery.postMessage,
                "fireAndForget",
                [state.id, message]
              ).then((response) => {
                if (!response.succeeded) {
                  debugPortEvent("portMessageBridgeFailed", {
                    apiName: state.delivery.namespace + "." + state.delivery.postMessage,
                    portName: debugSafePortName(state.name),
                    resultClassifier: "Port message not delivered",
                    firstMissingAPIOrPermissionOrLifecycleError:
                      debugSanitizedMessage(response.lastErrorMessage),
                    diagnostics: ["Port.postMessage bridge response failed."]
                  });
                  markDisconnected(response.lastErrorMessage);
                  return;
                }
                debugPortEvent("portMessageDelivered", {
                  apiName: state.delivery.namespace + "." + state.delivery.postMessage,
                  portName: debugSafePortName(state.name),
                  resultClassifier: "Port message delivered",
                  diagnostics: ["Port.postMessage bridge response succeeded."]
                });
                dispatchPostedMessages(response.resultPayload || {});
              }).catch(() => markDisconnected("Native messaging port is closed."));
            }
            function flushPendingMessages() {
              if (!state.id || state.disconnected || state.pendingMessages.length === 0) {
                return;
              }
              const messages = state.pendingMessages.splice(0, state.pendingMessages.length);
              messages.forEach(sendNativePortMessage);
            }
            Object.defineProperty(port, "name", {
              value: name || "",
              enumerable: true
            });
            Object.defineProperty(port, "sender", {
              get() {
                return state.sender || undefined;
              },
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
                sendNativePortMessage(toJSONCompatible(message));
              },
              enumerable: true
            });
            Object.defineProperty(port, "disconnect", {
              value() {
                if (state.disconnected) {
                  return;
                }
                if (state.delivery && state.delivery.namespace && state.delivery.disconnect && state.id) {
                  bridgePost(
                    state.delivery.namespace,
                    state.delivery.disconnect,
                    "fireAndForget",
                    [state.id]
                  );
                }
                markDisconnected();
              },
              enumerable: true
            });
            portState.set(port, state);
            state.flushPendingMessages = flushPendingMessages;
            state.markDisconnected = markDisconnected;
            return port;
          }

          function parseConnectName(rawArgs) {
            const args = Array.prototype.slice.call(rawArgs);
            if (args.length === 1 && args[0] && typeof args[0] === "object") {
              return typeof args[0].name === "string" ? args[0].name : "";
            }
            if (args.length === 2 && args[1] && typeof args[1] === "object") {
              return typeof args[1].name === "string" ? args[1].name : "";
            }
            return "";
          }

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "getURL", {
            value(path) {
              const raw = typeof path === "string" ? path : "";
              return config.extensionBaseURLString + raw.replace(/^\\/+/, "");
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "getManifest", {
            value() {
              bridgePost(
                "runtime",
                "getManifest",
                "fireAndForget",
                []
              ).catch(() => {});
              if (!runtimeManifestTemplate) {
                debugRuntimeGetManifest(null, false);
                debugPostGetManifestBootstrapSentinel(false);
                throw new Error(
                  "Chrome MV3 generated manifest snapshot is unavailable."
                );
              }
              const manifest = deepCloneJSONCompatible(runtimeManifestTemplate);
              debugRuntimeGetManifest(manifest, true);
              debugPostGetManifestBootstrapSentinel(true);
              return manifest;
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
              return callbackOrPromise("runtime", "sendMessage", rawArgs, callback);
            },
            enumerable: true
          });
          \(runtimeOnMessageSource)

          Object.defineProperty(runtime, "connect", {
            value() {
              const args = Array.prototype.slice.call(arguments);
              const port = createPort(parseConnectName(args), {
                namespace: "runtime",
                postMessage: "port.postMessage",
                disconnect: "port.disconnect"
              });
              const state = portState.get(port);
              nextPortNumber += 1;
              state.id = [
                config.surfaceID,
                "runtime-port",
                String(nextPortNumber)
              ].join(":");
              bridgePost("runtime", "connect", "fireAndForget", args.map(toJSONCompatible))
                .then((response) => {
                  if (!response.succeeded) {
                    state.markDisconnected(response.lastErrorMessage);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  state.sender = payload.sender || null;
                  state.flushPendingMessages();
                })
                .catch(() => state.markDisconnected(null));
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "sendNativeMessage", {
            value(application, message, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "runtime",
                "sendNativeMessage",
                [application, message],
                cb
              );
            },
            enumerable: true
          });

          const nativeConnectMethod = "connect" + "Native";
          Object.defineProperty(runtime, nativeConnectMethod, {
            value(application) {
              const port = createPort("", {
                namespace: "runtime",
                postMessage: "nativePort.postMessage",
                disconnect: "nativePort.disconnect"
              });
              const state = portState.get(port);
              bridgePost("runtime", nativeConnectMethod, "fireAndForget", [application])
                .then((response) => {
                  if (!response.succeeded) {
                    state.markDisconnected(response.lastErrorMessage);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  state.flushPendingMessages();
                })
                .catch(() => state.markDisconnected("Native messaging port is closed."));
              return port;
            },
            enumerable: true
          });

          function defineStorageArea(areaObject, areaName) {
            Object.defineProperty(areaObject, "get", {
              value(keys, callback) {
                const parsed = optionalKeysAndCallback(keys, callback);
                const args = parsed.keys === undefined ? [] : [parsed.keys];
                return callbackOrPromise("storage", areaName + ".get", args, parsed.callback);
              },
              enumerable: true
            });
            Object.defineProperty(areaObject, "set", {
              value(items, callback) {
                const cb = typeof callback === "function" ? callback : null;
                return callbackOrPromise("storage", areaName + ".set", [items], cb);
              },
              enumerable: true
            });
            Object.defineProperty(areaObject, "remove", {
              value(keys, callback) {
                const cb = typeof callback === "function" ? callback : null;
                return callbackOrPromise("storage", areaName + ".remove", [keys], cb);
              },
              enumerable: true
            });
            Object.defineProperty(areaObject, "clear", {
              value(callback) {
                const cb = typeof callback === "function" ? callback : null;
                return callbackOrPromise("storage", areaName + ".clear", [], cb);
              },
              enumerable: true
            });
            Object.defineProperty(areaObject, "getBytesInUse", {
              value(keys, callback) {
                const parsed = optionalKeysAndCallback(keys, callback);
                const args = parsed.keys === undefined ? [] : [parsed.keys];
                return callbackOrPromise("storage", areaName + ".getBytesInUse", args, parsed.callback);
              },
              enumerable: true
            });
          }

          function storageAreaObject(areaName, areaObject) {
            return new Proxy(Object.freeze(areaObject), {
              get(target, prop, receiver) {
                if (prop === "onChanged" && !Reflect.has(target, prop)) {
                  debugMissingAPI(
                    "chrome.storage." + areaName + ".onChanged",
                    "missing storage." + areaName + ".onChanged",
                    "storage." + areaName
                  );
                  return undefined;
                }
                return Reflect.get(target, prop, receiver);
              }
            });
          }

          function namespaceObject(namespaceName, namespaceObject) {
            return new Proxy(Object.freeze(namespaceObject), {
              get(target, prop, receiver) {
                if (
                  typeof prop === "string"
                  && !Reflect.has(target, prop)
                  && /^on[A-Z]/.test(prop)
                ) {
                  debugMissingAPI(
                    "chrome." + namespaceName + "." + prop,
                    "missing " + namespaceName + "." + prop,
                    namespaceName
                  );
                  return undefined;
                }
                return Reflect.get(target, prop, receiver);
              }
            });
          }

          defineStorageArea(local, "local");
          if (storageAreaOnChanged.local) {
            Object.defineProperty(local, "onChanged", {
              value: storageAreaOnChanged.local,
              enumerable: true
            });
          }
          if (config.storageSessionExposed) {
            defineStorageArea(session, "session");
            if (storageAreaOnChanged.session) {
              Object.defineProperty(session, "onChanged", {
                value: storageAreaOnChanged.session,
                enumerable: true
              });
            }
          }
          if (config.storageSyncExposed) {
            defineStorageArea(sync, "sync");
            if (storageAreaOnChanged.sync) {
              Object.defineProperty(sync, "onChanged", {
                value: storageAreaOnChanged.sync,
                enumerable: true
              });
            }
          }
          const runtimeObject = namespaceObject("runtime", runtime);
          Object.defineProperty(storage, "local", {
            value: storageAreaObject("local", local),
            enumerable: true
          });
          if (config.storageSessionExposed) {
            Object.defineProperty(storage, "session", {
              value: storageAreaObject("session", session),
              enumerable: true
            });
          }
          if (config.storageSyncExposed) {
            Object.defineProperty(storage, "sync", {
              value: storageAreaObject("sync", sync),
              enumerable: true
            });
          }
          Object.defineProperty(storage, "onChanged", {
            value: storageOnChanged,
            enumerable: true
          });
          const storageObject = new Proxy(Object.freeze(storage), {
            get(target, prop, receiver) {
              if (
                typeof prop === "string"
                && (
                  ["managed"].includes(prop)
                  || (prop === "sync" && !config.storageSyncExposed)
                  || (prop === "session" && !config.storageSessionExposed)
                )
              ) {
                debugMissingAPI(
                  "chrome.storage." + prop,
                  "missing storage." + prop,
                  "storage." + prop
                );
                return undefined;
              }
              return Reflect.get(target, prop, receiver);
            }
          });

          Object.defineProperty(i18n, "getUILanguage", {
            value() {
              const uiLanguage = i18nUILanguage();
              i18nDebugRecord("getUILanguage", {
                methodName: "chrome.i18n.getUILanguage",
                selectedLocale: uiLanguage,
                fallbackLocaleUsed: false,
                messageKeyShape: "none",
                substitutionShape: "arguments:0",
                resultClassifier: "uiLanguageReturned",
                diagnostics: [
                  "method=chrome.i18n.getUILanguage",
                  "uiLanguage=" + uiLanguage,
                  "selectedLocale=" + uiLanguage,
                  "fallbackLocaleUsed=false",
                  "messageKeyCount=0",
                  "substitutionShape=arguments:0",
                  "resultClassifier=uiLanguageReturned",
                  "No raw localized message values are recorded."
                ]
              });
              return uiLanguage;
            },
            enumerable: true
          });

          Object.defineProperty(i18n, "getMessage", {
            value(messageName, substitutions, options) {
              const rawSubstitutionShape = i18nSubstitutionShape(substitutions);
              const keyShape = i18nMessageKeyShape(messageName);
              if (typeof messageName !== "string") {
                i18nDebugRecord("getMessage", {
                  methodName: "chrome.i18n.getMessage",
                  selectedLocale: "none",
                  fallbackLocaleUsed: false,
                  messageKeyShape: keyShape,
                  substitutionShape: rawSubstitutionShape,
                  resultClassifier: "invalidMessageName",
                  diagnostics: [
                    "method=chrome.i18n.getMessage",
                    "messageKeyCount=0",
                    "messageKeyShape=" + keyShape,
                    "substitutionShape=" + rawSubstitutionShape,
                    "selectedLocale=none",
                    "fallbackLocaleUsed=false",
                    "resultClassifier=invalidMessageName",
                    "No raw localized message values are recorded."
                  ]
                });
                return undefined;
              }
              const substitutionsResult = i18nParseSubstitutions(substitutions);
              if (!substitutionsResult.valid) {
                i18nDebugRecord("getMessage", {
                  methodName: "chrome.i18n.getMessage",
                  selectedLocale: "none",
                  fallbackLocaleUsed: false,
                  messageKeyShape: keyShape,
                  substitutionShape: substitutionsResult.shape,
                  resultClassifier: "invalidSubstitutions",
                  diagnostics: [
                    "method=chrome.i18n.getMessage",
                    "messageKeyCount=1",
                    "messageKeyShape=" + keyShape,
                    "substitutionShape=" + substitutionsResult.shape,
                    "selectedLocale=none",
                    "fallbackLocaleUsed=false",
                    "resultClassifier=invalidSubstitutions",
                    "No raw localized message values are recorded."
                  ]
                });
                return undefined;
              }
              const predefined = i18nPredefinedMessage(messageName);
              if (predefined !== null) {
                i18nDebugRecord("getMessage", {
                  methodName: "chrome.i18n.getMessage",
                  selectedLocale: "predefined",
                  fallbackLocaleUsed: false,
                  messageKeyShape: keyShape,
                  substitutionShape: substitutionsResult.shape,
                  resultClassifier: "predefinedMessageReturned",
                  diagnostics: [
                    "method=chrome.i18n.getMessage",
                    "messageKeyCount=1",
                    "messageKeyShape=" + keyShape,
                    "substitutionShape=" + substitutionsResult.shape,
                    "selectedLocale=predefined",
                    "fallbackLocaleUsed=false",
                    "resultClassifier=predefinedMessageReturned",
                    "No raw localized message values are recorded."
                  ]
                });
                return predefined;
              }
              const lookup = i18nLookupMessage(messageName);
              if (!lookup || !lookup.record) {
                i18nDebugRecord("getMessage", {
                  methodName: "chrome.i18n.getMessage",
                  selectedLocale: "none",
                  fallbackLocaleUsed: false,
                  messageKeyShape: keyShape,
                  substitutionShape: substitutionsResult.shape,
                  resultClassifier: "messageMissing",
                  diagnostics: [
                    "method=chrome.i18n.getMessage",
                    "messageKeyCount=1",
                    "messageKeyShape=" + keyShape,
                    "substitutionShape=" + substitutionsResult.shape,
                    "selectedLocale=none",
                    "fallbackLocaleUsed=false",
                    "resultClassifier=messageMissing",
                    "No raw localized message values are recorded."
                  ]
                });
                return "";
              }
              const result = i18nFormatMessage(
                lookup.record,
                substitutionsResult.values,
                options
              );
              const primaryLocale = i18nLocaleSearchOrder()[0] || null;
              const fallbackLocaleUsed =
                primaryLocale !== null && lookup.locale !== primaryLocale;
              i18nDebugRecord("getMessage", {
                methodName: "chrome.i18n.getMessage",
                selectedLocale: lookup.locale || "none",
                fallbackLocaleUsed,
                messageKeyShape: keyShape,
                substitutionShape: substitutionsResult.shape,
                resultClassifier:
                  result.length > 0
                    ? "localizedMessageReturned"
                    : "emptyLocalizedMessageReturned",
                diagnostics: [
                  "method=chrome.i18n.getMessage",
                  "messageKeyCount=1",
                  "messageKeyShape=" + keyShape,
                  "substitutionShape=" + substitutionsResult.shape,
                  "selectedLocale=" + (lookup.locale || "none"),
                  "fallbackLocaleUsed=" + String(fallbackLocaleUsed),
                  "resultClassifier=" + (
                    result.length > 0
                      ? "localizedMessageReturned"
                      : "emptyLocalizedMessageReturned"
                  ),
                  "No raw localized message values are recorded."
                ]
              });
              return result;
            },
            enumerable: true
          });

          ["contains", "request", "remove"].forEach((methodName) => {
            Object.defineProperty(permissions, methodName, {
              value(permissionsObject, callback) {
                const cb = typeof callback === "function" ? callback : null;
                return callbackOrPromise(
                  "permissions",
                  methodName,
                  [permissionsObject || {}],
                  cb
                );
              },
              enumerable: true
            });
          });
          Object.defineProperty(permissions, "getAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "getAll", [], cb);
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
          \(tabsGetCurrentSource)
          Object.defineProperty(tabs, "sendMessage", {
            value(tabId, message, options, callback) {
              let cb = null;
              let opts = options;
              if (typeof options === "function") {
                cb = options;
                opts = undefined;
              } else if (typeof callback === "function") {
                cb = callback;
              }
              const args = opts === undefined
                ? [tabId, message]
                : [tabId, message, opts];
              return callbackOrPromise("tabs", "sendMessage", args, cb);
            },
            enumerable: true
          });
          Object.defineProperty(tabs, "connect", {
            value(tabId, connectInfo) {
              const port = createPort(connectInfo && connectInfo.name, {
                namespace: "tabs",
                postMessage: "port.postMessage",
                disconnect: "port.disconnect"
              });
              const state = portState.get(port);
              bridgePost("tabs", "connect", "fireAndForget", [tabId, connectInfo || {}])
                .then((response) => {
                  if (!response.succeeded) {
                    state.markDisconnected();
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  state.sender = payload.sender || null;
                  state.flushPendingMessages();
                })
                .catch(state.markDisconnected);
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(scripting, "executeScript", {
            value(details, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("scripting", "executeScript", [details || {}], cb);
            },
            enumerable: true
          });

          function blockedNamespace(namespace) {
            return new Proxy({}, {
              get(target, prop) {
                if (typeof prop !== "string") {
                  return undefined;
                }
                if (!Object.prototype.hasOwnProperty.call(target, prop)) {
                  Object.defineProperty(target, prop, {
                    value() {
                      const args = Array.prototype.slice.call(arguments);
                      const callback = typeof args[args.length - 1] === "function"
                        ? args.pop()
                        : null;
                      return callbackOrPromise(namespace, prop, args, callback);
                    },
                    enumerable: true
                  });
                }
                return target[prop];
              }
            });
          }

          function controlledExtensionNamespace(rootName) {
            const namespace = {};
            Object.defineProperty(namespace, "getBackgroundPage", {
              value() {
                debugExtensionGetBackgroundPage(
                  rootName,
                  "null",
                  Array.prototype.slice.call(arguments)
                );
                return null;
              },
              enumerable: true
            });
            return Object.freeze(namespace);
          }

          const tabsObject = namespaceObject("tabs", tabs);

          Object.defineProperty(chromeObject, "runtime", {
            value: runtimeObject,
            enumerable: true
          });
          Object.defineProperty(chromeObject, "storage", {
            value: storageObject,
            enumerable: true
          });
          if (config.i18nExposed) {
            Object.defineProperty(chromeObject, "i18n", {
              value: Object.freeze(i18n),
              enumerable: true
            });
          }
          Object.defineProperty(chromeObject, "permissions", {
            value: Object.freeze(permissions),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "tabs", {
            value: tabsObject,
            enumerable: true
          });
          Object.defineProperty(chromeObject, "scripting", {
            value: Object.freeze(scripting),
            enumerable: true
          });
          ["nativeMessaging", "declarativeNetRequest", "webRequest", "sidePanel", "offscreen", "identity"].forEach((namespace) => {
            Object.defineProperty(chromeObject, namespace, {
              value: blockedNamespace(namespace),
              enumerable: true
            });
          });
          function rootTarget(rootName) {
            const target = {};
            Object.getOwnPropertyNames(chromeObject).forEach((key) => {
              Object.defineProperty(
                target,
                key,
                Object.getOwnPropertyDescriptor(chromeObject, key)
              );
            });
            if (config.controlledExtensionGetBackgroundPageCompatibilitySurface) {
              const extensionSurface = controlledExtensionNamespace(rootName);
              Object.defineProperty(target, "extension", {
                get() {
                  debugExtensionNamespaceAccess(rootName);
                  return extensionSurface;
                },
                enumerable: true
              });
            }
            return Object.freeze(target);
          }
          function rootObject(rootName) {
            const target = rootTarget(rootName);
            return new Proxy(target, {
              get(target, prop, receiver) {
                if (typeof prop === "string" && !Reflect.has(target, prop)) {
                  debugMissingAPI(
                    rootName + "." + prop,
                    "missing Chrome API namespace",
                    "unknown"
                  );
                  return undefined;
                }
                return Reflect.get(target, prop, receiver);
              }
            });
          }
          const chromeRoot = rootObject("chrome");
          const browserRoot = rootObject("browser");

          Object.defineProperty(globalThis, "chrome", {
            value: chromeRoot,
            configurable: true
          });
          Object.defineProperty(globalThis, "browser", {
            value: browserRoot,
            configurable: true
          });

          installControlledNavigatorCompatibilitySurface();
        })();
        """
    }

    private static func debugSupportNoopSource() -> String {
        """
          function debugBridgeStart(namespace, methodName, invocationMode, args, bridgeCallID) {}
          function debugBridgeResolved(response) {}
          function debugBridgeRejected(namespace, methodName, bridgeCallID, error) {}
          function debugCallbackLastError(namespace, methodName, message) {}
          function debugPromiseRejected(namespace, methodName, message) {}
          function debugMissingAPI(apiName, resultClassifier, targetContext) {}
          function debugRuntimeOnMessageEvent(resultClassifier, listenerCount, diagnostics) {}
          function debugStorageEvent(eventKind, record) {}
          function debugStorageChangeValueShape(changes) { return "none"; }
          function debugPortEvent(eventKind, record) {}
          function debugRuntimeGetManifest(manifest, succeeded) {}
          function debugI18nCall(methodName, record) {}
          function debugExtensionNamespaceAccess(rootName) {}
          function debugExtensionGetBackgroundPage(rootName, resultClassifier, args) {}
          function debugPlatformEnvironmentProbe(phase, extras) {}
          function debugPostGetManifestBootstrapSentinel(succeeded) {}

          function installControlledNavigatorCompatibilitySurface() {}
        """
    }

    #if DEBUG
    private static func debugSupportSource() -> String {
        """
          const __sumiDebugEvents = [];
          const __sumiPendingBridgeCalls = new Map();
          const __sumiDebugStartedAt = Date.now();
          const __sumiPendingTimeoutMS = 900;
          const __sumiPostBootstrapCheckpointMS = [250, 900, 1800, 3500];
          const __sumiPostBootstrapState = {
            manifestReturnedAt: null,
            scheduled: false
          };
          const __sumiSafeFieldNames = new Set([
            "action", "command", "kind", "messageType", "method", "name",
            "operation", "requestType", "type"
          ]);
          const __sumiSensitiveFragments = [
            "auth", "cookie", "credential", "password", "secret",
            "sessionid", "token", "vault"
          ];

          function debugNowMS() {
            return Math.max(0, Date.now() - __sumiDebugStartedAt);
          }

          function debugIsSensitiveName(name) {
            const lower = String(name || "").toLowerCase();
            return __sumiSensitiveFragments.some((fragment) => lower.includes(fragment));
          }

          function debugSafeString(value, maxLength) {
            if (typeof value !== "string") {
              return null;
            }
            const trimmed = value.trim();
            if (!trimmed || trimmed.length > (maxLength || 120)) {
              return null;
            }
            if (debugIsSensitiveName(trimmed)) {
              return null;
            }
            if (/[\\u0000-\\u001f\\u007f]/.test(trimmed)) {
              return null;
            }
            return trimmed;
          }

          function debugSafePortName(value) {
            const name = debugSafeString(value, 80);
            if (!name || !/^[A-Za-z][A-Za-z0-9_.:-]{0,79}$/.test(name)) {
              return null;
            }
            return name;
          }

          function debugSafeFieldsInValue(value, depth) {
            if (depth > 3 || !value || typeof value !== "object") {
              return [];
            }
            if (Array.isArray(value)) {
              return Array.from(new Set(value.flatMap((item) => debugSafeFieldsInValue(item, depth + 1)))).sort();
            }
            return Object.keys(value)
              .filter((key) => __sumiSafeFieldNames.has(key))
              .filter((key) => !debugIsSensitiveName(key))
              .sort();
          }

          function debugValueShape(value, depth) {
            if (value === null) {
              return "null";
            }
            if (value === undefined) {
              return "undefined";
            }
            if (Array.isArray(value)) {
              return "array:length=" + value.length;
            }
            const type = typeof value;
            if (type === "object") {
              const fields = debugSafeFieldsInValue(value, depth || 0);
              return "object:keyCount=" + Object.keys(value).length
                + (fields.length ? ";safeFields=" + fields.join(",") : "");
            }
            if (type === "string") {
              return "string:length=" + value.length;
            }
            if (type === "number") {
              return "number";
            }
            if (type === "boolean") {
              return "boolean";
            }
            if (type === "function") {
              return "function";
            }
            return "value:" + type;
          }

          function debugStorageChangeValueShape(changes) {
            if (!changes || typeof changes !== "object" || Array.isArray(changes)) {
              return "none";
            }
            const shapes = [];
            Object.keys(changes).forEach((key) => {
              const change = changes[key];
              if (!change || typeof change !== "object") {
                shapes.push("change:nonObject");
                return;
              }
              if (Object.prototype.hasOwnProperty.call(change, "oldValue")) {
                shapes.push("oldValue=" + debugValueShape(change.oldValue, 0));
              } else {
                shapes.push("oldValue=absent");
              }
              if (Object.prototype.hasOwnProperty.call(change, "newValue")) {
                shapes.push("newValue=" + debugValueShape(change.newValue, 0));
              } else {
                shapes.push("newValue=absent");
              }
            });
            return shapes.sort().slice(0, 12).join(",");
          }

          function debugArgsShape(args) {
            const list = Array.isArray(args) ? args : [];
            if (list.length === 0) {
              return "arguments:0";
            }
            return list.map((value, index) => {
              return "arg" + index + "=" + debugValueShape(value, 0);
            }).join(";");
          }

          function debugTargetContext(namespace, methodName) {
            if (namespace === "i18n") {
              return "i18n";
            }
            if (namespace === "extension") {
              return "backgroundPage";
            }
            if (namespace === "storage") {
              if (methodName.indexOf("local.") === 0) {
                return "storage.local";
              }
              if (methodName.indexOf("session.") === 0) {
                return "storage.session";
              }
              if (methodName.indexOf("sync.") === 0) {
                return "storage.sync";
              }
              if (methodName.indexOf("managed.") === 0) {
                return "storage.managed";
              }
            }
            if (namespace === "runtime" && methodName === "sendMessage") {
              return "serviceWorker";
            }
            if (namespace === "runtime" && methodName === "connect") {
              return "serviceWorker";
            }
            if (namespace === "runtime" && methodName === "getManifest") {
              return "manifest";
            }
            if (namespace === "runtime" && methodName.indexOf("port.") === 0) {
              return "serviceWorker";
            }
            if (namespace === "tabs" && methodName === "query") {
              return "tabs";
            }
            if (namespace === "tabs" && methodName === "getCurrent") {
              return "tabs";
            }
            if (namespace === "tabs") {
              return "contentScript";
            }
            if (methodName === "sendNativeMessage") {
              return "nativeApplication";
            }
            if (methodName === "connectNative" || methodName === "nativePort.postMessage" || methodName === "nativePort.disconnect") {
              return "nativeApplicationPort";
            }
            return "unknown";
          }

          function debugPortName(namespace, methodName, args) {
            if (namespace === "runtime" && methodName === "connect") {
              if (args[0] && typeof args[0] === "object") {
                return debugSafePortName(args[0].name);
              }
              if (args[1] && typeof args[1] === "object") {
                return debugSafePortName(args[1].name);
              }
            }
            if (namespace === "tabs" && methodName === "connect") {
              return debugSafePortName(args[1] && args[1].name);
            }
            return null;
          }

          function debugAPIName(namespace, methodName) {
            return namespace + "." + methodName;
          }

          function debugClassifier(namespace, methodName, response) {
            if (namespace === "storage" && methodName.indexOf("local.") === 0) {
              return response && response.succeeded
                ? "storageLocalBrokerSucceeded"
                : "pending unresolved storage call";
            }
            if (namespace === "storage" && methodName.indexOf("session.") === 0) {
              return response && response.succeeded
                ? "storageSessionBrokerSucceeded"
                : "pending unresolved storage call";
            }
            if (namespace === "storage" && methodName.indexOf("sync.") === 0) {
              return response && response.succeeded
                ? "storageSyncLocalCompatibilitySucceeded"
                : "pending unresolved storage call";
            }
            if (namespace === "storage" && methodName.indexOf("managed.") === 0) {
              return "missing storage.managed";
            }
            if (namespace === "tabs" && methodName === "connect") {
              return response && response.succeeded
                ? "listenerRespondedSync"
                : "missing tabs.connect";
            }
            if (namespace === "tabs" && methodName === "getCurrent") {
              if (response && response.succeeded) {
                return response.resultPayload === null || response.resultPayload === undefined
                  ? "undefined"
                  : "tab";
              }
              return response && response.lastErrorCode
                ? response.lastErrorCode
                : "tabs.getCurrent error";
            }
            if (namespace === "extension" && methodName === "getBackgroundPage") {
              if (response && response.succeeded) {
                return response.resultPayload === null ? "null" : "returned";
              }
              return "unsupported";
            }
            if (namespace === "runtime" && methodName === "connect") {
              if (response && response.succeeded && response.resultPayload && response.resultPayload.canWakeServiceWorkerNow === false) {
                return "service worker not waking";
              }
              return response && response.succeeded ? "listenerRespondedSync" : "service worker not waking";
            }
            if (namespace === "runtime" && methodName === "getManifest") {
              return response && response.succeeded ? "manifestReturned" : "manifestUnavailable";
            }
            if (namespace === "runtime" && methodName === "port.postMessage") {
              return response && response.succeeded ? "Port response delivered" : "Port message not delivered";
            }
            if (response && response.succeeded) {
              return "listenerRespondedSync";
            }
            if (response && response.lastErrorCode === "noReceivingEnd") {
              return "service worker listener missing";
            }
            if (response && response.lastErrorCode) {
              return response.lastErrorCode;
            }
            return "unknown pending promise";
          }

          function debugSafeInteger(value) {
            if (typeof value !== "number" || !Number.isFinite(value)) {
              return null;
            }
            const rounded = Math.round(value);
            if (rounded < 0 || rounded > 1000000) {
              return null;
            }
            return String(rounded);
          }

          function debugSafeResourceDescriptor(value) {
            if (typeof value !== "string") {
              return null;
            }
            const beforeQuery = value.split("#", 1)[0].split("?", 1)[0];
            if (debugIsSensitiveName(beforeQuery)) {
              return null;
            }
            const pieces = beforeQuery.split("/").filter(Boolean);
            if (pieces.length === 0) {
              return null;
            }
            const tail = pieces.slice(Math.max(0, pieces.length - 2)).join("/");
            return debugSafeString(tail, 140);
          }

          function debugSanitizedText(value, maxLength) {
            if (value === null || value === undefined) {
              return null;
            }
            const string = String(value);
            if (debugIsSensitiveName(string)) {
              return null;
            }
            const redactedURLs = string.replace(
              /(?:file|https?|chrome-extension|sumi-extension-page-diagnostic):\\/\\/[^\\s"'<>)]*/g,
              (match) => {
                const descriptor = debugSafeResourceDescriptor(match);
                return descriptor ? "resource:" + descriptor : "resource:redacted";
              }
            );
            return debugSafeString(redactedURLs, maxLength || 180);
          }

          function debugSanitizedMessage(message) {
            return debugSanitizedText(message, 180);
          }

          function debugSafeFunctionName(value) {
            const name = debugSafeString(value, 100);
            if (!name || !/^[A-Za-z0-9_$.[\\]<>: -]+$/.test(name)) {
              return null;
            }
            return name;
          }

          function debugStackFrameDiagnostics(line, frameIndex) {
            const raw = typeof line === "string" ? line.trim() : "";
            if (!raw || debugIsSensitiveName(raw)) {
              return null;
            }
            let functionName = null;
            let resource = null;
            let lineNumber = null;
            let columnNumber = null;

            const urlMatch = raw.match(/((?:file|https?|chrome-extension|sumi-extension-page-diagnostic):\\/\\/[^\\s)]+):(\\d+):(\\d+)/);
            if (urlMatch) {
              resource = debugSafeResourceDescriptor(urlMatch[1]);
              lineNumber = debugSafeInteger(Number(urlMatch[2]));
              columnNumber = debugSafeInteger(Number(urlMatch[3]));
              const prefix = raw.slice(0, urlMatch.index).replace(/^at\\s+/, "").replace(/[(@\\s]+$/, "");
              functionName = debugSafeFunctionName(prefix);
            } else {
              const compactMatch = raw.match(/^([^@]+)@([^\\s)]+):(\\d+):(\\d+)/);
              if (compactMatch) {
                functionName = debugSafeFunctionName(compactMatch[1]);
                resource = debugSafeResourceDescriptor(compactMatch[2]);
                lineNumber = debugSafeInteger(Number(compactMatch[3]));
                columnNumber = debugSafeInteger(Number(compactMatch[4]));
              }
            }

            const parts = [];
            if (functionName) {
              parts.push("function=" + functionName);
            }
            if (resource) {
              parts.push("resource=" + resource);
            }
            if (lineNumber) {
              parts.push("line=" + lineNumber);
            }
            if (columnNumber) {
              parts.push("column=" + columnNumber);
            }
            if (parts.length === 0) {
              return null;
            }
            return "stackFrame" + frameIndex + "=" + parts.join(";");
          }

          function debugConsoleErrorDiagnostics(args) {
            const diagnostics = [];
            const list = Array.isArray(args) ? args : [];
            list.slice(0, 4).forEach((value, index) => {
              if (!value || typeof value !== "object") {
                return;
              }
              const errorName = debugSafeString(value.name, 80);
              const message = debugSanitizedMessage(value.message);
              if (errorName) {
                diagnostics.push("arg" + index + ".errorName=" + errorName);
              }
              if (message) {
                diagnostics.push("arg" + index + ".message=" + message);
              }
              const stack = typeof value.stack === "string" ? value.stack : "";
              if (!stack || debugIsSensitiveName(stack)) {
                return;
              }
              stack.split("\\n")
                .slice(1, 7)
                .map((line, frameIndex) => debugStackFrameDiagnostics(line, frameIndex))
                .filter(Boolean)
                .forEach((line) => diagnostics.push("arg" + index + "." + line));
            });
            return diagnostics;
          }

          function debugSafeElementAttribute(target, name, maxLength) {
            try {
              if (!target || typeof target.getAttribute !== "function") {
                return null;
              }
              return debugSafeString(target.getAttribute(name) || "", maxLength || 80);
            } catch (_) {
              return null;
            }
          }

          function debugResourceDiagnostics(target) {
            const tag = debugSafeString(String(target && target.tagName || "").toLowerCase(), 40) || "unknown";
            const resource = debugSafeResourceDescriptor(
              target && (target.currentSrc || target.src || target.href || "")
            );
            const type = debugSafeElementAttribute(target, "type", 80)
              || (tag === "script" ? "classic" : null);
            const rel = debugSafeElementAttribute(target, "rel", 80);
            const asValue = debugSafeElementAttribute(target, "as", 80);
            const diagnostics = [
              "tag=" + tag,
              resource ? "resource=" + resource : "resource=unknown"
            ];
            if (type) {
              diagnostics.push("type=" + type);
            }
            if (rel) {
              diagnostics.push("rel=" + rel);
            }
            if (asValue) {
              diagnostics.push("as=" + asValue);
            }
            return { tag, resource, type, rel, asValue, diagnostics };
          }

          const __sumiResourceEventCounters = {
            load: 0,
            error: 0,
            timing: 0
          };

          function debugRecordResourceEvent(eventKind, target, resultClassifier) {
            const key = eventKind === "resourceLoaded" ? "load" : "error";
            if (__sumiResourceEventCounters[key] >= 80) {
              return;
            }
            __sumiResourceEventCounters[key] += 1;
            const details = debugResourceDiagnostics(target);
            debugRecord(eventKind, {
              apiName: "resource." + details.tag,
              targetContext: "resource",
              resultClassifier,
              firstMissingAPIOrPermissionOrLifecycleError:
                eventKind === "resourceLoadError"
                  ? (details.resource
                    ? "resource load error: " + details.resource
                    : "resource load error")
                  : null,
              safeMessageShapeClassification: "resourceTag=" + details.tag,
              diagnostics:
                [
                  eventKind === "resourceLoadError"
                    ? "Popup resource emitted an error event."
                    : "Popup resource emitted a load event."
                ]
                .concat(details.diagnostics)
            });
          }

          function debugRecordResourceTiming(reason) {
            if (__sumiResourceEventCounters.timing >= 6) {
              return;
            }
            __sumiResourceEventCounters.timing += 1;
            let entries = [];
            try {
              entries = globalThis.performance
                && typeof globalThis.performance.getEntriesByType === "function"
                ? globalThis.performance.getEntriesByType("resource")
                : [];
            } catch (_) {
              entries = [];
            }
            const diagnostics = ["reason=" + reason];
            entries.slice(Math.max(0, entries.length - 60)).forEach((entry) => {
              const descriptor = debugSafeResourceDescriptor(entry && entry.name);
              const initiator = debugSafeString(entry && entry.initiatorType, 40) || "unknown";
              const duration = debugSafeInteger(entry && entry.duration);
              const transferSize = debugSafeInteger(entry && entry.transferSize);
              const responseStatus = debugSafeInteger(entry && entry.responseStatus);
              if (!descriptor) {
                return;
              }
              let line = "resource=" + descriptor + ";initiator=" + initiator;
              if (duration) {
                line += ";durationMs=" + duration;
              }
              if (transferSize) {
                line += ";transferSize=" + transferSize;
              }
              if (responseStatus) {
                line += ";status=" + responseStatus;
              }
              diagnostics.push(line);
            });
            debugRecord("resourceTimingSnapshot", {
              apiName: "performance.resourceTiming",
              targetContext: "resource",
              resultClassifier: "resource timing snapshot",
              safeMessageShapeClassification: "resourceTimingCount=" + String(entries.length),
              diagnostics
            });
          }

          function debugInstallConsoleCapture(level) {
            try {
              const consoleObject = globalThis.console;
              if (!consoleObject || typeof consoleObject[level] !== "function") {
                return;
              }
              const original = consoleObject[level];
              Object.defineProperty(consoleObject, level, {
                value() {
                  const args = Array.prototype.slice.call(arguments);
                  const firstMessage = debugSanitizedText(args[0], 180);
                  debugRecord(level === "error" ? "consoleError" : "consoleWarn", {
                    apiName: "console." + level,
                    targetContext: "console",
                    resultClassifier:
                      level === "error" ? "console error" : "console warning",
                    firstMissingAPIOrPermissionOrLifecycleError:
                      level === "error" ? firstMessage : null,
                    safeMessageShapeClassification: debugArgsShape(args),
                    safeCommandTypeActionFieldNames:
                      Array.from(new Set(args.flatMap((value) => debugSafeFieldsInValue(value, 0)))).sort(),
                    diagnostics:
                      firstMessage
                        ? ["console." + level + "=" + firstMessage]
                            .concat(debugConsoleErrorDiagnostics(args))
                        : ["console." + level + " called; raw arguments omitted."]
                            .concat(debugConsoleErrorDiagnostics(args))
                  });
                  return original.apply(this, args);
                },
                configurable: true
              });
            } catch (_) {
            }
          }

          function debugPost(record) {
            try {
              const handler = globalThis.webkit
                && globalThis.webkit.messageHandlers
                && globalThis.webkit.messageHandlers[bridgeName];
              if (!handler || typeof handler.postMessage !== "function") {
                return;
              }
              handler.postMessage(Object.assign({
                namespace: "__sumiDebug",
                methodName: "event",
                invocationMode: "fireAndForget",
                extensionID: config.extensionID,
                profileID: config.profileID,
                sourceContext: config.sourceContext,
                surfaceID: config.surfaceID,
                bridgeCallID: "popup-options-js-debug-" + String(debugNowMS())
              }, record));
            } catch (_) {
            }
          }

          function debugRecord(eventKind, record) {
            const sanitized = Object.assign({
              eventKind,
              sourceContext: config.sourceContext,
              safeMessageShapeClassification: "shape=unknown",
              safeCommandTypeActionFieldNames: [],
              diagnostics: []
            }, record || {});
            __sumiDebugEvents.push(Object.assign({ atMs: debugNowMS() }, sanitized));
            if (__sumiDebugEvents.length > 800) {
              __sumiDebugEvents.splice(0, __sumiDebugEvents.length - 800);
            }
            debugPost(sanitized);
          }

          function debugBridgeStart(namespace, methodName, invocationMode, args, bridgeCallID) {
            const apiName = debugAPIName(namespace, methodName);
            const pending = {
              apiName,
              bridgeCallID,
              invocationMode,
              sourceContext: config.sourceContext,
              targetContext: debugTargetContext(namespace, methodName),
              safeMessageShapeClassification: debugArgsShape(args),
              safeCommandTypeActionFieldNames: Array.from(new Set((args || []).flatMap((value) => debugSafeFieldsInValue(value, 0)))).sort(),
              portName: debugPortName(namespace, methodName, args),
              startedAt: debugNowMS()
            };
            __sumiPendingBridgeCalls.set(bridgeCallID, pending);
            debugRecord("bridgeCallStarted", Object.assign({}, pending, {
              resultClassifier: "pending"
            }));
            globalThis.setTimeout(() => {
              const current = __sumiPendingBridgeCalls.get(bridgeCallID);
              if (!current) {
                return;
              }
              const age = debugNowMS() - current.startedAt;
              debugRecord("pendingTimeout", Object.assign({}, current, {
                ageMilliseconds: Math.round(age),
                resultClassifier: debugClassifier(namespace, methodName, null),
                firstMissingAPIOrPermissionOrLifecycleError: debugClassifier(namespace, methodName, null),
                diagnostics: [
                  "Bridge call remained unresolved past the DEBUG pending-route timeout."
                ]
              }));
            }, __sumiPendingTimeoutMS);
          }

          function debugBridgeResolved(response) {
            if (!response || !response.bridgeCallID) {
              return;
            }
            const pending = __sumiPendingBridgeCalls.get(response.bridgeCallID);
            if (!pending) {
              return;
            }
            __sumiPendingBridgeCalls.delete(response.bridgeCallID);
            const parts = pending.apiName.split(".");
            const namespace = parts.shift() || "unknown";
            const methodName = parts.join(".");
            debugRecord("bridgeCallResolved", Object.assign({}, pending, {
              ageMilliseconds: Math.round(debugNowMS() - pending.startedAt),
              resultClassifier: debugClassifier(namespace, methodName, response),
              firstMissingAPIOrPermissionOrLifecycleError:
                response.succeeded ? null : debugSanitizedMessage(response.lastErrorMessage),
              diagnostics: [
                response.succeeded
                  ? "Bridge call resolved successfully."
                  : "Bridge call resolved with lastError."
              ]
            }));
          }

          function debugBridgeRejected(namespace, methodName, bridgeCallID, error) {
            const pending = __sumiPendingBridgeCalls.get(bridgeCallID);
            if (pending) {
              __sumiPendingBridgeCalls.delete(bridgeCallID);
            }
            debugRecord("bridgeCallRejected", Object.assign({}, pending || {
              apiName: debugAPIName(namespace, methodName),
              bridgeCallID,
              targetContext: debugTargetContext(namespace, methodName),
              safeMessageShapeClassification: "arguments:unknown"
            }, {
              ageMilliseconds: pending ? Math.round(debugNowMS() - pending.startedAt) : null,
              resultClassifier: "unknown pending promise",
              firstMissingAPIOrPermissionOrLifecycleError:
                debugSanitizedMessage(error && (error.message || String(error))),
              diagnostics: ["Bridge postMessage Promise rejected before a host response."]
            }));
          }

          function debugCallbackLastError(namespace, methodName, message) {
            debugRecord("callbackLastError", {
              apiName: debugAPIName(namespace, methodName),
              targetContext: debugTargetContext(namespace, methodName),
              resultClassifier: message ? "callback runtime.lastError" : "callback succeeded",
              firstMissingAPIOrPermissionOrLifecycleError:
                debugSanitizedMessage(message),
              diagnostics: [
                message
                  ? "Callback observed runtime.lastError."
                  : "Callback completed without runtime.lastError."
              ]
            });
          }

          function debugPromiseRejected(namespace, methodName, message) {
            debugRecord("promiseRejected", {
              apiName: debugAPIName(namespace, methodName),
              targetContext: debugTargetContext(namespace, methodName),
              resultClassifier: "Promise rejection",
              firstMissingAPIOrPermissionOrLifecycleError:
                debugSanitizedMessage(message),
              diagnostics: ["Promise rejected from popup/options bridge response."]
            });
          }

          function debugMissingAPI(apiName, resultClassifier, targetContext) {
            debugRecord("missingAPIAccess", {
              apiName,
              targetContext: targetContext || "unknown",
              resultClassifier: resultClassifier || "missing Chrome API namespace",
              firstMissingAPIOrPermissionOrLifecycleError:
                resultClassifier || "missing Chrome API namespace",
              safeMessageShapeClassification: "arguments:0",
              diagnostics: [
                "Missing or unsupported chrome.* namespace/property was accessed by the popup."
              ]
            });
          }

          function debugRuntimeOnMessageEvent(resultClassifier, listenerCount, diagnostics) {
            debugRecord("extensionMethodCalled", {
              apiName: "chrome.runtime.onMessage",
              targetContext: "extensionPage",
              resultClassifier: resultClassifier || "runtime.onMessage event observed",
              firstMissingAPIOrPermissionOrLifecycleError: null,
              safeMessageShapeClassification: "runtimeOnMessageEvent",
              safeCommandTypeActionFieldNames: [],
              diagnostics: Array.isArray(diagnostics)
                ? diagnostics
                : [
                    "eventObjectPresent=true",
                    "listenerCount=" + String(listenerCount || 0),
                    "listenerRegistryScope=pageSession;profile;extension",
                    "sourceContext=" + config.sourceContext,
                    "targetContext=extensionPage",
                    "senderMetadataShape=none",
                    "responseClassifier=registrationOnly",
                    "inboundRoute=notWired",
                    "No raw message bodies, storage values, form values, URLs, or private payloads are recorded."
                  ]
            });
          }

          function debugExtensionNamespaceAccess(rootName) {
            debugRecord("extensionNamespaceAccessed", {
              apiName: rootName + ".extension",
              targetContext: "backgroundPage",
              resultClassifier: "namespace returned",
              firstMissingAPIOrPermissionOrLifecycleError: null,
              safeMessageShapeClassification: "arguments:0",
              diagnostics: [
                "Controlled action popup read " + rootName + ".extension.",
                "Only extension.getBackgroundPage is exposed on this DEBUG/local-experimental namespace.",
                "No broad legacy chrome.extension APIs are exposed."
              ]
            });
          }

          function debugExtensionGetBackgroundPage(rootName, resultClassifier, args) {
            const classifier = resultClassifier || "null";
            debugRecord("extensionMethodCalled", {
              apiName: rootName + ".extension.getBackgroundPage",
              targetContext: "backgroundPage",
              resultClassifier: classifier,
              firstMissingAPIOrPermissionOrLifecycleError: null,
              safeMessageShapeClassification: debugArgsShape(args || []),
              safeCommandTypeActionFieldNames: [],
              diagnostics: [
                "method=extension.getBackgroundPage namespace=" + rootName
                  + " result=" + classifier
                  + " redaction=notApplicable sourceContext=" + config.sourceContext,
                "Chrome MV3 has no background page window when the extension uses a service worker; returning null.",
                "No fake background page/window or service-worker internals were returned."
              ]
            });
          }

          function debugUserAgentLengthBucket(value) {
            const length = String(value || "").length;
            if (length === 0) {
              return "0";
            }
            if (length < 40) {
              return "1-39";
            }
            if (length < 80) {
              return "40-79";
            }
            if (length < 120) {
              return "80-119";
            }
            if (length < 180) {
              return "120-179";
            }
            return "180+";
          }

          function debugUserAgentTokenDiagnostics(value) {
            const userAgent = String(value || "");
            return [
              "uaLengthBucket=" + debugUserAgentLengthBucket(userAgent),
              "uaHasMozilla=" + String(userAgent.indexOf("Mozilla/") !== -1),
              "uaHasAppleWebKit=" + String(userAgent.indexOf("AppleWebKit/") !== -1),
              "uaHasChromeSignal=" + String(userAgent.indexOf(" Chrome/") !== -1),
              "uaHasEdgeSignal=" + String(userAgent.indexOf(" Edg/") !== -1),
              "uaHasOperaSignal=" + String(userAgent.indexOf(" OPR/") !== -1),
              "uaHasVivaldiSignal=" + String(userAgent.indexOf(" Vivaldi/") !== -1),
              "uaHasFirefoxSignal=" + String(userAgent.indexOf(" Firefox/") !== -1),
              "uaHasGeckoSignal=" + String(userAgent.indexOf(" Gecko/") !== -1),
              "uaHasSafariSignal=" + String(userAgent.indexOf(" Safari/") !== -1)
            ];
          }

          function debugPlatformShape(value) {
            const platform = String(value || "");
            if (!platform) {
              return "empty";
            }
            if (/^Mac/i.test(platform)) {
              return "mac";
            }
            if (/^Win/i.test(platform)) {
              return "win";
            }
            if (/Linux/i.test(platform)) {
              return "linux";
            }
            if (/iPhone|iPad|iPod/i.test(platform)) {
              return "ios";
            }
            return "other";
          }

          function debugLanguageShape(value) {
            const language = String(value || "");
            if (!language) {
              return "empty";
            }
            return /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(language)
              ? "bcp47-like"
              : "other";
          }

          function debugBrandClass(value) {
            const brand = String(value || "").toLowerCase();
            if (brand.indexOf("chromium") !== -1) {
              return "chromium";
            }
            if (brand.indexOf("chrome") !== -1) {
              return "chrome";
            }
            if (brand.indexOf("edge") !== -1) {
              return "edge";
            }
            if (brand.indexOf("opera") !== -1) {
              return "opera";
            }
            if (brand.indexOf("firefox") !== -1) {
              return "firefox";
            }
            if (brand.indexOf("safari") !== -1) {
              return "safari";
            }
            if (brand.indexOf("not") !== -1) {
              return "notabrand";
            }
            return "other";
          }

          function debugUserAgentDataDiagnostics(value) {
            if (!value || typeof value !== "object") {
              return ["userAgentData=absent"];
            }
            const brands = Array.isArray(value.brands) ? value.brands : [];
            const brandClasses = Array.from(new Set(brands.map((entry) => {
              return debugBrandClass(entry && entry.brand);
            }))).sort();
            return [
              "userAgentData=present",
              "userAgentDataBrandsCount=" + String(brands.length),
              "userAgentDataBrandClasses=" + (brandClasses.join(",") || "none"),
              "userAgentDataMobileType=" + typeof value.mobile,
              "userAgentDataPlatformShape=" + debugPlatformShape(value.platform)
            ];
          }

          function debugSafeNamespaceKeys(value) {
            if (!value || typeof value !== "object") {
              return "none";
            }
            try {
              const keys = Object.keys(value)
                .filter((key) => /^[A-Za-z][A-Za-z0-9_.:-]{0,48}$/.test(key))
                .filter((key) => !debugIsSensitiveName(key))
                .sort();
              return keys.slice(0, 24).join(",") || "none";
            } catch (_) {
              return "unavailable";
            }
          }

          function debugPlatformEnvironmentProbe(phase, extras) {
            const nav = globalThis.navigator || {};
            const chromeRuntime = globalThis.chrome && globalThis.chrome.runtime;
            const browserRuntime = globalThis.browser && globalThis.browser.runtime;
            const userAgent = String(nav.userAgent || "");
            const diagnostics = [
              "phase=" + phase,
              "sourceContext=" + config.sourceContext,
              "compatGate=" + String(!!config.controlledNavigatorCompatibilitySurface),
              "platformShape=" + debugPlatformShape(nav.platform),
              "languageShape=" + debugLanguageShape(nav.language),
              "languagesCount=" + String(Array.isArray(nav.languages) ? nav.languages.length : 0),
              "chromeTopLevelKeys=" + debugSafeNamespaceKeys(globalThis.chrome),
              "browserTopLevelKeys=" + debugSafeNamespaceKeys(globalThis.browser),
              "chromeRuntimePresent=" + String(!!chromeRuntime),
              "browserRuntimePresent=" + String(!!browserRuntime),
              "browserRuntimeSharesChromeRuntime=" + String(!!chromeRuntime && chromeRuntime === browserRuntime),
              "chromeRuntimeGetPlatformInfo=" + String(
                !!chromeRuntime && typeof chromeRuntime.getPlatformInfo === "function"
              ),
              "chromeRuntimeGetBrowserInfo=" + String(
                !!chromeRuntime && typeof chromeRuntime.getBrowserInfo === "function"
              ),
              "browserRuntimeGetPlatformInfo=" + String(
                !!browserRuntime && typeof browserRuntime.getPlatformInfo === "function"
              ),
              "browserRuntimeGetBrowserInfo=" + String(
                !!browserRuntime && typeof browserRuntime.getBrowserInfo === "function"
              )
            ]
              .concat(debugUserAgentTokenDiagnostics(userAgent))
              .concat(debugUserAgentDataDiagnostics(nav.userAgentData))
              .concat(Array.isArray(extras) ? extras : []);
            debugRecord("environmentProbe", {
              apiName: "navigator.platformIdentity",
              targetContext: "platform",
              resultClassifier: "platform probe captured",
              safeMessageShapeClassification: [
                "navigator",
                "uaLengthBucket=" + debugUserAgentLengthBucket(userAgent),
                "platformShape=" + debugPlatformShape(nav.platform),
                "languageShape=" + debugLanguageShape(nav.language)
              ].join(";"),
              diagnostics
            });
          }

          function hasKnownBrowserFamilyUserAgentToken(value) {
            const userAgent = String(value || "");
            return userAgent.indexOf(" Chrome/") !== -1
              || userAgent.indexOf(" Edg/") !== -1
              || userAgent.indexOf(" OPR/") !== -1
              || userAgent.indexOf(" Vivaldi/") !== -1
              || userAgent.indexOf(" Firefox/") !== -1
              || userAgent.indexOf(" Gecko/") !== -1
              || userAgent.indexOf(" Safari/") !== -1;
          }

          function defineControlledNavigatorGetter(name, value) {
            const nav = globalThis.navigator;
            const targets = [
              { label: "navigator", value: nav },
              { label: "navigatorPrototype", value: nav && Object.getPrototypeOf(nav) }
            ];
            for (const target of targets) {
              try {
                if (!target.value) {
                  continue;
                }
                Object.defineProperty(target.value, name, {
                  get() {
                    return value;
                  },
                  configurable: true
                });
                if (String(nav && nav[name] || "") === value) {
                  return { applied: true, target: target.label };
                }
              } catch (_) {
              }
            }
            return { applied: false, target: "none" };
          }

          function installControlledNavigatorCompatibilitySurface() {
            if (!config.controlledNavigatorCompatibilitySurface) {
              return;
            }
            const nav = globalThis.navigator || {};
            const beforeUserAgent = String(nav.userAgent || "");
            const beforePlatform = String(nav.platform || "");
            const knownFamilyBefore =
              hasKnownBrowserFamilyUserAgentToken(beforeUserAgent);
            debugPlatformEnvironmentProbe("preNavigatorCompatibility", [
              "knownBrowserFamilyBefore=" + String(knownFamilyBefore),
              "platformOverrideCandidate=" + String(!/^Mac/i.test(beforePlatform || "")),
              "No raw user agent, language tags, storage data, message bodies, or form values are recorded."
            ]);

            const reducedMacChromeUserAgent =
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/0.0.0.0 Safari/537.36";
            const userAgentResult = knownFamilyBefore
              ? { applied: false, target: "alreadyCompatible" }
              : defineControlledNavigatorGetter("userAgent", reducedMacChromeUserAgent);
            const platformResult = /^Mac/i.test(beforePlatform || "")
              ? { applied: false, target: "alreadyCompatible" }
              : defineControlledNavigatorGetter("platform", "MacIntel");

            debugPlatformEnvironmentProbe("postNavigatorCompatibility", [
              "knownBrowserFamilyBefore=" + String(knownFamilyBefore),
              "knownBrowserFamilyAfter=" + String(
                hasKnownBrowserFamilyUserAgentToken(
                  globalThis.navigator && globalThis.navigator.userAgent
                )
              ),
              "compatOverrideApplied=" + String(
                userAgentResult.applied || platformResult.applied
              ),
              "userAgentOverrideApplied=" + String(userAgentResult.applied),
              "userAgentOverrideTarget=" + userAgentResult.target,
              "userAgentOverrideKind=reducedChromeMac",
              "platformOverrideApplied=" + String(platformResult.applied),
              "platformOverrideTarget=" + platformResult.target,
              "platformOverrideKind=macIntel",
              "compatReason=missingKnownBrowserFamilySignal"
            ]);
          }

          function debugSafeManifestFieldNames(manifest) {
            if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
              return [];
            }
            return Object.keys(manifest)
              .filter((key) => /^[A-Za-z0-9_.:-]{1,80}$/.test(key))
              .filter((key) => !debugIsSensitiveName(key))
              .sort();
          }

          function debugRuntimeGetManifest(manifest, succeeded) {
            const safeFields = debugSafeManifestFieldNames(manifest);
            const manifestVersion =
              manifest
              && typeof manifest.manifest_version === "number"
              && Number.isFinite(manifest.manifest_version)
                ? Math.round(manifest.manifest_version)
                : null;
            const keyCount =
              manifest && typeof manifest === "object" && !Array.isArray(manifest)
                ? Object.keys(manifest).length
                : 0;
            debugRecord("bridgeCallResolved", {
              apiName: "runtime.getManifest",
              targetContext: "manifest",
              resultClassifier:
                succeeded ? "manifestReturned" : "manifestUnavailable",
              safeMessageShapeClassification:
                succeeded
                  ? "object:keyCount=" + String(keyCount)
                  : "manifestUnavailable",
              diagnostics: [
                "method=runtime.getManifest",
                "topLevelManifestKeyCount=" + String(keyCount),
                "safeTopLevelManifestFields=" + safeFields.join(","),
                "manifestVersion=" + (
                  manifestVersion === null
                    ? "unknown"
                    : String(manifestVersion)
                ),
                "succeeded=" + (succeeded ? "true" : "false"),
                "runtime.getManifest JS diagnostics omit manifest body and host filesystem paths."
              ]
            });
          }

          function debugI18nCall(methodName, record) {
            const details = record || {};
            const diagnostics = Array.isArray(details.diagnostics)
              ? details.diagnostics
              : [
                "method=chrome.i18n." + methodName,
                "uiLanguage=" + String(details.uiLanguage || "unknown"),
                "defaultLocale=" + String(details.defaultLocale || "none"),
                "selectedLocale=" + String(details.selectedLocale || "none"),
                "fallbackLocaleUsed=" + String(!!details.fallbackLocaleUsed),
                "messageKeyShape=" + String(details.messageKeyShape || "none"),
                "substitutionShape=" + String(details.substitutionShape || "arguments:0"),
                "resultClassifier=" + String(details.resultClassifier || "unknown"),
                "No raw localized message values are recorded."
              ];
            debugRecord("bridgeCallResolved", {
              apiName: "chrome.i18n." + methodName,
              targetContext: "i18n",
              resultClassifier: details.resultClassifier || "i18nCallReturned",
              safeMessageShapeClassification: [
                "messageKeyShape=" + String(details.messageKeyShape || "none"),
                "substitutionShape=" + String(details.substitutionShape || "arguments:0")
              ].join(";"),
              diagnostics
            });
          }

          function debugCoarseDOMState() {
            const body = globalThis.document && globalThis.document.body;
            const text = body && typeof body.innerText === "string"
              ? body.innerText
              : "";
            const trimmedTextLength = text.trim().length;
            const queryCount = (selector) => {
              try {
                return globalThis.document.querySelectorAll(selector).length;
              } catch (_) {
                return 0;
              }
            };
            const inputCount = queryCount("input,textarea,select");
            const buttonCount = queryCount("button,[role='button'],input[type='button'],input[type='submit']");
            const linkCount = queryCount("a[href]");
            const formCount = queryCount("form");
            const appRootCount = queryCount("app-root,[data-app-root],main,#app,#root");
            const elementCount = body && typeof body.querySelectorAll === "function"
              ? body.querySelectorAll("*").length
              : 0;
            const hasBusyIndicator =
              queryCount("[role='progressbar'],[aria-busy='true'],.spinner,.loading,.loader,[data-loading='true']") > 0;
            const hasLoadingText = /\\b(loading|please wait|initializing|syncing)\\b/i.test(text);
            const controlCount = inputCount + buttonCount + linkCount;
            const blankCandidate =
              trimmedTextLength === 0
                && controlCount === 0
                && elementCount <= Math.max(1, appRootCount);
            const usableFormCandidate =
              (inputCount > 0 && buttonCount > 0)
                || (controlCount >= 2 && trimmedTextLength > 0);
            return {
              readyState: globalThis.document ? globalThis.document.readyState : "unknown",
              trimmedTextLength,
              inputCount,
              buttonCount,
              linkCount,
              formCount,
              appRootCount,
              elementCount,
              hasBusyIndicator,
              hasLoadingText,
              controlCount,
              blankCandidate,
              usableFormCandidate
            };
          }

          function debugPostBootstrapEventsSinceManifest() {
            const manifestAt = __sumiPostBootstrapState.manifestReturnedAt;
            if (manifestAt === null) {
              return [];
            }
            return __sumiDebugEvents.filter((event) => {
              return event
                && event.atMs >= manifestAt
                && event.eventKind !== "postBootstrapCheckpoint"
                && !(event.apiName === "runtime.getManifest"
                  && event.resultClassifier === "manifestReturned");
            });
          }

          function debugPostBootstrapPendingRoutes() {
            return Array.from(__sumiPendingBridgeCalls.values()).map((entry) => {
              return Object.assign({}, entry, {
                ageMilliseconds: Math.round(debugNowMS() - entry.startedAt),
                resultClassifier: "unknown pending promise"
              });
            });
          }

          function debugPostBootstrapClassification(dom, routeEvents, pending) {
            const firstBlocker = routeEvents.find((event) => {
              return event.eventKind === "missingAPIAccess"
                || /^missing /.test(event.resultClassifier || "")
                || [
                  "scriptError",
                  "unhandledRejection",
                  "consoleError",
                  "cspViolation",
                  "resourceLoadError",
                  "webContentProcessTerminated"
                ].includes(event.eventKind);
            });
            if (firstBlocker) {
              if (firstBlocker.eventKind === "missingAPIAccess"
                  || /^missing /.test(firstBlocker.resultClassifier || "")) {
                return {
                  resultClassifier: "waits on missing API",
                  firstError:
                    firstBlocker.firstMissingAPIOrPermissionOrLifecycleError
                      || firstBlocker.resultClassifier
                      || "missing API"
                };
              }
              if (firstBlocker.eventKind === "scriptError") {
                return {
                  resultClassifier: "crashed after script error",
                  firstError:
                    firstBlocker.firstMissingAPIOrPermissionOrLifecycleError
                      || "script error"
                };
              }
              if (firstBlocker.eventKind === "unhandledRejection") {
                return {
                  resultClassifier: "Promise rejection",
                  firstError:
                    firstBlocker.firstMissingAPIOrPermissionOrLifecycleError
                      || "Promise rejection"
                };
              }
              if (firstBlocker.eventKind === "resourceLoadError") {
                return {
                  resultClassifier: "network/resource failure",
                  firstError:
                    firstBlocker.firstMissingAPIOrPermissionOrLifecycleError
                      || "resource load error"
                };
              }
              return {
                resultClassifier:
                  firstBlocker.resultClassifier || firstBlocker.eventKind,
                firstError:
                  firstBlocker.firstMissingAPIOrPermissionOrLifecycleError
                    || firstBlocker.resultClassifier
                    || firstBlocker.eventKind
              };
            }
            const oldPending = pending.find((entry) => {
              return entry.ageMilliseconds >= __sumiPendingTimeoutMS;
            });
            if (oldPending) {
              return {
                resultClassifier: "waits on unresolved bridge call",
                firstError:
                  oldPending.resultClassifier || "unknown pending promise"
              };
            }
            if (dom.usableFormCandidate && !dom.hasBusyIndicator) {
              return {
                resultClassifier: "usable onboarding/login UI reached",
                firstError: null
              };
            }
            if (dom.blankCandidate) {
              return {
                resultClassifier: "blank",
                firstError: null
              };
            }
            if (dom.hasBusyIndicator || dom.hasLoadingText) {
              return {
                resultClassifier: "spinner/loading",
                firstError: null
              };
            }
            if (routeEvents.length === 0) {
              return {
                resultClassifier: "no further route emitted within timeout",
                firstError: null
              };
            }
            return {
              resultClassifier: "waits on app state",
              firstError: null
            };
          }

          function debugPostBootstrapCheckpoint(phase) {
            if (__sumiPostBootstrapState.manifestReturnedAt === null) {
              return;
            }
            const dom = debugCoarseDOMState();
            const routeEvents = debugPostBootstrapEventsSinceManifest();
            const pending = debugPostBootstrapPendingRoutes();
            const classification =
              debugPostBootstrapClassification(dom, routeEvents, pending);
            const serviceWorkerRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "serviceWorker";
            }).length;
            const contentScriptRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "contentScript";
            }).length;
            const storageLocalRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "storage.local";
            }).length;
            const storageSessionRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "storage.session";
            }).length;
            const storageSyncRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "storage.sync";
            }).length;
            const i18nRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "i18n";
            }).length;
            const extensionNamespaceRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "backgroundPage";
            }).length;
            const nativeRouteCount = routeEvents.filter((event) => {
              return event.targetContext === "nativeApplication"
                || event.targetContext === "nativeApplicationPort";
            }).length;
            const routeCountExcludingSentinel = routeEvents.filter((event) => {
              return event.apiName !== "postBootstrap.sentinel";
            }).length;
            debugRecord("postBootstrapCheckpoint", {
              apiName: "postBootstrap.sentinel",
              targetContext: "dom",
              resultClassifier: classification.resultClassifier,
              firstMissingAPIOrPermissionOrLifecycleError:
                classification.firstError,
              safeMessageShapeClassification: [
                "dom",
                "readyState=" + dom.readyState,
                "controlCount=" + String(dom.controlCount),
                "inputCount=" + String(dom.inputCount),
                "buttonCount=" + String(dom.buttonCount)
              ].join(";"),
              diagnostics: [
                "phase=" + phase,
                "sinceGetManifestMs=" + String(Math.round(
                  debugNowMS() - __sumiPostBootstrapState.manifestReturnedAt
                )),
                "readyState=" + dom.readyState,
                "visibleTextLength=" + String(dom.trimmedTextLength),
                "inputCount=" + String(dom.inputCount),
                "buttonCount=" + String(dom.buttonCount),
                "linkCount=" + String(dom.linkCount),
                "formCount=" + String(dom.formCount),
                "appRootCount=" + String(dom.appRootCount),
                "elementCount=" + String(dom.elementCount),
                "hasBusyIndicator=" + String(dom.hasBusyIndicator),
                "hasLoadingText=" + String(dom.hasLoadingText),
                "blankCandidate=" + String(dom.blankCandidate),
                "usableFormCandidate=" + String(dom.usableFormCandidate),
                "routesAfterGetManifest=" + String(routeCountExcludingSentinel),
                "pendingRouteCount=" + String(pending.length),
                "serviceWorkerRouteEvents=" + String(serviceWorkerRouteCount),
                "contentScriptRouteEvents=" + String(contentScriptRouteCount),
                "storageLocalRouteEvents=" + String(storageLocalRouteCount),
                "storageSessionRouteEvents=" + String(storageSessionRouteCount),
                "storageSyncRouteEvents=" + String(storageSyncRouteCount),
                "i18nRouteEvents=" + String(i18nRouteCount),
                "extensionNamespaceRouteEvents=" + String(extensionNamespaceRouteCount),
                "nativeRouteEvents=" + String(nativeRouteCount),
                "No raw storage values, message bodies, form values, manifest bodies, URLs, or private payloads were recorded."
              ]
            });
          }

          function debugPostGetManifestBootstrapSentinel(succeeded) {
            if (!succeeded || __sumiPostBootstrapState.scheduled) {
              return;
            }
            __sumiPostBootstrapState.manifestReturnedAt = debugNowMS();
            __sumiPostBootstrapState.scheduled = true;
            debugPostBootstrapCheckpoint("immediate");
            __sumiPostBootstrapCheckpointMS.forEach((delay) => {
              globalThis.setTimeout(() => {
                debugPostBootstrapCheckpoint(
                  delay === __sumiPostBootstrapCheckpointMS[
                    __sumiPostBootstrapCheckpointMS.length - 1
                  ]
                    ? "final"
                    : String(delay) + "ms"
                );
              }, delay);
            });
          }

          function debugStorageEvent(eventKind, record) {
            debugRecord(eventKind || "extensionMethodCalled", {
              apiName: record && record.apiName || "chrome.storage.onChanged",
              targetContext: record && record.targetContext || "storage.local",
              safeMessageShapeClassification:
                record && record.safeMessageShapeClassification || "storageEvent",
              resultClassifier:
                record && record.resultClassifier || "storage event observed",
              diagnostics: record && Array.isArray(record.diagnostics)
                ? record.diagnostics
                : [
                    "eventObjectPresent=true",
                    "listenerCount=0",
                    "changedKeyCount=0",
                    "valueShape=none",
                    "No raw storage keys or values are recorded."
                  ]
            });
          }

          function debugPortEvent(eventKind, record) {
            debugRecord(eventKind, Object.assign({
              targetContext: "serviceWorker",
              safeMessageShapeClassification: "arguments:0"
            }, record || {}));
          }

          let __sumiLastScriptError = {
            key: null,
            atMS: -1000
          };

          function debugRecordScriptError(messageValue, filenameValue, lineValue, columnValue, errorValue, sourceLabel) {
            const message = debugSanitizedMessage(messageValue);
            const filename = debugSafeResourceDescriptor(filenameValue);
            const line = debugSafeInteger(lineValue);
            const column = debugSafeInteger(columnValue);
            const errorName = debugSafeString(errorValue && errorValue.name, 80);
            const dedupeKey = [
              message || "",
              filename || "",
              line || "",
              column || "",
              errorName || ""
            ].join("|");
            const now = debugNowMS();
            if (
              __sumiLastScriptError.key === dedupeKey
              && now - __sumiLastScriptError.atMS < 50
            ) {
              return;
            }
            __sumiLastScriptError.key = dedupeKey;
            __sumiLastScriptError.atMS = now;
            const diagnostics = [
              "Popup emitted a " + sourceLabel + " script error."
            ];
            if (message) {
              diagnostics.push("message=" + message);
            }
            if (filename) {
              diagnostics.push("resource=" + filename);
            }
            if (line) {
              diagnostics.push("line=" + line);
            }
            if (column) {
              diagnostics.push("column=" + column);
            }
            if (errorName) {
              diagnostics.push("errorName=" + errorName);
            }
            debugRecord("scriptError", {
              apiName: "global.error",
              targetContext: "unknown",
              resultClassifier: "script error",
              firstMissingAPIOrPermissionOrLifecycleError:
                message,
              diagnostics
            });
          }

          debugInstallConsoleCapture("error");
          debugInstallConsoleCapture("warn");

          globalThis.onerror = function(message, source, lineno, colno, error) {
            debugRecordScriptError(
              message,
              source,
              lineno,
              colno,
              error,
              "window.onerror"
            );
            return false;
          };

          globalThis.addEventListener("unhandledrejection", (event) => {
            const reason = event && event.reason;
            const message = debugSanitizedMessage(
              reason && (reason.message || String(reason))
            );
            const errorName = debugSafeString(reason && reason.name, 80);
            const diagnostics = ["Popup emitted an unhandled Promise rejection."];
            if (message) {
              diagnostics.push("message=" + message);
            }
            if (errorName) {
              diagnostics.push("errorName=" + errorName);
            }
            debugRecord("unhandledRejection", {
              apiName: "global.unhandledrejection",
              targetContext: "unknown",
              resultClassifier: "Promise rejection",
              firstMissingAPIOrPermissionOrLifecycleError:
                message,
              diagnostics
            });
          });

          globalThis.addEventListener("securitypolicyviolation", (event) => {
            const blocked = debugSafeResourceDescriptor(event && event.blockedURI);
            const source = debugSafeResourceDescriptor(event && event.sourceFile);
            const effectiveDirective = debugSafeString(
              event && event.effectiveDirective,
              80
            );
            const violatedDirective = debugSafeString(
              event && event.violatedDirective,
              120
            );
            const disposition = debugSafeString(event && event.disposition, 40);
            const line = debugSafeInteger(event && event.lineNumber);
            const column = debugSafeInteger(event && event.columnNumber);
            const diagnostics = ["Popup emitted a securitypolicyviolation event."];
            if (effectiveDirective) {
              diagnostics.push("effectiveDirective=" + effectiveDirective);
            }
            if (violatedDirective) {
              diagnostics.push("violatedDirective=" + violatedDirective);
            }
            if (blocked) {
              diagnostics.push("blockedResource=" + blocked);
            }
            if (source) {
              diagnostics.push("source=" + source);
            }
            if (line) {
              diagnostics.push("line=" + line);
            }
            if (column) {
              diagnostics.push("column=" + column);
            }
            if (disposition) {
              diagnostics.push("disposition=" + disposition);
            }
            debugRecord("cspViolation", {
              apiName: "securitypolicyviolation",
              targetContext: "csp",
              resultClassifier: "CSP violation",
              firstMissingAPIOrPermissionOrLifecycleError:
                effectiveDirective
                  ? "CSP violation: " + effectiveDirective
                  : "CSP violation",
              safeMessageShapeClassification: "cspViolation",
              diagnostics
            });
          }, true);

          globalThis.addEventListener("load", (event) => {
            const target = event && event.target;
            if (!target || target === globalThis || target === globalThis.window || target === globalThis.document) {
              return;
            }
            debugRecordResourceEvent(
              "resourceLoaded",
              target,
              "resource loaded"
            );
          }, true);

          globalThis.addEventListener("error", (event) => {
            const target = event && event.target;
            if (target && target !== globalThis && target !== globalThis.window) {
              debugRecordResourceEvent(
                "resourceLoadError",
                target,
                "resource load error"
              );
              return;
            }
            debugRecordScriptError(
              event && event.message,
              event && event.filename,
              event && event.lineno,
              event && event.colno,
              event && event.error,
              "window error event"
            );
          }, true);

          globalThis.addEventListener("DOMContentLoaded", () => {
            debugRecordResourceTiming("domcontentloaded");
          }, { once: true });

          globalThis.addEventListener("load", () => {
            debugRecordResourceTiming("window-load");
          }, { once: true });

          globalThis.setTimeout(() => {
            debugRecordResourceTiming("timer-250ms");
          }, 250);

          Object.defineProperty(globalThis, "__sumiChromeMV3PopupOptionsDebugSnapshot", {
            value() {
              const pending = Array.from(__sumiPendingBridgeCalls.values()).map((entry) => {
                return Object.assign({}, entry, {
                  ageMilliseconds: Math.round(debugNowMS() - entry.startedAt),
                  resultClassifier: "unknown pending promise"
                });
              });
              return {
                sourceContext: config.sourceContext,
                pending,
                events: __sumiDebugEvents.slice()
              };
            },
            configurable: false
          });
        """
    }
    #endif

    private static func jsonString(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

#if canImport(WebKit)
@MainActor
final class ChromeMV3PopupOptionsWKScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3PopupOptionsJSBridgeHandler

    init(handler: ChromeMV3PopupOptionsJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        let response = await handler.handleAsync(message.body)
        return (response.foundationObject, nil)
    }
}
#endif

private func uniqueSortedPopupOptionsBridge(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func uniqueSortedPreservingOrderPopupOptionsBridge(
    _ values: [String]
) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for value in values where value.isEmpty == false
        && seen.insert(value).inserted {
        unique.append(value)
    }
    return unique
}

private func stableIDPopupOptionsBridge(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueBlockedDiagnostics(
    _ diagnostics: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
) -> [ChromeMV3PopupOptionsBlockedAPIDiagnostic] {
    var seen: Set<String> = []
    var unique: [ChromeMV3PopupOptionsBlockedAPIDiagnostic] = []
    for diagnostic in diagnostics.sorted(by: {
        if $0.namespace != $1.namespace { return $0.namespace < $1.namespace }
        return $0.methodName < $1.methodName
    }) {
        let key = "\(diagnostic.namespace).\(diagnostic.methodName)"
        if seen.insert(key).inserted {
            unique.append(diagnostic)
        }
    }
    return unique
}

private func uniquePermissionEventDispatches(
    _ records: [ChromeMV3PermissionEventDispatchRecord]
) -> [ChromeMV3PermissionEventDispatchRecord] {
    var seen: Set<String> = []
    var unique: [ChromeMV3PermissionEventDispatchRecord] = []
    for record in records.sorted(by: {
        if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
        return $0.id < $1.id
    }) {
        if seen.insert(record.id).inserted {
            unique.append(record)
        }
    }
    return unique
}

private extension ChromeMV3StorageValue {
    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded() == value,
              value >= Double(Int.min),
              value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }

    var popupOptionsBridgeFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.popupOptionsBridgeFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.popupOptionsBridgeFoundationObject)
        case .string(let value):
            return value
        }
    }
}

private extension ChromeMV3StorageOnChangedEventPayload {
    var popupOptionsBridgeFoundationObject: Any {
        [
            "areaName": areaName,
            "changedKeys": changedKeys,
            "changes":
                changes.map(\.popupOptionsBridgeFoundationObject),
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
    var popupOptionsBridgeFoundationObject: Any {
        var object: [String: Any] = ["key": key]
        if let oldValue {
            object["oldValue"] =
                oldValue.popupOptionsBridgeFoundationObject
        }
        if let newValue {
            object["newValue"] =
                newValue.popupOptionsBridgeFoundationObject
        }
        return object
    }
}

private extension ChromeMV3PermissionsAPIEventPayload {
    var popupOptionsBridgeFoundationObject: Any {
        [
            "eventKind": eventKind.rawValue,
            "permissions": permissions,
            "origins": origins,
            "extensionID": extensionID,
            "profileID": profileID,
        ]
    }
}
