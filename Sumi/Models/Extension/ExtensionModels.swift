//
//  ExtensionModels.swift
//  Sumi
//
//  Persistence and DTO models for Sumi's WebExtension runtime.
//

import Foundation
import SwiftData

enum IncognitoExtensionMode: String, Codable, CaseIterable {
    case spanning
    case split
    case notAllowed = "not_allowed"

    static func fromManifest(_ manifest: [String: Any]) throws -> Self {
        guard let rawValue = manifest["incognito"] as? String else {
            return .spanning
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let mode = Self(rawValue: normalized) else {
            throw ExtensionError.invalidManifest(
                "Unsupported incognito mode: \(rawValue)"
            )
        }

        return mode
    }

    var allowsPrivateAccess: Bool {
        self != .notAllowed
    }
}

enum WebExtensionSourceKind: String, Codable, CaseIterable, Sendable {
    case directory
    case safariAppExtension
}

enum WebExtensionBackgroundModel: String, Codable, CaseIterable {
    case serviceWorker = "service_worker"
    case none
}

struct ExtensionActivationSummary: Codable, Equatable {
    let matchPatternStrings: [String]
    let broadScope: Bool
    let hasContentScripts: Bool
    let hasAction: Bool
    let hasOptionsPage: Bool
    let hasExtensionPages: Bool
}

@Model
final class ExtensionEntity {
    @Attribute(.unique) var id: String
    var name: String
    var version: String
    var manifestVersion: Int
    var extensionDescription: String?
    var isEnabled: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var packagePath: String
    var iconPath: String?

    var sourceKindRawValue: String
    var backgroundModelRawValue: String
    var incognitoModeRawValue: String

    var sourcePathFingerprint: String
    var manifestRootFingerprint: String
    var sourceBundlePath: String
    var optionsPagePath: String?
    var defaultPopupPath: String?

    var hasBackground: Bool
    var hasAction: Bool
    var hasOptionsPage: Bool
    var hasContentScripts: Bool
    var hasExtensionPages: Bool
    var broadScope: Bool

    var activationSummaryJSON: String
    var manifestSnapshotJSON: String

    init(record: InstalledExtensionRecord) {
        self.id = record.id
        self.name = record.name
        self.version = record.version
        self.manifestVersion = record.manifestVersion
        self.extensionDescription = record.description
        self.isEnabled = record.isEnabled
        self.installDate = record.installDate
        self.lastUpdateDate = record.lastUpdateDate
        self.packagePath = record.packagePath
        self.iconPath = record.iconPath
        self.sourceKindRawValue = record.sourceKind.rawValue
        self.backgroundModelRawValue = record.backgroundModel.rawValue
        self.incognitoModeRawValue = record.incognitoMode.rawValue
        self.sourcePathFingerprint = record.sourcePathFingerprint
        self.manifestRootFingerprint = record.manifestRootFingerprint
        self.sourceBundlePath = record.sourceBundlePath
        self.optionsPagePath = record.optionsPagePath
        self.defaultPopupPath = record.defaultPopupPath
        self.hasBackground = record.hasBackground
        self.hasAction = record.hasAction
        self.hasOptionsPage = record.hasOptionsPage
        self.hasContentScripts = record.hasContentScripts
        self.hasExtensionPages = record.hasExtensionPages
        self.broadScope = record.activationSummary.broadScope
        self.activationSummaryJSON = record.encodedActivationSummary
        self.manifestSnapshotJSON = record.encodedManifestSnapshot
    }
}

struct InstalledExtensionRecord {
    let id: String
    let name: String
    let version: String
    let manifestVersion: Int
    let description: String?
    let isEnabled: Bool
    let installDate: Date
    let lastUpdateDate: Date
    let packagePath: String
    let iconPath: String?

    let sourceKind: WebExtensionSourceKind
    let backgroundModel: WebExtensionBackgroundModel
    let incognitoMode: IncognitoExtensionMode

    let sourcePathFingerprint: String
    let manifestRootFingerprint: String
    let sourceBundlePath: String
    let optionsPagePath: String?
    let defaultPopupPath: String?

    let hasBackground: Bool
    let hasAction: Bool
    let hasOptionsPage: Bool
    let hasContentScripts: Bool
    let hasExtensionPages: Bool

    let activationSummary: ExtensionActivationSummary
    let manifest: [String: Any]

