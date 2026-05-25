//
//  ChromeMV3ExtensionPageHostHarness.swift
//  Sumi
//
//  DEBUG/internal extension-owned page host diagnostics for action popup and
//  options fixtures. This is not product UI and not Chrome MV3 runtime support.
//

import CryptoKit
import Foundation

enum ChromeMV3ExtensionPageKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case optionsPage
    case optionsUI
    case extensionPageFixture

    static func < (
        lhs: ChromeMV3ExtensionPageKind,
        rhs: ChromeMV3ExtensionPageKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ExtensionPageManifestReadStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case loaded
    case missing
    case unreadable
    case corrupt
}

enum ChromeMV3ExtensionPagePathSafety:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case safe
    case unsafe
    case missing
}

enum ChromeMV3ExtensionPagePathNormalization {
    case success(String)
    case failure(String)
}

struct ChromeMV3ExtensionPageDeclaration:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3ExtensionPageKind
    var sourceManifestField: String
    var declaredPath: String
    var normalizedPath: String?
    var manifestPath: String
    var generatedRewrittenBundlePath: String
    var generatedResourcePath: String?
    var resourceExists: Bool
    var pathSafety: ChromeMV3ExtensionPagePathSafety
    var safetyDiagnostics: [String]
}

struct ChromeMV3ExtensionPageDeclarationModel:
    Codable,
    Equatable,
    Sendable
{
    var generatedRewrittenBundlePath: String
    var manifestPath: String
    var manifestReadStatus: ChromeMV3ExtensionPageManifestReadStatus
    var manifestSHA256: String?
    var declarations: [ChromeMV3ExtensionPageDeclaration]
    var actionDefaultPopupDeclared: Bool
    var optionsPageDeclared: Bool
    var optionsUIPageDeclared: Bool
    var extensionPageFixtureDeclared: Bool
    var warnings: [String]
}

enum ChromeMV3ExtensionPageDeclarationReader {
    static func read(
        generatedRewrittenRootPath rootPath: String,
        extensionPageFixturePath: String? = nil,
        fileManager: FileManager = .default
    ) -> ChromeMV3ExtensionPageDeclarationModel {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        var warnings: [String] = []
        let manifestObject: [String: Any]
        let manifestStatus: ChromeMV3ExtensionPageManifestReadStatus
        var manifestHash: String?

        if fileManager.fileExists(atPath: manifestURL.path) == false {
            manifestObject = [:]
            manifestStatus = .missing
            manifestHash = nil
            warnings.append("manifest.json is missing.")
        } else {
            do {
                let data = try Data(contentsOf: manifestURL)
                manifestHash = chromeMV3ExtensionPageSHA256(data)
                guard
                    let object = try JSONSerialization.jsonObject(
                        with: data
                    ) as? [String: Any]
                else {
                    manifestObject = [:]
                    manifestStatus = .corrupt
                    warnings.append("manifest.json root is not an object.")
                    return model(
                        rootURL: rootURL,
                        manifestURL: manifestURL,
                        manifestStatus: manifestStatus,
                        manifestHash: manifestHash,
                        declarations: [],
                        warnings: warnings
                    )
                }
                manifestObject = object
                manifestStatus = .loaded
            } catch {
                manifestObject = [:]
                manifestStatus = .unreadable
                manifestHash = nil
                warnings.append(
                    "manifest.json could not be read: \(error.localizedDescription)"
                )
            }
        }

        var declarations: [ChromeMV3ExtensionPageDeclaration] = []
        if
            let action = manifestObject["action"] as? [String: Any],
            let popup = stringValue(action["default_popup"])
        {
            declarations.append(
                declaration(
                    kind: .actionPopup,
                    field: "action.default_popup",
                    path: popup,
                    rootURL: rootURL,
                    manifestURL: manifestURL,
                    fileManager: fileManager
                )
            )
        }
        if let optionsPage = stringValue(manifestObject["options_page"]) {
            declarations.append(
                declaration(
                    kind: .optionsPage,
                    field: "options_page",
                    path: optionsPage,
                    rootURL: rootURL,
                    manifestURL: manifestURL,
                    fileManager: fileManager
                )
            )
        }
        if
            let optionsUI = manifestObject["options_ui"] as? [String: Any],
            let page = stringValue(optionsUI["page"])
        {
            declarations.append(
                declaration(
                    kind: .optionsUI,
                    field: "options_ui.page",
                    path: page,
                    rootURL: rootURL,
                    manifestURL: manifestURL,
                    fileManager: fileManager
                )
            )
        }
        if let fixture = extensionPageFixturePath {
            declarations.append(
                declaration(
                    kind: .extensionPageFixture,
                    field: "debug.extension_page_fixture",
                    path: fixture,
                    rootURL: rootURL,
                    manifestURL: manifestURL,
                    fileManager: fileManager
                )
            )
        }

        return model(
            rootURL: rootURL,
            manifestURL: manifestURL,
            manifestStatus: manifestStatus,
            manifestHash: manifestHash,
            declarations: declarations,
            warnings: warnings
        )
    }

    private static func model(
        rootURL: URL,
        manifestURL: URL,
        manifestStatus: ChromeMV3ExtensionPageManifestReadStatus,
        manifestHash: String?,
        declarations: [ChromeMV3ExtensionPageDeclaration],
        warnings: [String]
    ) -> ChromeMV3ExtensionPageDeclarationModel {
        let sorted = declarations.sorted {
            if $0.kind != $1.kind {
                return $0.kind < $1.kind
            }
            return $0.sourceManifestField < $1.sourceManifestField
        }
        return ChromeMV3ExtensionPageDeclarationModel(
            generatedRewrittenBundlePath: rootURL.path,
            manifestPath: manifestURL.path,
            manifestReadStatus: manifestStatus,
            manifestSHA256: manifestHash,
            declarations: sorted,
            actionDefaultPopupDeclared:
                sorted.contains { $0.kind == .actionPopup },
            optionsPageDeclared:
                sorted.contains { $0.kind == .optionsPage },
            optionsUIPageDeclared:
                sorted.contains { $0.kind == .optionsUI },
            extensionPageFixtureDeclared:
                sorted.contains { $0.kind == .extensionPageFixture },
            warnings: uniqueSorted(warnings)
        )
    }

    private static func declaration(
        kind: ChromeMV3ExtensionPageKind,
        field: String,
        path: String,
        rootURL: URL,
        manifestURL: URL,
        fileManager: FileManager
    ) -> ChromeMV3ExtensionPageDeclaration {
        let normalized: String?
        let pathSafety: ChromeMV3ExtensionPagePathSafety
        let resourceURL: URL?
        var diagnostics: [String] = []

        switch ChromeMV3ExtensionPageResourcePath.normalize(path) {
        case .success(let safePath):
            normalized = safePath
            resourceURL = ChromeMV3ExtensionPageResourcePath
                .resourceURL(
                    normalizedRelativePath: safePath,
                    rootURL: rootURL
                )
            if let resourceURL,
               fileManager.fileExists(atPath: resourceURL.path)
            {
                pathSafety = .safe
            } else {
                pathSafety = .missing
                diagnostics.append(
                    "Declared extension page resource is missing: \(safePath)"
                )
            }
        case .failure(let reason):
            normalized = nil
            resourceURL = nil
            pathSafety = .unsafe
            diagnostics.append(reason)
        }

        return ChromeMV3ExtensionPageDeclaration(
            kind: kind,
            sourceManifestField: field,
            declaredPath: path,
            normalizedPath: normalized,
            manifestPath: manifestURL.path,
            generatedRewrittenBundlePath: rootURL.path,
            generatedResourcePath: resourceURL?.path,
            resourceExists:
                resourceURL.map { fileManager.fileExists(atPath: $0.path) }
                    ?? false,
            pathSafety: pathSafety,
            safetyDiagnostics: uniqueSorted(diagnostics)
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }
}

enum ChromeMV3ExtensionPageLinkedResourceKind:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case pageHTML
    case localScript
    case inertLocalScript
    case localStylesheet
    case localImage
    case localFrame
    case localOther
    case remoteResource
    case inlineScript
    case unsafeLocalPath
    case missingLocalResource
}

struct ChromeMV3ExtensionPageLinkedResource:
    Codable,
    Equatable,
    Sendable
{
    var tagName: String
    var attributeName: String?
    var rawValue: String
    var normalizedPath: String?
    var generatedResourcePath: String?
    var exists: Bool
    var kind: ChromeMV3ExtensionPageLinkedResourceKind
    var inertLocalScript: Bool
    var blocked: Bool
    var diagnostics: [String]
}

