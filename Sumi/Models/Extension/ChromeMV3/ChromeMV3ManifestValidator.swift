//
//  ChromeMV3ManifestValidator.swift
//  Sumi
//
//  Pure install-time validation for unpacked Chrome MV3 manifests.
//

import CryptoKit
import Foundation

enum ChromeMV3ManifestValidationError: LocalizedError, CustomStringConvertible, Equatable {
    case missingManifest(String)
    case invalidJSON(String)
    case invalidJSONStructure
    case missingManifestVersion
    case invalidManifestVersion
    case unsupportedManifestVersion(Int)
    case missingName
    case missingVersion
    case backgroundPageUnsupported
    case backgroundScriptsUnsupported
    case backgroundPersistenceUnsupported
    case unsafeResourcePath(field: String, path: String)
    case unsupportedSafariPackageInput(String)
    case unsupportedArchiveInspection(ChromeMV3PackageSourceKind)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let path):
            return "Missing manifest.json at \(path)"
        case .invalidJSON(let reason):
            return "Invalid manifest.json: \(reason)"
        case .invalidJSONStructure:
            return "Invalid manifest.json: top-level value must be an object"
        case .missingManifestVersion:
            return "Invalid manifest.json: Missing manifest_version"
        case .invalidManifestVersion:
            return "Invalid manifest.json: manifest_version must be an integer"
        case .unsupportedManifestVersion(let version):
            return "Unsupported extension manifest: Sumi supports manifest_version 3 only (found \(version))"
        case .missingName:
            return "Invalid manifest.json: Missing name"
        case .missingVersion:
            return "Invalid manifest.json: Missing version"
        case .backgroundPageUnsupported:
            return "Unsupported extension manifest: Background pages are not supported"
        case .backgroundScriptsUnsupported:
            return "Unsupported extension manifest: Background scripts are not supported"
        case .backgroundPersistenceUnsupported:
            return "Unsupported extension manifest: MV2 background persistence is not supported"
        case .unsafeResourcePath(let field, let path):
            return "Invalid manifest.json: Unsafe resource path '\(path)' in \(field)"
        case .unsupportedSafariPackageInput(let path):
            return "Unsupported extension package: Safari .app/.appex inputs are not Chrome MV3 sources (\(path))"
        case .unsupportedArchiveInspection(let sourceKind):
            return "Unsupported extension package: \(sourceKind.rawValue) inspection is deferred until archive import is implemented"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