    init(
        id: String,
        name: String,
        version: String,
        manifestVersion: Int,
        description: String?,
        isEnabled: Bool,
        installDate: Date,
        lastUpdateDate: Date,
        packagePath: String,
        iconPath: String?,
        sourceKind: WebExtensionSourceKind,
        backgroundModel: WebExtensionBackgroundModel,
        incognitoMode: IncognitoExtensionMode,
        sourcePathFingerprint: String,
        manifestRootFingerprint: String,
        sourceBundlePath: String,
        optionsPagePath: String?,
        defaultPopupPath: String?,
        hasBackground: Bool,
        hasAction: Bool,
        hasOptionsPage: Bool,
        hasContentScripts: Bool,
        hasExtensionPages: Bool,
        activationSummary: ExtensionActivationSummary,
        manifest: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.manifestVersion = manifestVersion
        self.description = description
        self.isEnabled = isEnabled
        self.installDate = installDate
        self.lastUpdateDate = lastUpdateDate
        self.packagePath = packagePath
        self.iconPath = iconPath
        self.sourceKind = sourceKind
        self.backgroundModel = backgroundModel
        self.incognitoMode = incognitoMode
        self.sourcePathFingerprint = sourcePathFingerprint
        self.manifestRootFingerprint = manifestRootFingerprint
        self.sourceBundlePath = sourceBundlePath
        self.optionsPagePath = optionsPagePath
        self.defaultPopupPath = defaultPopupPath
        self.hasBackground = hasBackground
        self.hasAction = hasAction
        self.hasOptionsPage = hasOptionsPage
        self.hasContentScripts = hasContentScripts
        self.hasExtensionPages = hasExtensionPages
        self.activationSummary = activationSummary
        self.manifest = manifest
    }

    init?(from entity: ExtensionEntity) {
        guard
            let sourceKind = WebExtensionSourceKind(
                rawValue: entity.sourceKindRawValue
            ),
            let backgroundModel = WebExtensionBackgroundModel(
                rawValue: entity.backgroundModelRawValue
            ),
            let incognitoMode = IncognitoExtensionMode(
                rawValue: entity.incognitoModeRawValue
            ),
            let activationSummary = Self.decode(
                ExtensionActivationSummary.self,
                from: entity.activationSummaryJSON
            ),
            let manifest = Self.decodeJSONObject(from: entity.manifestSnapshotJSON)
        else {
            return nil
        }

        self.init(
            id: entity.id,
            name: entity.name,
            version: entity.version,
            manifestVersion: entity.manifestVersion,
            description: entity.extensionDescription,
            isEnabled: entity.isEnabled,
            installDate: entity.installDate,
            lastUpdateDate: entity.lastUpdateDate,
            packagePath: entity.packagePath,
            iconPath: entity.iconPath,
            sourceKind: sourceKind,
            backgroundModel: backgroundModel,
            incognitoMode: incognitoMode,
            sourcePathFingerprint: entity.sourcePathFingerprint,
            manifestRootFingerprint: entity.manifestRootFingerprint,
            sourceBundlePath: entity.sourceBundlePath,
            optionsPagePath: entity.optionsPagePath,
            defaultPopupPath: entity.defaultPopupPath,
            hasBackground: entity.hasBackground,
            hasAction: entity.hasAction,
            hasOptionsPage: entity.hasOptionsPage,
            hasContentScripts: entity.hasContentScripts,
            hasExtensionPages: entity.hasExtensionPages,
            activationSummary: activationSummary,
            manifest: manifest
        )
    }

    var encodedActivationSummary: String {
        Self.encode(activationSummary)
    }

    var encodedManifestSnapshot: String {
        Self.encodeJSONObject(manifest)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from json: String
    ) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func decodeJSONObject(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private static func encodeJSONObject(_ value: [String: Any]) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys]
            ),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

typealias InstalledExtension = InstalledExtensionRecord

enum ExtensionError: LocalizedError {
    case unsupportedOS
    case invalidManifest(String)
    case unsupportedManifest(String)
    case unsupportedCapability(String)
    case installationFailed(String)
    case importSucceededEnableFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Extensions require iOS 18.5+ or macOS 15.5+"
        case .invalidManifest(let reason):
            return "Invalid manifest.json: \(reason)"
        case .unsupportedManifest(let reason):
            return "Unsupported extension manifest: \(reason)"
        case .unsupportedCapability(let reason):
            return "Unsupported extension capability: \(reason)"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .importSucceededEnableFailed(let reason):
            return reason
        case .permissionDenied:
            return "Permission denied"
        }
    }
}