struct ChromeMV3ExtensionPageResourceResolution:
    Codable,
    Equatable,
    Sendable
{
    var declaration: ChromeMV3ExtensionPageDeclaration
    var htmlPageExists: Bool
    var htmlPageSHA256: String?
    var htmlTitle: String?
    var fixtureMarker: String?
    var contentSecurityPolicyMetaPresent: Bool
    var linkedResources: [ChromeMV3ExtensionPageLinkedResource]
    var missingResourcePaths: [String]
    var unsafeResourcePaths: [String]
    var remoteResourceReferences: [String]
    var executableLocalScriptPaths: [String]
    var inertLocalScriptPaths: [String]
    var resourceSafeForExtensionPageHost: Bool
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3ExtensionPageResourceResolver {
    static func resolve(
        declaration: ChromeMV3ExtensionPageDeclaration,
        fileManager: FileManager = .default
    ) -> ChromeMV3ExtensionPageResourceResolution {
        var blockers = declaration.safetyDiagnostics
        var warnings: [String] = []
        guard
            declaration.pathSafety == .safe,
            let normalizedPath = declaration.normalizedPath,
            let pageURL = declaration.generatedResourcePath
                .map(URL.init(fileURLWithPath:))
        else {
            if declaration.pathSafety == .missing {
                blockers.append("Extension page HTML resource is missing.")
            }
            if declaration.pathSafety == .unsafe {
                blockers.append("Extension page path is unsafe.")
            }
            return resolution(
                declaration: declaration,
                htmlData: nil,
                html: nil,
                linkedResources: [],
                blockers: blockers,
                warnings: warnings
            )
        }

        guard normalizedPath.lowercased().hasSuffix(".html")
            || normalizedPath.lowercased().hasSuffix(".htm")
        else {
            blockers.append("Extension page host only accepts HTML page resources.")
            return resolution(
                declaration: declaration,
                htmlData: nil,
                html: nil,
                linkedResources: [],
                blockers: blockers,
                warnings: warnings
            )
        }

        let htmlData: Data
        let html: String
        do {
            htmlData = try Data(contentsOf: pageURL)
            html = String(data: htmlData, encoding: .utf8) ?? ""
        } catch {
            blockers.append(
                "Extension page HTML could not be read: \(error.localizedDescription)"
            )
            return resolution(
                declaration: declaration,
                htmlData: nil,
                html: nil,
                linkedResources: [],
                blockers: blockers,
                warnings: warnings
            )
        }

        let rootURL = URL(
            fileURLWithPath: declaration.generatedRewrittenBundlePath,
            isDirectory: true
        ).standardizedFileURL
        let pageDirectory = normalizedPath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        let linked = linkedResources(
            in: html,
            rootURL: rootURL,
            pageDirectory: pageDirectory,
            fileManager: fileManager
        )
        blockers += linked.flatMap { resource in
            resource.blocked ? resource.diagnostics : []
        }

        if linked.contains(where: { $0.kind == .localScript }) {
            blockers.append(
                "Local script dependencies must be explicitly marked as inert fixture scripts."
            )
        }
        if linked.contains(where: { $0.kind == .inlineScript }) {
            blockers.append(
                "Inline script is not allowed in the DEBUG/internal extension page host fixture."
            )
        }
        if linked.contains(where: { $0.kind == .remoteResource }) {
            blockers.append("Remote extension page resources are not loaded.")
        }
        if html.isEmpty {
            warnings.append("Extension page HTML decoded as an empty UTF-8 string.")
        }

        return resolution(
            declaration: declaration,
            htmlData: htmlData,
            html: html,
            linkedResources: linked,
            blockers: blockers,
            warnings: warnings
        )
    }

    private static func resolution(
        declaration: ChromeMV3ExtensionPageDeclaration,
        htmlData: Data?,
        html: String?,
        linkedResources: [ChromeMV3ExtensionPageLinkedResource],
        blockers: [String],
        warnings: [String]
    ) -> ChromeMV3ExtensionPageResourceResolution {
        let sortedLinked = linkedResources.sorted {
            if $0.tagName != $1.tagName {
                return $0.tagName < $1.tagName
            }
            return $0.rawValue < $1.rawValue
        }
        return ChromeMV3ExtensionPageResourceResolution(
            declaration: declaration,
            htmlPageExists: declaration.resourceExists,
            htmlPageSHA256: htmlData.map(chromeMV3ExtensionPageSHA256),
            htmlTitle: html.flatMap(extractTitle),
            fixtureMarker: html.flatMap(extractFixtureMarker),
            contentSecurityPolicyMetaPresent:
                html.map(hasContentSecurityPolicyMeta) ?? false,
            linkedResources: sortedLinked,
            missingResourcePaths:
                uniqueSorted(
                    sortedLinked.compactMap {
                        $0.kind == .missingLocalResource
                            ? $0.normalizedPath
                            : nil
                    }
                ),
            unsafeResourcePaths:
                uniqueSorted(
                    sortedLinked.compactMap {
                        $0.kind == .unsafeLocalPath
                            ? $0.rawValue
                            : nil
                    }
                ),
            remoteResourceReferences:
                uniqueSorted(
                    sortedLinked
                        .filter { $0.kind == .remoteResource }
                        .map(\.rawValue)
                ),
            executableLocalScriptPaths:
                uniqueSorted(
                    sortedLinked.compactMap {
                        $0.kind == .localScript ? $0.normalizedPath : nil
                    }
                ),
            inertLocalScriptPaths:
                uniqueSorted(
                    sortedLinked.compactMap {
                        $0.kind == .inertLocalScript ? $0.normalizedPath : nil
                    }
                ),
            resourceSafeForExtensionPageHost:
                uniqueSorted(blockers).isEmpty
                    && declaration.resourceExists,
            blockingReasons: uniqueSorted(blockers),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func linkedResources(
        in html: String,
        rootURL: URL,
        pageDirectory: String,
        fileManager: FileManager
    ) -> [ChromeMV3ExtensionPageLinkedResource] {
        var resources: [ChromeMV3ExtensionPageLinkedResource] = []
        resources += scriptResources(
            in: html,
            rootURL: rootURL,
            pageDirectory: pageDirectory,
            fileManager: fileManager
        )
        resources += tagResources(
            in: html,
            tagName: "link",
            attributeName: "href",
            rootURL: rootURL,
            pageDirectory: pageDirectory,
            fileManager: fileManager
        )
        resources += tagResources(
            in: html,
            tagName: "img",
            attributeName: "src",
            rootURL: rootURL,
            pageDirectory: pageDirectory,
            fileManager: fileManager
        )
        resources += tagResources(
            in: html,
            tagName: "iframe",
            attributeName: "src",
            rootURL: rootURL,
            pageDirectory: pageDirectory,
            fileManager: fileManager
        )
        return resources
    }

    private static func scriptResources(
        in html: String,
        rootURL: URL,
        pageDirectory: String,
        fileManager: FileManager
    ) -> [ChromeMV3ExtensionPageLinkedResource] {
        tagMatches(in: html, tagName: "script").map { tag, body in
            if let src = attribute("src", in: tag) {
                return linkedResource(
                    tagName: "script",
                    attributeName: "src",
                    rawValue: src,
                    rootURL: rootURL,
                    pageDirectory: pageDirectory,
                    fileManager: fileManager,
                    explicitInert:
                        isExplicitInertScript(tag: tag, body: body)
                )
            }
            let trimmed = body
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ChromeMV3ExtensionPageLinkedResource(
                tagName: "script",
                attributeName: nil,
                rawValue: "inline-script",
                normalizedPath: nil,
                generatedResourcePath: nil,
                exists: trimmed.isEmpty,
                kind:
                    trimmed.isEmpty
                        ? .localOther
                        : .inlineScript,
                inertLocalScript: false,
                blocked: trimmed.isEmpty == false,
                diagnostics:
                    trimmed.isEmpty
                        ? []
                        : [
                            "Inline script is not a local inert fixture script.",
                        ]
            )
        }
    }

    private static func tagResources(
        in html: String,
        tagName: String,
        attributeName: String,
        rootURL: URL,
        pageDirectory: String,
        fileManager: FileManager
    ) -> [ChromeMV3ExtensionPageLinkedResource] {
        tagMatches(in: html, tagName: tagName).compactMap { tag, _ in
            guard let raw = attribute(attributeName, in: tag),
                  raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix("#") == false
            else { return nil }
            return linkedResource(
                tagName: tagName,
                attributeName: attributeName,
                rawValue: raw,
                rootURL: rootURL,
                pageDirectory: pageDirectory,
                fileManager: fileManager,
                explicitInert: false
            )
        }
    }

    private static func linkedResource(
        tagName: String,
        attributeName: String,
        rawValue: String,
        rootURL: URL,
        pageDirectory: String,
        fileManager: FileManager,
        explicitInert: Bool
    ) -> ChromeMV3ExtensionPageLinkedResource {
        if ChromeMV3ExtensionPageResourcePath.isRemote(rawValue) {
            return ChromeMV3ExtensionPageLinkedResource(
                tagName: tagName,
                attributeName: attributeName,
                rawValue: rawValue,
                normalizedPath: nil,
                generatedResourcePath: nil,
                exists: false,
                kind: .remoteResource,
                inertLocalScript: false,
                blocked: true,
                diagnostics: [
                    "Remote resource is blocked: \(rawValue)",
                ]
            )
        }

        switch ChromeMV3ExtensionPageResourcePath.normalize(
            rawValue,
            relativeTo: pageDirectory
        ) {
        case .failure(let reason):
            return ChromeMV3ExtensionPageLinkedResource(
                tagName: tagName,
                attributeName: attributeName,
                rawValue: rawValue,
                normalizedPath: nil,
                generatedResourcePath: nil,
                exists: false,
                kind: .unsafeLocalPath,
                inertLocalScript: false,
                blocked: true,
                diagnostics: [reason]
            )
        case .success(let path):
            let url = ChromeMV3ExtensionPageResourcePath.resourceURL(
                normalizedRelativePath: path,
                rootURL: rootURL
            )
            let exists = url.map { fileManager.fileExists(atPath: $0.path) }
                ?? false
            if exists == false {
                return ChromeMV3ExtensionPageLinkedResource(
                    tagName: tagName,
                    attributeName: attributeName,
                    rawValue: rawValue,
                    normalizedPath: path,
                    generatedResourcePath: url?.path,
                    exists: false,
                    kind: .missingLocalResource,
                    inertLocalScript: false,
                    blocked: true,
                    diagnostics: [
                        "Linked local extension page resource is missing: \(path)",
                    ]
                )
            }
            let isScript = tagName.lowercased() == "script"
            let inert = isScript
                && explicitInert
                && localScriptContentLooksInert(url)
            let kind: ChromeMV3ExtensionPageLinkedResourceKind
            if isScript {
                kind = inert ? .inertLocalScript : .localScript
            } else if tagName.lowercased() == "link" {
                kind = .localStylesheet
            } else if tagName.lowercased() == "img" {
                kind = .localImage
            } else if tagName.lowercased() == "iframe" {
                kind = .localFrame
            } else {
                kind = .localOther
            }
            return ChromeMV3ExtensionPageLinkedResource(
                tagName: tagName,
                attributeName: attributeName,
                rawValue: rawValue,
                normalizedPath: path,
                generatedResourcePath: url?.path,
                exists: true,
                kind: kind,
                inertLocalScript: inert,
                blocked: isScript && inert == false,
                diagnostics:
                    isScript && inert == false
                        ? [
                            "Local script is not explicitly classified as an inert fixture script: \(path)",
                        ]
                        : []
            )
        }
    }

    private static func localScriptContentLooksInert(_ url: URL?) -> Bool {
        guard let url,
              let data = try? Data(contentsOf: url),
              let script = String(data: data, encoding: .utf8)
        else { return false }
        let lowered = script.lowercased()
        let forbidden = [
            "chrome.",
            "browser.",
            "runtime.",
            "fetch(",
            "xmlhttprequest",
            "websocket",
            "import(",
            "eval(",
            "connect" + "native",
        ]
        return forbidden.contains { lowered.contains($0) } == false
    }

    private static func isExplicitInertScript(
        tag: String,
        body: String
    ) -> Bool {
        let lowered = tag.lowercased()
        if lowered.contains("data-sumi-extension-page-fixture=\"inert\"")
            || lowered.contains("data-sumi-inert=\"true\"")
        {
            return true
        }
        let type = attribute("type", in: tag)?.lowercased()
        if type == "application/json" || type == "text/plain" {
            return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    private static func tagMatches(
        in html: String,
        tagName: String
    ) -> [(tag: String, body: String)] {
        let escaped = NSRegularExpression.escapedPattern(for: tagName)
        let pattern =
            #"<\s*\#(escaped)\b([^>]*)>(.*?)<\s*/\s*\#(escaped)\s*>"#
        let selfClosing =
            #"<\s*\#(escaped)\b([^>]*)/?>"#
        var matches: [(String, String)] = []
        matches += regexMatches(pattern: pattern, in: html).map { match in
            let tag = match.indices.contains(0) ? String(match[0]) : ""
            let body = match.indices.contains(2) ? String(match[2]) : ""
            return (tag, body)
        }
        matches += regexMatches(pattern: selfClosing, in: html).map { match in
            let tag = match.indices.contains(0) ? String(match[0]) : ""
            return (tag, "")
        }
        return matches
    }

    private static func attribute(
        _ name: String,
        in tag: String
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern =
            #"\b\#(escaped)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let match = regexMatches(pattern: pattern, in: tag).first else {
            return nil
        }
        for index in 1..<match.count {
            if match[index].isEmpty == false {
                return String(match[index])
            }
        }
        return nil
    }

    private static func extractTitle(from html: String) -> String? {
        guard
            let match = regexMatches(
                pattern: #"<\s*title\s*>(.*?)<\s*/\s*title\s*>"#,
                in: html
            ).first?[1]
        else { return nil }
        return String(match)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFixtureMarker(from html: String) -> String? {
        attribute("data-sumi-extension-page-fixture-marker", in: html)
    }

    private static func hasContentSecurityPolicyMeta(_ html: String) -> Bool {
        regexMatches(
            pattern:
                #"<\s*meta\b[^>]*http-equiv\s*=\s*['"]?content-security-policy['"]?[^>]*>"#,
            in: html
        ).isEmpty == false
    }

    private static func regexMatches(
        pattern: String,
        in string: String
    ) -> [[Substring]] {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else { return [] }
        let nsRange = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: nsRange).map { result in
            (0..<result.numberOfRanges).map { index in
                guard let range = Range(result.range(at: index), in: string)
                else { return "" }
                return string[range]
            }
        }
    }
}

enum ChromeMV3ExtensionPageFixturePolicyBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case noExtensionPageDeclaration
    case unsafePagePath
    case missingPageResource
    case htmlResourceUnsafe
    case remoteResourceDependency
    case dynamicScriptDependency
    case nativeMessagingDetected
    case externallyConnectableDetected
    case serviceWorkerWakeRequirement
    case contentScriptProductHostRequirement
    case productHostRequirement
    case productJSBridgeDependency
    case productUIAttachmentRequired
    case runtimeLoadabilityInvariantViolation

    var reason: String {
        switch self {
        case .noExtensionPageDeclaration:
            return "No action/options extension page declaration was selected."
        case .unsafePagePath:
            return "The selected extension page path is unsafe."
        case .missingPageResource:
            return "The selected extension page resource is missing."
        case .htmlResourceUnsafe:
            return "The selected extension page HTML or local resources are not safe for the host fixture."
        case .remoteResourceDependency:
            return "The extension page declares a remote resource dependency."
        case .dynamicScriptDependency:
            return "The extension page has executable script that is not explicitly inert."
        case .nativeMessagingDetected:
            return "nativeMessaging is declared and is forbidden for this host harness."
        case .externallyConnectableDetected:
            return "externally_connectable would expose an external messaging path."
        case .serviceWorkerWakeRequirement:
            return "A background service worker would require a wake/runtime path."
        case .contentScriptProductHostRequirement:
            return "Content scripts require product host/injection policy and are outside this host harness."
        case .productHostRequirement:
            return "Host permissions or optional host permissions require product browsing integration."
        case .productJSBridgeDependency:
            return "The page appears to depend on Chrome extension APIs or a product bridge."
        case .productUIAttachmentRequired:
            return "The fixture requires product UI attachment, which is forbidden."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable must remain false."
        }
    }
}

struct ChromeMV3ExtensionPageFixturePolicyResult:
    Codable,
    Equatable,
    Sendable
{
    var selectedKind: ChromeMV3ExtensionPageKind?
    var selectedSourceManifestField: String?
    var pageDeclarationSummary: ChromeMV3ExtensionPageDeclarationModel
    var resourceResolution: ChromeMV3ExtensionPageResourceResolution?
    var manifestPermissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var backgroundServiceWorkerPath: String?
    var contentScriptCount: Int
    var externallyConnectablePresent: Bool
    var fixturePagePolicyPassed: Bool
    var blockers: [ChromeMV3ExtensionPageFixturePolicyBlocker]
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3ExtensionPageFixturePolicy {
    static func evaluate(
        declarationModel: ChromeMV3ExtensionPageDeclarationModel,
        selectedKind: ChromeMV3ExtensionPageKind,
        fileManager: FileManager = .default
    ) -> ChromeMV3ExtensionPageFixturePolicyResult {
        let manifestObject = manifestJSONObject(
            path: declarationModel.manifestPath
        )
        let selectedDeclaration = declarationModel.declarations.first {
            $0.kind == selectedKind
        }
        let resourceResolution = selectedDeclaration.map {
            ChromeMV3ExtensionPageResourceResolver.resolve(
                declaration: $0,
                fileManager: fileManager
            )
        }
        var blockers: [ChromeMV3ExtensionPageFixturePolicyBlocker] = []
        var warnings = declarationModel.warnings

        if selectedDeclaration == nil {
            blockers.append(.noExtensionPageDeclaration)
        }
        if selectedDeclaration?.pathSafety == .unsafe {
            blockers.append(.unsafePagePath)
        }
        if selectedDeclaration?.pathSafety == .missing
            || selectedDeclaration?.resourceExists == false
        {
            blockers.append(.missingPageResource)
        }
        if resourceResolution?.resourceSafeForExtensionPageHost == false {
            blockers.append(.htmlResourceUnsafe)
        }
        if resourceResolution?.remoteResourceReferences.isEmpty == false {
            blockers.append(.remoteResourceDependency)
        }
        if resourceResolution?.executableLocalScriptPaths.isEmpty == false
            || resourceResolution?.linkedResources.contains(where: {
                $0.kind == .inlineScript
            }) == true
        {
            blockers.append(.dynamicScriptDependency)
        }

        let permissions = stringArray(manifestObject["permissions"])
        let optionalPermissions =
            stringArray(manifestObject["optional_permissions"])
        let allPermissions = Set(permissions + optionalPermissions)
        let hostPermissions = stringArray(manifestObject["host_permissions"])
        let optionalHostPermissions = stringArray(
            manifestObject["optional_host_permissions"]
        )
        let background = manifestObject["background"] as? [String: Any]
        let serviceWorker = stringValue(background?["service_worker"])
        let contentScripts = manifestObject["content_scripts"] as? [Any] ?? []
        let externallyConnectable =
            manifestObject["externally_connectable"] != nil

        if allPermissions.contains("nativeMessaging") {
            blockers.append(.nativeMessagingDetected)
        }
        if externallyConnectable {
            blockers.append(.externallyConnectableDetected)
        }
        if serviceWorker?.isEmpty == false {
            blockers.append(.serviceWorkerWakeRequirement)
        }
        if contentScripts.isEmpty == false {
            blockers.append(.contentScriptProductHostRequirement)
        }
        if hostPermissions.isEmpty == false
            || optionalHostPermissions.isEmpty == false
        {
            blockers.append(.productHostRequirement)
        }
        if pageReferencesExtensionAPI(resourceResolution) {
            blockers.append(.productJSBridgeDependency)
        }

        warnings.append(
            "This policy validates only deterministic extension-owned page fixtures; it does not expose action popup or options UI in product."
        )

        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        return ChromeMV3ExtensionPageFixturePolicyResult(
            selectedKind: selectedDeclaration?.kind,
            selectedSourceManifestField:
                selectedDeclaration?.sourceManifestField,
            pageDeclarationSummary: declarationModel,
            resourceResolution: resourceResolution,
            manifestPermissions: uniqueSorted(permissions),
            optionalPermissions: uniqueSorted(optionalPermissions),
            hostPermissions: uniqueSorted(hostPermissions),
            optionalHostPermissions: uniqueSorted(optionalHostPermissions),
            backgroundServiceWorkerPath: serviceWorker,
            contentScriptCount: contentScripts.count,
            externallyConnectablePresent: externallyConnectable,
            fixturePagePolicyPassed: uniqueBlockers.isEmpty,
            blockers: uniqueBlockers,
            blockingReasons:
                uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func pageReferencesExtensionAPI(
        _ resolution: ChromeMV3ExtensionPageResourceResolution?
    ) -> Bool {
        guard let pagePath = resolution?.declaration.generatedResourcePath,
              let html = try? String(
                contentsOfFile: pagePath,
                encoding: .utf8
              )
        else { return false }
        let lowered = html.lowercased()
        return lowered.contains("chrome.")
            || lowered.contains("browser.")
            || lowered.contains("runtime.")
    }

    private static func manifestJSONObject(path: String) -> [String: Any] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return [:] }
        return object
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }
}

enum ChromeMV3ExtensionPageHostOutcome:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case blocked
    case attempted
    case loaded
    case failed
}

enum ChromeMV3ExtensionPageHostLoadState:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notAttempted
    case blocked
    case attempted
    case succeeded
    case failed
}

enum ChromeMV3ExtensionPageObservationState:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notAttempted
    case blocked
    case succeeded
    case failed
}

enum ChromeMV3ExtensionPageHostBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case explicitHostFlagMissing
    case explicitSyntheticWebViewCreationMissing
    case explicitSyntheticNavigationMissing
    case fixturePolicyFailed
    case acceptedExtensionObjectUnavailable
    case detachedContextMissing
    case controllerLoadStateUnavailable
    case controllerLoadGateBlocked
    case contextLoadUnavailable
    case sameControllerConfigurationUnavailable
    case syntheticConfigurationHasUserScripts
    case jsBridgeExposed
    case serviceWorkerWakeAvailable
    case runtimeDispatchAvailable
    case nativeMessagingAvailable
    case productUIPathRequested
    case runtimeLoadabilityInvariantViolation

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .explicitHostFlagMissing:
            return "Explicit DEBUG/internal action/options page host flag is not enabled."
        case .explicitSyntheticWebViewCreationMissing:
            return "Synthetic hidden WKWebView creation requires its explicit DEBUG/internal flag."
        case .explicitSyntheticNavigationMissing:
            return "Synthetic extension page navigation requires its explicit DEBUG/internal flag."
        case .fixturePolicyFailed:
            return "The action/options fixture policy did not pass."
        case .acceptedExtensionObjectUnavailable:
            return "An accepted WKWebExtension object is not available."
        case .detachedContextMissing:
            return "A detached WKWebExtensionContext is not available."
        case .controllerLoadStateUnavailable:
            return "Controller-load state is unavailable for this page host attempt."
        case .controllerLoadGateBlocked:
            return "The controller-load gate is blocked."
        case .contextLoadUnavailable:
            return "The WKWebExtensionContext is not loaded; extension page navigation remains blocked."
        case .sameControllerConfigurationUnavailable:
            return "A same-controller extension page WKWebViewConfiguration is unavailable."
        case .syntheticConfigurationHasUserScripts:
            return "The synthetic extension page configuration contains user scripts."
        case .jsBridgeExposed:
            return "The Sumi JS bridge is exposed or injectable."
        case .serviceWorkerWakeAvailable:
            return "A service-worker wake path is available or was requested."
        case .runtimeDispatchAvailable:
            return "Runtime message dispatch is available or was requested."
        case .nativeMessagingAvailable:
            return "Native messaging launch or port opening is available."
        case .productUIPathRequested:
            return "Product UI exposure or toolbar/options integration was requested."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable and runtime availability must remain false."
        }
    }
}

