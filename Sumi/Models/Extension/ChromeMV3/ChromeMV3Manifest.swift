//
//  ChromeMV3Manifest.swift
//  Sumi
//
//  Neutral Chrome Manifest V3 data models. These types intentionally do not
//  load, rewrite, or execute extension resources.
//

import Foundation

enum ChromeMV3PackageSourceKind: String, Codable, CaseIterable {
    case unpackedDirectory
    case zipArchive
    case crxArchive
}

struct ChromeMV3ExtensionIdentity: Codable, Equatable {
    var id: String?
    var derivationInput: String?
}

struct ChromeMV3PackageMetadata: Codable, Equatable {
    var extensionIdentity: ChromeMV3ExtensionIdentity
    var originalBundlePath: String?
    var originalBundleLastPathComponent: String?
    var sourceKind: ChromeMV3PackageSourceKind
    var generatedBundlePath: String?
    var installDate: Date?
    var installedVersion: String?
    var sourceSHA256: String?
    var manifestSHA256: String?

    init(
        extensionIdentity: ChromeMV3ExtensionIdentity = ChromeMV3ExtensionIdentity(),
        originalBundlePath: String? = nil,
        originalBundleLastPathComponent: String? = nil,
        sourceKind: ChromeMV3PackageSourceKind,
        generatedBundlePath: String? = nil,
        installDate: Date? = nil,
        installedVersion: String? = nil,
        sourceSHA256: String? = nil,
        manifestSHA256: String? = nil
    ) {
        self.extensionIdentity = extensionIdentity
        self.originalBundlePath = originalBundlePath
        self.originalBundleLastPathComponent = originalBundleLastPathComponent
        self.sourceKind = sourceKind
        self.generatedBundlePath = generatedBundlePath
        self.installDate = installDate
        self.installedVersion = installedVersion
        self.sourceSHA256 = sourceSHA256
        self.manifestSHA256 = manifestSHA256
    }
}

struct ChromeMV3Manifest: Codable, Equatable {
    var manifestVersion: Int
    var name: String
    var version: String
    var description: String?
    var background: ChromeMV3Background?
    var permissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String] = []
    var defaultLocale: String?
    var contentScripts: [ChromeMV3ContentScript]
    var action: ChromeMV3Action?
    var optionsPage: String?
    var optionsUI: ChromeMV3OptionsUI?
    var webAccessibleResources: [ChromeMV3WebAccessibleResource]
    var externallyConnectable: ChromeMV3ExternallyConnectable?
    var declarativeNetRequest: ChromeMV3DeclarativeNetRequest?
    var sidePanel: ChromeMV3SidePanel?
    var oauth2: ChromeMV3OAuth2?
    var commands: [String: ChromeMV3Command]
    var minimumChromeVersion: String?
    var browserSpecificSettings: [String: JSONValue]
    var devtoolsPage: String?
    var topLevelKeys: [String]

    var allDeclaredPermissions: [String] {
        Array(Set(permissions + optionalPermissions)).sorted()
    }

    func declaresPermission(_ permission: String) -> Bool {
        allDeclaredPermissions.contains(permission)
    }

    func declaresPermission(withPrefix prefix: String) -> Bool {
        allDeclaredPermissions.contains { $0.hasPrefix(prefix) }
    }
}

struct ChromeMV3Background: Codable, Equatable {
    var serviceWorker: String?
    var type: String?
}

struct ChromeMV3ContentScript: Codable, Equatable {
    var matches: [String]
    var excludeMatches: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var js: [String]
    var css: [String]
    var allFrames: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var runAt: String?
    var world: String?
}

struct ChromeMV3Action: Codable, Equatable {
    var defaultPopup: String?
    var defaultTitle: String?
    var defaultIconPaths: [String: String]
}

struct ChromeMV3OptionsUI: Codable, Equatable {
    var page: String?
    var openInTab: Bool?
}

struct ChromeMV3WebAccessibleResource: Codable, Equatable {
    var resources: [String]
    var matches: [String]
    var extensionIDs: [String]
    var useDynamicURL: Bool?
}

struct ChromeMV3ExternallyConnectable: Codable, Equatable {
    var ids: [String]
    var matches: [String]
    var acceptsTLSChannelID: Bool?
}

struct ChromeMV3DeclarativeNetRequest: Codable, Equatable {
    var ruleResources: [ChromeMV3DeclarativeNetRequestRuleResource]
}

struct ChromeMV3DeclarativeNetRequestRuleResource: Codable, Equatable {
    var id: String?
    var enabled: Bool?
    var path: String?
}

struct ChromeMV3SidePanel: Codable, Equatable {
    var defaultPath: String?
}

struct ChromeMV3OAuth2: Codable, Equatable {
    var clientID: String?
    var scopes: [String]
}

struct ChromeMV3Command: Codable, Equatable {
    var description: String?
    var suggestedKey: [String: String]
}

enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(any value: Any) {
        if value is NSNull {
            self = .null
        } else if let string = value as? String {
            self = .string(string)
        } else if let number = value as? NSNumber {
            let type = String(cString: number.objCType)
            if type == "c" {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        } else if let array = value as? [Any] {
            self = .array(array.map(JSONValue.init(any:)))
        } else if let object = value as? [String: Any] {
            self = .object(object.mapValues(JSONValue.init(any:)))
        } else {
            self = .string(String(describing: value))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .null:
            try container.encodeNil()
        }
    }
}