enum ChromeMV3ManifestValidator {
    static func validatePackage(
        at packageURL: URL,
        sourceKind: ChromeMV3PackageSourceKind
    ) throws -> ChromeMV3Manifest {
        try rejectSafariPackageInput(packageURL)

        switch sourceKind {
        case .unpackedDirectory:
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: packageURL.path,
                    isDirectory: &isDirectory
                ),
                isDirectory.boolValue
            else {
                throw ChromeMV3ManifestValidationError.missingManifest(
                    packageURL.appendingPathComponent("manifest.json").path
                )
            }
            return try validateManifestFile(
                at: packageURL.appendingPathComponent("manifest.json")
            )
        case .zipArchive, .crxArchive:
            throw ChromeMV3ManifestValidationError.unsupportedArchiveInspection(
                sourceKind
            )
        }
    }

    static func validateManifestFile(at manifestURL: URL) throws -> ChromeMV3Manifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ChromeMV3ManifestValidationError.missingManifest(manifestURL.path)
        }

        let object = try loadJSONObject(at: manifestURL)
        return try validateJSONObject(object)
    }

    static func validateJSONObject(_ object: [String: Any]) throws -> ChromeMV3Manifest {
        guard object.keys.contains("manifest_version") else {
            throw ChromeMV3ManifestValidationError.missingManifestVersion
        }

        guard let manifestVersion = intValue(object["manifest_version"]) else {
            throw ChromeMV3ManifestValidationError.invalidManifestVersion
        }

        guard manifestVersion == 3 else {
            throw ChromeMV3ManifestValidationError.unsupportedManifestVersion(
                manifestVersion
            )
        }

        guard let name = stringValue(object["name"]), name.isEmpty == false else {
            throw ChromeMV3ManifestValidationError.missingName
        }

        guard let version = stringValue(object["version"]), version.isEmpty == false else {
            throw ChromeMV3ManifestValidationError.missingVersion
        }

        try validateMV3Background(in: object)
        try validateDeclaredResourcePaths(in: object)

        return ChromeMV3Manifest(
            manifestVersion: manifestVersion,
            name: name,
            version: version,
            description: stringValue(object["description"]),
            background: parseBackground(object["background"]),
            permissions: stringArray(object["permissions"]).sorted(),
            optionalPermissions: stringArray(object["optional_permissions"]).sorted(),
            hostPermissions: stringArray(object["host_permissions"]).sorted(),
            optionalHostPermissions:
                stringArray(object["optional_host_permissions"]).sorted(),
            contentScripts: parseContentScripts(object["content_scripts"]),
            action: parseAction(object["action"]),
            optionsPage: stringValue(object["options_page"]),
            optionsUI: parseOptionsUI(object["options_ui"]),
            webAccessibleResources: parseWebAccessibleResources(
                object["web_accessible_resources"]
            ),
            externallyConnectable: parseExternallyConnectable(
                object["externally_connectable"]
            ),
            declarativeNetRequest: parseDeclarativeNetRequest(
                object["declarative_net_request"]
            ),
            sidePanel: parseSidePanel(object["side_panel"]),
            oauth2: parseOAuth2(object["oauth2"]),
            commands: parseCommands(object["commands"]),
            minimumChromeVersion: stringValue(object["minimum_chrome_version"]),
            browserSpecificSettings: parseJSONValueObject(
                object["browser_specific_settings"]
            ),
            devtoolsPage: stringValue(object["devtools_page"]),
            topLevelKeys: object.keys.sorted()
        )
    }

    static func packageMetadata(
        for packageURL: URL,
        sourceKind: ChromeMV3PackageSourceKind,
        manifestURL: URL? = nil,
        manifest: ChromeMV3Manifest? = nil
    ) -> ChromeMV3PackageMetadata {
        let manifestHash = manifestURL.flatMap { sha256(fileAt: $0) }
        return ChromeMV3PackageMetadata(
            extensionIdentity: ChromeMV3ExtensionIdentity(
                id: nil,
                derivationInput: manifestHash
                    ?? packageURL.standardizedFileURL.path
            ),
            originalBundlePath: packageURL.standardizedFileURL.path,
            originalBundleLastPathComponent: packageURL.lastPathComponent,
            sourceKind: sourceKind,
            generatedBundlePath: nil,
            installDate: nil,
            installedVersion: manifest?.version,
            sourceSHA256: sourceKind == .unpackedDirectory
                ? nil
                : sha256(fileAt: packageURL),
            manifestSHA256: manifestHash
        )
    }

    private static func loadJSONObject(at url: URL) throws -> [String: Any] {
        do {
            let data = try Data(contentsOf: url)
            let rawObject = try JSONSerialization.jsonObject(with: data)
            guard let object = rawObject as? [String: Any] else {
                throw ChromeMV3ManifestValidationError.invalidJSONStructure
            }
            return object
        } catch let error as ChromeMV3ManifestValidationError {
            throw error
        } catch {
            throw ChromeMV3ManifestValidationError.invalidJSON(
                error.localizedDescription
            )
        }
    }

    private static func rejectSafariPackageInput(_ url: URL) throws {
        let pathExtension = url.pathExtension.lowercased()
        guard pathExtension == "app" || pathExtension == "appex" else { return }
        throw ChromeMV3ManifestValidationError.unsupportedSafariPackageInput(
            url.path
        )
    }

    private static func validateMV3Background(in object: [String: Any]) throws {
        guard let background = object["background"] as? [String: Any] else {
            return
        }

        if background.keys.contains("page") {
            throw ChromeMV3ManifestValidationError.backgroundPageUnsupported
        }

        if background.keys.contains("scripts") {
            throw ChromeMV3ManifestValidationError.backgroundScriptsUnsupported
        }

        if background.keys.contains("persistent") {
            throw ChromeMV3ManifestValidationError.backgroundPersistenceUnsupported
        }
    }

    private static func validateDeclaredResourcePaths(
        in object: [String: Any]
    ) throws {
        if let background = object["background"] as? [String: Any] {
            try validatePath(
                stringValue(background["service_worker"]),
                field: "background.service_worker"
            )
        }

        if let contentScripts = object["content_scripts"] as? [[String: Any]] {
            for (index, script) in contentScripts.enumerated() {
                for path in stringArray(script["js"]) {
                    try validatePath(
                        path,
                        field: "content_scripts[\(index)].js"
                    )
                }
                for path in stringArray(script["css"]) {
                    try validatePath(
                        path,
                        field: "content_scripts[\(index)].css"
                    )
                }
            }
        }

        try validatePath(stringValue(object["options_page"]), field: "options_page")

        if let optionsUI = object["options_ui"] as? [String: Any] {
            try validatePath(
                stringValue(optionsUI["page"]),
                field: "options_ui.page"
            )
        }

        if let action = object["action"] as? [String: Any] {
            try validatePath(
                stringValue(action["default_popup"]),
                field: "action.default_popup"
            )
            for path in iconPaths(action["default_icon"]) {
                try validatePath(
                    path,
                    field: "action.default_icon",
                    allowsRootRelative: true
                )
            }
        }

        if let icons = object["icons"] as? [String: Any] {
            for path in iconPaths(icons) {
                try validatePath(path, field: "icons", allowsRootRelative: true)
            }
        }

        if let resources = object["web_accessible_resources"] as? [[String: Any]] {
            for (index, entry) in resources.enumerated() {
                for path in stringArray(entry["resources"]) {
                    try validatePath(
                        path,
                        field: "web_accessible_resources[\(index)].resources",
                        allowsGlob: true
                    )
                }
            }
        }

        if let dnr = object["declarative_net_request"] as? [String: Any],
           let ruleResources = dnr["rule_resources"] as? [[String: Any]]
        {
            for (index, resource) in ruleResources.enumerated() {
                try validatePath(
                    stringValue(resource["path"]),
                    field: "declarative_net_request.rule_resources[\(index)].path"
                )
            }
        }

        if let sidePanel = object["side_panel"] as? [String: Any] {
            try validatePath(
                stringValue(sidePanel["default_path"]),
                field: "side_panel.default_path"
            )
        }

        try validatePath(stringValue(object["devtools_page"]), field: "devtools_page")
    }

    private static func validatePath(
        _ path: String?,
        field: String,
        allowsGlob: Bool = false,
        allowsRootRelative: Bool = false
    ) throws {
        guard let path else { return }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ChromeMV3ManifestValidationError.unsafeResourcePath(
                field: field,
                path: path
            )
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
        let normalizedDecoded =
            decoded.hasPrefix("/") && decoded.hasPrefix("//") == false
            ? String(decoded.dropFirst())
            : decoded
        let pathForSegments = allowsRootRelative ? normalizedDecoded : decoded
        let isUnsafe = (decoded.hasPrefix("/") && allowsRootRelative == false)
            || decoded.hasPrefix("//")
            || decoded.hasPrefix("~")
            || decoded.contains("\\")
            || decoded.contains("\0")
            || decoded.localizedCaseInsensitiveContains("://")
            || (!allowsGlob && pathForSegments.contains("*"))

        guard isUnsafe == false else {
            throw ChromeMV3ManifestValidationError.unsafeResourcePath(
                field: field,
                path: path
            )
        }

        let segments = pathForSegments.split(
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
            throw ChromeMV3ManifestValidationError.unsafeResourcePath(
                field: field,
                path: path
            )
        }
    }

    private static func parseBackground(_ value: Any?) -> ChromeMV3Background? {
        guard let object = value as? [String: Any] else { return nil }
        return ChromeMV3Background(
            serviceWorker: stringValue(object["service_worker"]),
            type: stringValue(object["type"])
        )
    }

    private static func parseContentScripts(_ value: Any?) -> [ChromeMV3ContentScript] {
        guard let scripts = value as? [[String: Any]] else { return [] }
        return scripts.map { script in
            ChromeMV3ContentScript(
                matches: stringArray(script["matches"]).sorted(),
                excludeMatches: stringArray(script["exclude_matches"]).sorted(),
                includeGlobs: stringArray(script["include_globs"]).sorted(),
                excludeGlobs: stringArray(script["exclude_globs"]).sorted(),
                js: stringArray(script["js"]),
                css: stringArray(script["css"]),
                allFrames: boolValue(script["all_frames"]) ?? false,
                matchAboutBlank: boolValue(script["match_about_blank"]) ?? false,
                matchOriginAsFallback: boolValue(script["match_origin_as_fallback"]) ?? false,
                runAt: stringValue(script["run_at"]),
                world: stringValue(script["world"])
            )
        }
    }

    private static func parseAction(_ value: Any?) -> ChromeMV3Action? {
        guard let action = value as? [String: Any] else { return nil }
        return ChromeMV3Action(
            defaultPopup: stringValue(action["default_popup"]),
            defaultTitle: stringValue(action["default_title"]),
            defaultIconPaths: iconPathMap(action["default_icon"])
        )
    }

    private static func parseOptionsUI(_ value: Any?) -> ChromeMV3OptionsUI? {
        guard let optionsUI = value as? [String: Any] else { return nil }
        return ChromeMV3OptionsUI(
            page: stringValue(optionsUI["page"]),
            openInTab: boolValue(optionsUI["open_in_tab"])
        )
    }

    private static func parseWebAccessibleResources(
        _ value: Any?
    ) -> [ChromeMV3WebAccessibleResource] {
        guard let resources = value as? [[String: Any]] else { return [] }
        return resources.map { entry in
            ChromeMV3WebAccessibleResource(
                resources: stringArray(entry["resources"]).sorted(),
                matches: stringArray(entry["matches"]).sorted(),
                extensionIDs: stringArray(entry["extension_ids"]).sorted(),
                useDynamicURL: boolValue(entry["use_dynamic_url"])
            )
        }
    }

    private static func parseExternallyConnectable(
        _ value: Any?
    ) -> ChromeMV3ExternallyConnectable? {
        guard let object = value as? [String: Any] else { return nil }
        return ChromeMV3ExternallyConnectable(
            ids: stringArray(object["ids"]).sorted(),
            matches: stringArray(object["matches"]).sorted(),
            acceptsTLSChannelID: boolValue(object["accepts_tls_channel_id"])
        )
    }

    private static func parseDeclarativeNetRequest(
        _ value: Any?
    ) -> ChromeMV3DeclarativeNetRequest? {
        guard let object = value as? [String: Any] else { return nil }
        let resources = (object["rule_resources"] as? [[String: Any]] ?? []).map {
            ChromeMV3DeclarativeNetRequestRuleResource(
                id: stringValue($0["id"]),
                enabled: boolValue($0["enabled"]),
                path: stringValue($0["path"])
            )
        }
        return ChromeMV3DeclarativeNetRequest(ruleResources: resources)
    }

    private static func parseSidePanel(_ value: Any?) -> ChromeMV3SidePanel? {
        guard let object = value as? [String: Any] else { return nil }
        return ChromeMV3SidePanel(
            defaultPath: stringValue(object["default_path"])
        )
    }

    private static func parseOAuth2(_ value: Any?) -> ChromeMV3OAuth2? {
        guard let object = value as? [String: Any] else { return nil }
        return ChromeMV3OAuth2(
            clientID: stringValue(object["client_id"]),
            scopes: stringArray(object["scopes"]).sorted()
        )
    }

    private static func parseCommands(_ value: Any?) -> [String: ChromeMV3Command] {
        guard let commands = value as? [String: Any] else { return [:] }
        return commands.reduce(into: [:]) { result, entry in
            guard let command = entry.value as? [String: Any] else { return }
            let suggestedKey = command["suggested_key"] as? [String: Any] ?? [:]
            result[entry.key] = ChromeMV3Command(
                description: stringValue(command["description"]),
                suggestedKey: suggestedKey.reduce(into: [:]) { keys, entry in
                    if let value = stringValue(entry.value) {
                        keys[entry.key] = value
                    }
                }
            )
        }
    }

    private static func parseJSONValueObject(_ value: Any?) -> [String: JSONValue] {
        guard let object = value as? [String: Any] else { return [:] }
        return object.mapValues(JSONValue.init(any:))
    }

    private static func iconPathMap(_ value: Any?) -> [String: String] {
        if let path = stringValue(value) {
            return ["default": path]
        }
        guard let object = value as? [String: Any] else { return [:] }
        return object.reduce(into: [:]) { result, entry in
            if let path = stringValue(entry.value) {
                result[entry.key] = path
            }
        }
    }

    private static func iconPaths(_ value: Any?) -> [String] {
        if let path = stringValue(value) {
            return [path]
        }
        if let object = value as? [String: Any] {
            return object.values.compactMap(stringValue)
        }
        return []
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type != "c" else { return nil }
        return number.intValue
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type == "c" else { return nil }
        return number.boolValue
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func sha256(fileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