struct ChromeMV3ExtensionPageHostGateInput:
    Codable,
    Equatable,
    Sendable
{
    var candidateID: String
    var generatedRewrittenRootPath: String
    var selectedKind: ChromeMV3ExtensionPageKind
    var extensionsModuleEnabled: Bool
    var explicitInternalExtensionPageHostAllowed: Bool
    var explicitSyntheticWebViewCreationAllowed: Bool
    var explicitSyntheticNavigationAllowed: Bool
    var explicitTestDOMInspectionAllowed: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextAvailable: Bool
    var controllerLoadGateDecision:
        ChromeMV3ControllerLoadGateDecision?
    var controllerLoadOwnerDiagnostics:
        ChromeMV3ControllerLoadOwnerDiagnostics?
    var loadedContextAvailable: Bool
    var sameControllerConfigurationAvailable: Bool
    var syntheticConfigurationUserScriptCount: Int
    var fixturePolicy:
        ChromeMV3ExtensionPageFixturePolicyResult
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var requestedProductUI: Bool
    var requestedToolbarIntegration: Bool
    var requestedSettingsIntegration: Bool
    var requestedServiceWorkerWake: Bool
    var requestedRuntimeDispatch: Bool
    var requestedNativeMessagingLaunch: Bool
}

struct ChromeMV3ExtensionPageHostGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3ExtensionPageHostGateInput
    var canCreateExtensionPageHostNow: Bool
    var canLoadExtensionPageNow: Bool
    var canInspectExtensionPageNow: Bool
    var pageHostAttempted: Bool
    var pageLoaded: Bool
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productUIExposed: Bool
    var blockers: [ChromeMV3ExtensionPageHostBlocker]
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3ExtensionPageHostGate {
    static func evaluate(
        input: ChromeMV3ExtensionPageHostGateInput
    ) -> ChromeMV3ExtensionPageHostGateDecision {
        var blockers: [ChromeMV3ExtensionPageHostBlocker] = []
        var warnings = input.fixturePolicy.warnings

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }
        if input.explicitInternalExtensionPageHostAllowed == false {
            blockers.append(.explicitHostFlagMissing)
        }
        if input.explicitSyntheticWebViewCreationAllowed == false {
            blockers.append(.explicitSyntheticWebViewCreationMissing)
        }
        if input.explicitSyntheticNavigationAllowed == false {
            blockers.append(.explicitSyntheticNavigationMissing)
        }
        if input.fixturePolicy.fixturePagePolicyPassed == false {
            blockers.append(.fixturePolicyFailed)
        }
        if input.acceptedWebExtensionObjectAvailable == false {
            blockers.append(.acceptedExtensionObjectUnavailable)
        }
        if input.detachedContextAvailable == false {
            blockers.append(.detachedContextMissing)
        }

        if input.controllerLoadGateDecision == nil
            && input.controllerLoadOwnerDiagnostics == nil
        {
            blockers.append(.controllerLoadStateUnavailable)
        }
        if input.controllerLoadGateDecision?.loadAttemptAllowed == false {
            blockers.append(.controllerLoadGateBlocked)
        }
        if input.loadedContextAvailable == false
            || input.controllerLoadOwnerDiagnostics?
            .contextLoadedIntoController != true
        {
            blockers.append(.contextLoadUnavailable)
        }
        if input.sameControllerConfigurationAvailable == false {
            blockers.append(.sameControllerConfigurationUnavailable)
        }
        if input.syntheticConfigurationUserScriptCount > 0 {
            blockers.append(.syntheticConfigurationHasUserScripts)
        }

        let readiness = input.runtimeBridgeReadinessReport
        let jsBridge = readiness?.jsBridgeContractReportSummary
        if isEnabled(jsBridge?.jsBridgeAvailableNow)
            || isEnabled(jsBridge?.exposedToJSNow)
            || isEnabled(jsBridge?.canInjectScriptsNow)
        {
            blockers.append(.jsBridgeExposed)
        }
        if isEnabled(
            readiness?.serviceWorkerLifecycleReportSummary?
                .canWakeServiceWorkerNow
        )
            || isEnabled(
                readiness?.serviceWorkerLifecycleGate
                    .serviceWorkerWakeImplemented
            )
            || (input.controllerLoadOwnerDiagnostics?
                .serviceWorkerWakeCount ?? 0) > 0
            || input.requestedServiceWorkerWake
        {
            blockers.append(.serviceWorkerWakeAvailable)
        }
        if isEnabled(readiness?.messagingGate.dispatchImplemented)
            || input.requestedRuntimeDispatch
        {
            blockers.append(.runtimeDispatchAvailable)
        }
        if isEnabled(
            readiness?.nativeMessagingGate
                .nativeMessagingRuntimeImplemented
        )
            || isEnabled(
                readiness?.nativeMessagingGate
                    .processLaunchImplemented
            )
            || isEnabled(
                readiness?.nativeMessagingReadinessReportSummary?
                    .processLaunchAllowedNow
            )
            || isEnabled(
                readiness?.nativeMessagingReadinessReportSummary?
                    .canOpenPortNow
            )
            || (input.controllerLoadOwnerDiagnostics?
                .nativeMessagingPortCount ?? 0) > 0
            || input.requestedNativeMessagingLaunch
        {
            blockers.append(.nativeMessagingAvailable)
        }
        if input.requestedProductUI
            || input.requestedToolbarIntegration
            || input.requestedSettingsIntegration
        {
            blockers.append(.productUIPathRequested)
        }

        if isEnabled(input.runtimeBridgeReadinessReport?.runtimeLoadable)
            || isEnabled(input.controllerLoadOwnerDiagnostics?.runtimeLoadable)
            || isEnabled(
                input.controllerLoadOwnerDiagnostics?
                    .chromeRuntimeAvailableNow
            )
            || isEnabled(
                input.controllerLoadOwnerDiagnostics?
                    .jsBridgeAvailableNow
            )
            || isEnabled(input.controllerLoadGateDecision?.runtimeLoadable)
            || isEnabled(
                input.controllerLoadGateDecision?
                    .chromeRuntimeAvailableNow
            )
            || isEnabled(
                input.controllerLoadGateDecision?
                    .jsBridgeAvailableNow
            )
        {
            blockers.append(.runtimeLoadabilityInvariantViolation)
        }

        if input.explicitTestDOMInspectionAllowed == false {
            warnings.append(
                "One-shot DOM inspection is skipped unless its explicit DEBUG/internal flag is enabled."
            )
        }
        warnings.append(
            "This host is synthetic and hidden; it is not connected to toolbar, settings, normal tabs, or product UI."
        )

        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        let canCreate = uniqueBlockers.isEmpty
        return ChromeMV3ExtensionPageHostGateDecision(
            input: input,
            canCreateExtensionPageHostNow: canCreate,
            canLoadExtensionPageNow: canCreate,
            canInspectExtensionPageNow:
                canCreate && input.explicitTestDOMInspectionAllowed,
            pageHostAttempted: false,
            pageLoaded: false,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productUIExposed: false,
            blockers: uniqueBlockers,
            blockingReasons:
                uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func isEnabled(_ value: Bool?) -> Bool {
        value ?? false
    }
}

struct ChromeMV3ExtensionPageURLClassification:
    Codable,
    Equatable,
    Sendable
{
    var urlString: String?
    var scheme: String?
    var host: String?
    var path: String?
    var usesExtensionBaseOrigin: Bool
    var remoteNetworkURL: Bool
}

struct ChromeMV3ExtensionPageSyntheticConfigurationResult:
    Codable,
    Equatable,
    Sendable
{
    var configurationCreated: Bool
    var sameControllerConfigurationUsed: Bool
    var configurationSource: String
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var sumiJSBridgeAvailable: Bool
    var blockingReasons: [String]
}

struct ChromeMV3ExtensionPageSyntheticWebViewResult:
    Codable,
    Equatable,
    Sendable
{
    var syntheticWebViewCreated: Bool
    var hidden: Bool
    var userVisibleWindowCreated: Bool
    var productTabRegistered: Bool
    var toolbarIntegrated: Bool
    var settingsIntegrated: Bool
    var sameControllerConfigurationUsed: Bool
    var pageURL: ChromeMV3ExtensionPageURLClassification
    var loadState: ChromeMV3ExtensionPageHostLoadState
    var navigationAttempted: Bool
    var navigationErrorDescription: String?
    var blockingReasons: [String]
    var warnings: [String]
}

struct ChromeMV3ExtensionPageObservationResult:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ExtensionPageObservationState
    var attempted: Bool
    var oneShotOnly: Bool
    var readOnlyDOMInspection: Bool
    var persistentScriptRegistered: Bool
    var scriptMessageHandlerRegistered: Bool
    var jsBridgeUsed: Bool
    var title: String?
    var marker: String?
    var readyState: String?
    var observedURL: String?
    var pageURLClassification:
        ChromeMV3ExtensionPageURLClassification
    var diagnostics: [String]
}

struct ChromeMV3ExtensionPageHostSideEffectCounters:
    Codable,
    Equatable,
    Sendable
{
    var sumiJSInjectionCount: Int
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var serviceWorkerWakeCount: Int
    var runtimeDispatchCount: Int
    var runtimePortCount: Int
    var nativeMessagingPortCount: Int
    var processLaunchCount: Int
    var productUIExposureCount: Int
    var syntheticWebViewCreatedCount: Int
    var pageLoadAttemptCount: Int
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productUIExposed: Bool
}

struct ChromeMV3ExtensionPageHostTeardownResult:
    Codable,
    Equatable,
    Sendable
{
    var syntheticWebViewReleaseRequested: Bool
    var syntheticWebViewReleased: Bool
    var syntheticConfigurationReleaseRequested: Bool
    var syntheticConfigurationReleased: Bool
    var contextOwnerTeardownRequested: Bool
    var controllerOwnerTeardownRequested: Bool
    var generatedArtifactsDeleted: Bool
    var websiteDataCleared: Bool
    var warnings: [String]
}

struct ChromeMV3ExtensionPageHostReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var candidateID: String
    var selectedKind: ChromeMV3ExtensionPageKind
    var canCreateExtensionPageHostNow: Bool
    var canLoadExtensionPageNow: Bool
    var pageHostAttempted: Bool
    var pageLoaded: Bool
    var observationState: ChromeMV3ExtensionPageObservationState
    var runtimeLoadable: Bool
    var productUIExposed: Bool
    var jsBridgeAvailableNow: Bool
}

struct ChromeMV3ExtensionPageHostReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var generatedRewrittenRootPath: String
    var selectedKind: ChromeMV3ExtensionPageKind
    var outcome: ChromeMV3ExtensionPageHostOutcome
    var pageDeclarationSummary: ChromeMV3ExtensionPageDeclarationModel
    var resourceResolverSummary:
        ChromeMV3ExtensionPageResourceResolution?
    var fixturePolicyResult:
        ChromeMV3ExtensionPageFixturePolicyResult
    var hostGateResult: ChromeMV3ExtensionPageHostGateDecision
    var syntheticConfigurationResult:
        ChromeMV3ExtensionPageSyntheticConfigurationResult
    var syntheticWebViewResult:
        ChromeMV3ExtensionPageSyntheticWebViewResult
    var observationResult:
        ChromeMV3ExtensionPageObservationResult
    var sideEffectCounters:
        ChromeMV3ExtensionPageHostSideEffectCounters
    var teardownResult:
        ChromeMV3ExtensionPageHostTeardownResult
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productUIExposed: Bool
    var whyProductSupportRemainsDisabled: [String]
    var blockedOrUnverifiedReasons: [String]
    var warnings: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]

    var summary: ChromeMV3ExtensionPageHostReportSummary {
        ChromeMV3ExtensionPageHostReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            candidateID: candidateID,
            selectedKind: selectedKind,
            canCreateExtensionPageHostNow:
                hostGateResult.canCreateExtensionPageHostNow,
            canLoadExtensionPageNow:
                hostGateResult.canLoadExtensionPageNow,
            pageHostAttempted:
                syntheticWebViewResult.syntheticWebViewCreated,
            pageLoaded:
                syntheticWebViewResult.loadState == .succeeded,
            observationState: observationResult.state,
            runtimeLoadable: false,
            productUIExposed: false,
            jsBridgeAvailableNow: false
        )
    }
}

enum ChromeMV3ExtensionPageHostReportWriter {
    static let reportFileName = "runtime-extension-page-host-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ExtensionPageHostReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ExtensionPageHostReport {
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

enum ChromeMV3ExtensionPageHostReportGenerator {
    static func makeReport(
        candidateID: String,
        generatedRewrittenRootPath: String,
        selectedKind: ChromeMV3ExtensionPageKind,
        declarationModel: ChromeMV3ExtensionPageDeclarationModel,
        fixturePolicy: ChromeMV3ExtensionPageFixturePolicyResult,
        gateDecision: ChromeMV3ExtensionPageHostGateDecision,
        syntheticConfigurationResult:
            ChromeMV3ExtensionPageSyntheticConfigurationResult,
        syntheticWebViewResult:
            ChromeMV3ExtensionPageSyntheticWebViewResult,
        observationResult:
            ChromeMV3ExtensionPageObservationResult,
        teardownResult:
            ChromeMV3ExtensionPageHostTeardownResult
    ) -> ChromeMV3ExtensionPageHostReport {
        let loadAttempted = syntheticWebViewResult.navigationAttempted
        let pageLoaded = syntheticWebViewResult.loadState == .succeeded
        let outcome: ChromeMV3ExtensionPageHostOutcome
        if gateDecision.canCreateExtensionPageHostNow == false {
            outcome = .blocked
        } else if pageLoaded {
            outcome = .loaded
        } else if loadAttempted {
            outcome = .failed
        } else {
            outcome = .attempted
        }
        let blocked = uniqueSorted(
            gateDecision.blockingReasons
                + fixturePolicy.blockingReasons
                + (fixturePolicy.resourceResolution?.blockingReasons ?? [])
                + syntheticWebViewResult.blockingReasons
                + observationResult.diagnostics
        )

        return ChromeMV3ExtensionPageHostReport(
            schemaVersion: 1,
            id: reportID(
                candidateID: candidateID,
                rootPath: generatedRewrittenRootPath,
                selectedKind: selectedKind,
                outcome: outcome,
                loadState: syntheticWebViewResult.loadState
            ),
            reportFileName:
                ChromeMV3ExtensionPageHostReportWriter.reportFileName,
            candidateID: candidateID,
            generatedRewrittenRootPath: generatedRewrittenRootPath,
            selectedKind: selectedKind,
            outcome: outcome,
            pageDeclarationSummary: declarationModel,
            resourceResolverSummary: fixturePolicy.resourceResolution,
            fixturePolicyResult: fixturePolicy,
            hostGateResult: gateDecision,
            syntheticConfigurationResult: syntheticConfigurationResult,
            syntheticWebViewResult: syntheticWebViewResult,
            observationResult: observationResult,
            sideEffectCounters:
                ChromeMV3ExtensionPageHostSideEffectCounters(
                    sumiJSInjectionCount: 0,
                    userScriptCount:
                        syntheticConfigurationResult.userScriptCount,
                    scriptMessageHandlerCount: 0,
                    serviceWorkerWakeCount: 0,
                    runtimeDispatchCount: 0,
                    runtimePortCount: 0,
                    nativeMessagingPortCount: 0,
                    processLaunchCount: 0,
                    productUIExposureCount: 0,
                    syntheticWebViewCreatedCount:
                        syntheticWebViewResult.syntheticWebViewCreated
                            ? 1
                            : 0,
                    pageLoadAttemptCount: loadAttempted ? 1 : 0,
                    runtimeLoadable: false,
                    chromeRuntimeAvailableNow: false,
                    jsBridgeAvailableNow: false,
                    productUIExposed: false
                ),
            teardownResult: teardownResult,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productUIExposed: false,
            whyProductSupportRemainsDisabled: [
                "This is a DEBUG/internal extension page host for deterministic fixture diagnostics only.",
                "No action popup or options page is exposed through product toolbar, settings, URL bar, normal tabs, or extension action UI.",
                "Sumi does not expose a JS bridge, register user scripts, register script message handlers, dispatch extension messages, wake service workers, open ports, launch native messaging, or claim Chrome MV3 runtime support.",
                "runtimeLoadable and productUIExposed remain false.",
            ],
            blockedOrUnverifiedReasons: blocked,
            warnings: uniqueSorted(
                gateDecision.warnings
                    + fixturePolicy.warnings
                    + syntheticWebViewResult.warnings
                    + teardownResult.warnings
            ),
            documentationSources: documentationSources()
        )
    }

    static func blockedConfigurationResult(
        userScriptCount: Int = 0,
        reasons: [String]
    ) -> ChromeMV3ExtensionPageSyntheticConfigurationResult {
        ChromeMV3ExtensionPageSyntheticConfigurationResult(
            configurationCreated: false,
            sameControllerConfigurationUsed: false,
            configurationSource: "unavailable",
            userScriptCount: userScriptCount,
            scriptMessageHandlerCount: 0,
            sumiJSBridgeAvailable: false,
            blockingReasons: uniqueSorted(reasons)
        )
    }

    static func webViewResult(
        created: Bool,
        sameController: Bool,
        pageURL: ChromeMV3ExtensionPageURLClassification,
        loadState: ChromeMV3ExtensionPageHostLoadState,
        navigationAttempted: Bool,
        navigationErrorDescription: String?,
        blockers: [String],
        warnings: [String]
    ) -> ChromeMV3ExtensionPageSyntheticWebViewResult {
        ChromeMV3ExtensionPageSyntheticWebViewResult(
            syntheticWebViewCreated: created,
            hidden: true,
            userVisibleWindowCreated: false,
            productTabRegistered: false,
            toolbarIntegrated: false,
            settingsIntegrated: false,
            sameControllerConfigurationUsed: sameController,
            pageURL: pageURL,
            loadState: loadState,
            navigationAttempted: navigationAttempted,
            navigationErrorDescription: navigationErrorDescription,
            blockingReasons: uniqueSorted(blockers),
            warnings: uniqueSorted(warnings)
        )
    }

    static func observationResult(
        state: ChromeMV3ExtensionPageObservationState,
        attempted: Bool,
        title: String? = nil,
        marker: String? = nil,
        readyState: String? = nil,
        observedURL: String? = nil,
        pageURL:
            ChromeMV3ExtensionPageURLClassification = .notAvailable,
        diagnostics: [String] = []
    ) -> ChromeMV3ExtensionPageObservationResult {
        ChromeMV3ExtensionPageObservationResult(
            state: state,
            attempted: attempted,
            oneShotOnly: true,
            readOnlyDOMInspection: true,
            persistentScriptRegistered: false,
            scriptMessageHandlerRegistered: false,
            jsBridgeUsed: false,
            title: title,
            marker: marker,
            readyState: readyState,
            observedURL: observedURL,
            pageURLClassification: pageURL,
            diagnostics: uniqueSorted(diagnostics)
        )
    }

    static func teardownResult(
        webViewCreated: Bool,
        configurationCreated: Bool,
        contextOwnerTeardownRequested: Bool,
        controllerOwnerTeardownRequested: Bool
    ) -> ChromeMV3ExtensionPageHostTeardownResult {
        ChromeMV3ExtensionPageHostTeardownResult(
            syntheticWebViewReleaseRequested: webViewCreated,
            syntheticWebViewReleased: webViewCreated,
            syntheticConfigurationReleaseRequested: configurationCreated,
            syntheticConfigurationReleased: configurationCreated,
            contextOwnerTeardownRequested: contextOwnerTeardownRequested,
            controllerOwnerTeardownRequested:
                controllerOwnerTeardownRequested,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false,
            warnings: [
                "Extension page host teardown releases only synthetic references; generated artifacts and website data are left untouched.",
            ]
        )
    }

    private static func reportID(
        candidateID: String,
        rootPath: String,
        selectedKind: ChromeMV3ExtensionPageKind,
        outcome: ChromeMV3ExtensionPageHostOutcome,
        loadState: ChromeMV3ExtensionPageHostLoadState
    ) -> String {
        let input = [
            candidateID,
            rootPath,
            selectedKind.rawValue,
            outcome.rawValue,
            loadState.rawValue,
        ].joined(separator: "|")
        return chromeMV3ExtensionPageSHA256(Data(input.utf8))
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "chromeDocumentation",
                title: "chrome.action",
                url: "https://developer.chrome.com/docs/extensions/reference/api/action",
                note: "Chrome declares action.default_popup as extension-owned popup HTML. Sumi does not expose product action UI here."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Extension options pages",
                url: "https://developer.chrome.com/docs/extensions/develop/ui/options-page",
                note: "Chrome declares options_page and options_ui.page as extension-owned options pages. Sumi does not expose product options UI here."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Manifest content security policy",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-security-policy",
                note: "Chrome extension pages are constrained to local extension resources by CSP; this fixture resolver rejects remote resources."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Web accessible resources",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/web-accessible-resources",
                note: "Only extension-origin pages/scripts can access extension resources by default; this host does not broaden web_accessible_resources."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebViewConfiguration.webExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller",
                note: "The synthetic page configuration must use the same WKWebExtensionController as the loaded context."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController.load(_:)",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/load(_:)",
                note: "Controller load remains owned by the existing controller-load owner; this page host only consumes loaded-context diagnostics."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionContext.webViewConfiguration",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontext/webviewconfiguration",
                note: "Apple requires the extension context configuration for WebViews navigating to the extension base URL."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebView initialization and loading",
                url: "https://developer.apple.com/documentation/webkit/wkwebview",
                note: "WKWebView is initialized with a WKWebViewConfiguration and loads a URLRequest; this harness keeps it hidden and synthetic."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX WebKit headers",
                url: nil,
                note: "Local headers document that extension page navigation requires a loaded context and its webViewConfiguration."
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

extension ChromeMV3ExtensionPageURLClassification {
    static var notAvailable: ChromeMV3ExtensionPageURLClassification {
        ChromeMV3ExtensionPageURLClassification(
            urlString: nil,
            scheme: nil,
            host: nil,
            path: nil,
            usesExtensionBaseOrigin: false,
            remoteNetworkURL: false
        )
    }

    static func classify(
        url: URL?,
        extensionBaseURL: URL?
    ) -> ChromeMV3ExtensionPageURLClassification {
        guard let url else { return .notAvailable }
        let remote = url.scheme == "http" || url.scheme == "https"
        let sameOrigin =
            url.scheme == extensionBaseURL?.scheme
                && url.host == extensionBaseURL?.host
        return ChromeMV3ExtensionPageURLClassification(
            urlString: url.absoluteString,
            scheme: url.scheme,
            host: url.host,
            path: url.path,
            usesExtensionBaseOrigin: sameOrigin,
            remoteNetworkURL: remote
        )
    }
}

enum ChromeMV3ExtensionPageResourcePath {
    static func normalize(
        _ rawPath: String,
        relativeTo pageDirectory: String? = nil
    ) -> ChromeMV3ExtensionPagePathNormalization {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure("Extension page resource path is empty.")
        }
        if isRemote(trimmed) {
            return .failure("Extension page resource path is remote: \(rawPath)")
        }
        let pathBeforeFragment = trimmed.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? trimmed
        let pathOnly = pathBeforeFragment.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? pathBeforeFragment
        let decoded = pathOnly.removingPercentEncoding ?? pathOnly
        let candidate: String
        if let pageDirectory,
           pageDirectory.isEmpty == false,
           decoded.hasPrefix("/") == false
        {
            candidate = pageDirectory + "/" + decoded
        } else {
            candidate = decoded
        }
        guard
            candidate.hasPrefix("/") == false,
            candidate.hasPrefix("~") == false,
            candidate.contains("\\") == false,
            candidate.contains("\0") == false,
            candidate.localizedCaseInsensitiveContains("://") == false,
            candidate.contains("*") == false
        else {
            return .failure(
                "Extension page resource path is unsafe: \(rawPath)"
            )
        }

        let segments = candidate.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard
            segments.isEmpty == false,
            segments.allSatisfy({ segment in
                segment.isEmpty == false
                    && segment != "."
                    && segment != ".."
            })
        else {
            return .failure(
                "Extension page resource path escapes the generated bundle: \(rawPath)"
            )
        }
        return .success(candidate)
    }

    static func resourceURL(
        normalizedRelativePath: String,
        rootURL: URL
    ) -> URL? {
        let rootURL = rootURL.standardizedFileURL
        let url = rootURL
            .appendingPathComponent(normalizedRelativePath)
            .standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/")
            ? rootURL.path
            : rootURL.path + "/"
        guard url.path.hasPrefix(rootPath) else { return nil }
        return url
    }

    static func isRemote(_ value: String) -> Bool {
        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://")
            || lowered.hasPrefix("//")
            || lowered.hasPrefix("data:")
            || lowered.hasPrefix("blob:")
    }
}

private func chromeMV3ExtensionPageSHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSorted<T: Hashable & Comparable>(_ values: [T]) -> [T] {
    Array(Set(values)).sorted()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

#if DEBUG
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3ExtensionPageNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var awaitedNavigation: WKNavigation?
    private var completion: ChromeMV3ExtensionPageNavigationCompletion?
    private var continuation:
        CheckedContinuation<
            ChromeMV3ExtensionPageNavigationCompletion,
            Never
        >?

    func waitForCompletion(
        navigation: WKNavigation?
    ) async -> ChromeMV3ExtensionPageNavigationCompletion {
        guard let navigation else {
            return .notStarted
        }
        awaitedNavigation = navigation
        if let completion {
            return completion
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        guard isAwaited(navigation) else { return }
        finish(
            ChromeMV3ExtensionPageNavigationCompletion(
                state: .succeeded,
                errorDescription: nil
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        guard isAwaited(navigation) else { return }
        finish(
            ChromeMV3ExtensionPageNavigationCompletion(
                state: .failed,
                errorDescription: error.localizedDescription
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        guard isAwaited(navigation) else { return }
        finish(
            ChromeMV3ExtensionPageNavigationCompletion(
                state: .failed,
                errorDescription: error.localizedDescription
            )
        )
    }

    private func isAwaited(_ navigation: WKNavigation?) -> Bool {
        guard let awaitedNavigation else { return true }
        return navigation === awaitedNavigation
    }

    private func finish(
        _ completion: ChromeMV3ExtensionPageNavigationCompletion
    ) {
        guard self.completion == nil else { return }
        self.completion = completion
        continuation?.resume(returning: completion)
        continuation = nil
    }
}

private struct ChromeMV3ExtensionPageNavigationCompletion {
    var state: ChromeMV3ExtensionPageHostLoadState
    var errorDescription: String?

    static let notStarted = ChromeMV3ExtensionPageNavigationCompletion(
        state: .notAttempted,
        errorDescription: nil
    )
}

@available(macOS 15.5, *)
enum ChromeMV3ExtensionPageHostHarness {
    @MainActor
    static func run(
        candidate: ChromeMV3RewrittenVariantCandidate,
        selectedKind: ChromeMV3ExtensionPageKind,
        extensionsModuleEnabled: Bool,
        explicitInternalExtensionPageHostAllowed: Bool,
        explicitSyntheticWebViewCreationAllowed: Bool,
        explicitSyntheticNavigationAllowed: Bool,
        explicitTestDOMInspectionAllowed: Bool,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport?,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?,
        emptyControllerOwner:
            ChromeMV3EmptyControllerOwner?,
        detachedContextOwner:
            ChromeMV3DetachedContextOwner?,
        controllerLoadOwner:
            ChromeMV3ControllerLoadOwner?,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        tearDownLoadedContextAndControllerAfterRun: Bool = false
    ) async -> ChromeMV3ExtensionPageHostReport {
        let rootURL = URL(
            fileURLWithPath: candidate.rewrittenVariantRootPath,
            isDirectory: true
        ).standardizedFileURL
        let declarationModel = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: rootURL.path
        )
        let fixturePolicy = ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: declarationModel,
            selectedKind: selectedKind
        )

        let controller = emptyControllerOwner?.controller
        let context = detachedContextOwner?.detachedContext
        let loadDiagnostics = controllerLoadOwner?.diagnostics()
        let contextLoaded =
            loadDiagnostics?.contextLoadedIntoController ?? false
        let loadedContext =
            contextLoaded
                && context?.webExtensionController === controller
        let contextConfiguration = loadedContext
            ? context?.webViewConfiguration
            : nil
        let sameControllerConfiguration =
            contextConfiguration?.webExtensionController === controller
        let userScriptCount =
            contextConfiguration?.userContentController.userScripts.count
                ?? 0
        let accepted =
            objectAcceptanceReport?.objectAcceptedByWebKit == true

        let gateInput = ChromeMV3ExtensionPageHostGateInput(
            candidateID: candidate.id,
            generatedRewrittenRootPath: rootURL.path,
            selectedKind: selectedKind,
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitInternalExtensionPageHostAllowed:
                explicitInternalExtensionPageHostAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            explicitSyntheticNavigationAllowed:
                explicitSyntheticNavigationAllowed,
            explicitTestDOMInspectionAllowed:
                explicitTestDOMInspectionAllowed,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextAvailable: context != nil,
            controllerLoadGateDecision:
                loadDiagnostics?.gateDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            loadedContextAvailable: loadedContext,
            sameControllerConfigurationAvailable:
                sameControllerConfiguration,
            syntheticConfigurationUserScriptCount: userScriptCount,
            fixturePolicy: fixturePolicy,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            requestedProductUI: false,
            requestedToolbarIntegration: false,
            requestedSettingsIntegration: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedNativeMessagingLaunch: false
        )
        let gateDecision = ChromeMV3ExtensionPageHostGate.evaluate(
            input: gateInput
        )

        guard gateDecision.canCreateExtensionPageHostNow,
              let context,
              let configuration = contextConfiguration,
              let pageURL = extensionPageURL(
                context: context,
                resolution: fixturePolicy.resourceResolution
              )
        else {
            let pageURL = ChromeMV3ExtensionPageURLClassification
                .notAvailable
            return ChromeMV3ExtensionPageHostReportGenerator.makeReport(
                candidateID: candidate.id,
                generatedRewrittenRootPath: rootURL.path,
                selectedKind: selectedKind,
                declarationModel: declarationModel,
                fixturePolicy: fixturePolicy,
                gateDecision: gateDecision,
                syntheticConfigurationResult:
                    ChromeMV3ExtensionPageHostReportGenerator
                    .blockedConfigurationResult(
                        userScriptCount: userScriptCount,
                        reasons: gateDecision.blockingReasons
                    ),
                syntheticWebViewResult:
                    ChromeMV3ExtensionPageHostReportGenerator.webViewResult(
                        created: false,
                        sameController: false,
                        pageURL: pageURL,
                        loadState: .blocked,
                        navigationAttempted: false,
                        navigationErrorDescription: nil,
                        blockers: gateDecision.blockingReasons,
                        warnings: gateDecision.warnings
                    ),
                observationResult:
                    ChromeMV3ExtensionPageHostReportGenerator
                    .observationResult(
                        state: .blocked,
                        attempted: false,
                        pageURL: pageURL,
                        diagnostics: gateDecision.blockingReasons
                    ),
                teardownResult:
                    ChromeMV3ExtensionPageHostReportGenerator.teardownResult(
                        webViewCreated: false,
                        configurationCreated: false,
                        contextOwnerTeardownRequested: false,
                        controllerOwnerTeardownRequested: false
                    )
            )
        }

        var syntheticConfiguration: WKWebViewConfiguration? =
            configuration
        syntheticConfiguration?
            .sumiIsNormalTabWebViewConfiguration = false
        let configurationSameController =
            syntheticConfiguration?.webExtensionController === controller
        let configurationUserScriptCount =
            syntheticConfiguration?.userContentController.userScripts.count
                ?? 0
        let configurationResult =
            ChromeMV3ExtensionPageSyntheticConfigurationResult(
                configurationCreated: syntheticConfiguration != nil,
                sameControllerConfigurationUsed:
                    configurationSameController,
                configurationSource:
                    "WKWebExtensionContext.webViewConfiguration",
                userScriptCount: configurationUserScriptCount,
                scriptMessageHandlerCount: 0,
                sumiJSBridgeAvailable: false,
                blockingReasons: []
            )

        var syntheticWebView: WKWebView?
        var navigationObserver:
            ChromeMV3ExtensionPageNavigationObserver?
        var navigationCompletion =
            ChromeMV3ExtensionPageNavigationCompletion.notStarted
        let pageURLClassification =
            ChromeMV3ExtensionPageURLClassification.classify(
                url: pageURL,
                extensionBaseURL: context.baseURL
            )

        if gateDecision.canLoadExtensionPageNow,
           configurationSameController,
           let syntheticConfiguration
        {
            let webView = WKWebView(
                frame: .zero,
                configuration: syntheticConfiguration
            )
            syntheticWebView = webView
            navigationObserver = ChromeMV3ExtensionPageNavigationObserver()
            webView.navigationDelegate = navigationObserver
            let loadPage: (URLRequest) -> WKNavigation? = webView.load
            let navigation = loadPage(URLRequest(url: pageURL))
            navigationCompletion =
                await navigationObserver?.waitForCompletion(
                    navigation: navigation
                ) ?? .notStarted
        }

        let webViewResult =
            ChromeMV3ExtensionPageHostReportGenerator.webViewResult(
                created: syntheticWebView != nil,
                sameController:
                    syntheticWebView?.configuration.webExtensionController
                        === controller,
                pageURL: pageURLClassification,
                loadState: navigationCompletion.state,
                navigationAttempted:
                    navigationCompletion.state != .notAttempted,
                navigationErrorDescription:
                    navigationCompletion.errorDescription,
                blockers:
                    navigationCompletion.state == .failed
                        ? [
                            navigationCompletion.errorDescription
                                ?? "Extension page navigation failed.",
                        ]
                        : [],
                warnings: [
                    "Synthetic WKWebView was hidden and not registered as a product tab.",
                ]
            )

        let observation: ChromeMV3ExtensionPageObservationResult
        if gateDecision.canInspectExtensionPageNow,
           navigationCompletion.state == .succeeded,
           let syntheticWebView
        {
            observation = await inspect(
                webView: syntheticWebView,
                pageURL: pageURLClassification
            )
        } else {
            observation =
                ChromeMV3ExtensionPageHostReportGenerator
                .observationResult(
                    state:
                        gateDecision.canInspectExtensionPageNow
                            ? .blocked
                            : .notAttempted,
                    attempted: false,
                    pageURL: pageURLClassification,
                    diagnostics:
                        gateDecision.canInspectExtensionPageNow
                            ? [
                                "Page observation is blocked because navigation did not finish.",
                            ]
                            : [
                                "One-shot page observation was not requested.",
                            ]
                )
        }

        syntheticWebView?.navigationDelegate = nil
        syntheticWebView = nil
        syntheticConfiguration = nil

        let loadTeardown: ChromeMV3ControllerLoadOwnerDiagnostics?
        let detachedTeardown: ChromeMV3DetachedContextOwnerDiagnostics?
        let controllerTeardown: ChromeMV3EmptyControllerDiagnostics?
        if tearDownLoadedContextAndControllerAfterRun {
            loadTeardown = controllerLoadOwner?.tearDown()
            detachedTeardown = detachedContextOwner?.tearDown()
            controllerTeardown = emptyControllerOwner?.tearDown(
                trigger: .explicitReset
            )
        } else {
            loadTeardown = nil
            detachedTeardown = nil
            controllerTeardown = nil
        }

        return ChromeMV3ExtensionPageHostReportGenerator.makeReport(
            candidateID: candidate.id,
            generatedRewrittenRootPath: rootURL.path,
            selectedKind: selectedKind,
            declarationModel: declarationModel,
            fixturePolicy: fixturePolicy,
            gateDecision: gateDecision,
            syntheticConfigurationResult: configurationResult,
            syntheticWebViewResult: webViewResult,
            observationResult: observation,
            teardownResult:
                ChromeMV3ExtensionPageHostReportGenerator.teardownResult(
                    webViewCreated:
                        webViewResult.syntheticWebViewCreated,
                    configurationCreated:
                        configurationResult.configurationCreated,
                    contextOwnerTeardownRequested:
                        detachedTeardown != nil || loadTeardown != nil,
                    controllerOwnerTeardownRequested:
                        controllerTeardown != nil
                )
        )
    }

    @MainActor
    private static func extensionPageURL(
        context: WKWebExtensionContext,
        resolution: ChromeMV3ExtensionPageResourceResolution?
    ) -> URL? {
        guard let path = resolution?.declaration.normalizedPath else {
            return nil
        }
        var components = URLComponents(
            url: context.baseURL,
            resolvingAgainstBaseURL: false
        )
        components?.path = "/" + path
        return components?.url
    }

    private static func inspect(
        webView: WKWebView,
        pageURL: ChromeMV3ExtensionPageURLClassification
    ) async -> ChromeMV3ExtensionPageObservationResult {
        let script = """
        JSON.stringify({
          title: document.title || "",
          marker: (document.querySelector("[data-sumi-extension-page-fixture-marker]") || {}).dataset?.sumiExtensionPageFixtureMarker || null,
          readyState: document.readyState || "",
          url: location.href || ""
        })
        """
        do {
            let json = try await evaluate(script: script, webView: webView)
            let snapshot = decodeObservation(json)
            return ChromeMV3ExtensionPageHostReportGenerator
                .observationResult(
                    state: .succeeded,
                    attempted: true,
                    title: snapshot.title,
                    marker: snapshot.marker,
                    readyState: snapshot.readyState,
                    observedURL: snapshot.url,
                    pageURL: pageURL
                )
        } catch {
            return ChromeMV3ExtensionPageHostReportGenerator
                .observationResult(
                    state: .failed,
                    attempted: true,
                    pageURL: pageURL,
                    diagnostics: [error.localizedDescription]
                )
        }
    }

    @MainActor
    private static func evaluate(
        script: String,
        webView: WKWebView
    ) async throws -> String {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            webView.evaluateJavaScript(script, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let string = value as? String {
                        continuation.resume(returning: string)
                    } else {
                        continuation.resume(
                            throwing: NSError(
                                domain:
                                    "Sumi.ChromeMV3ExtensionPageObservation",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "DOM inspection did not return JSON.",
                                ]
                            )
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func decodeObservation(
        _ json: String
    ) -> (title: String?, marker: String?, readyState: String?, url: String?) {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return (nil, nil, nil, nil)
        }
        return (
            object["title"] as? String,
            object["marker"] as? String,
            object["readyState"] as? String,
            object["url"] as? String
        )
    }
}
#endif
