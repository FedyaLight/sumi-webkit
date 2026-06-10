import Foundation

@testable import Sumi

enum SafariExtensionScannerTestSupport {
    static let safariExtensionPoint = SafariExtensionScanner.safariWebExtensionPointIdentifier

    @discardableResult
    static func makeContainingAppBundle(
        in parentDirectory: URL,
        appName: String = "PasswordManager",
        appBundleIdentifier: String = "com.example.passwordmanager",
        extensions: [SyntheticSafariExtension]
    ) throws -> URL {
        let appURL = parentDirectory.appendingPathComponent("\(appName).app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents/PlugIns", isDirectory: true),
            withIntermediateDirectories: true
        )

        try writeInfoPlist(
            at: appURL.appendingPathComponent("Contents/Info.plist"),
            bundleIdentifier: appBundleIdentifier,
            displayName: appName
        )

        for ext in extensions {
            try makeAppexBundle(
                in: appURL.appendingPathComponent("Contents/PlugIns", isDirectory: true),
                specification: ext
            )
        }

        return appURL
    }

    @discardableResult
    static func makeStandaloneAppex(
        in parentDirectory: URL,
        specification: SyntheticSafariExtension
    ) throws -> URL {
        try makeAppexBundle(in: parentDirectory, specification: specification)
    }

    @discardableResult
    private static func makeAppexBundle(
        in pluginsDirectory: URL,
        specification: SyntheticSafariExtension
    ) throws -> URL {
        let appexURL = pluginsDirectory.appendingPathComponent(
            "\(specification.name).appex",
            isDirectory: true
        )
        let contentsURL = appexURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsURL.appendingPathComponent("Resources", isDirectory: true),
            withIntermediateDirectories: true
        )

        var extensionDictionary: [String: Any] = [
            "NSExtensionPointIdentifier": specification.extensionPointIdentifier,
        ]
        if specification.includeExtensionAttributes {
            extensionDictionary["NSExtensionAttributes"] = [
                "WebExtensionVersion": "1.0",
            ]
        }

        try writeInfoPlist(
            at: contentsURL.appendingPathComponent("Info.plist"),
            bundleIdentifier: specification.bundleIdentifier,
            displayName: specification.displayName,
            version: specification.version,
            extensionDictionary: extensionDictionary,
            corruptPlist: specification.corruptPlist
        )

        if specification.includeManifest {
            let resourcesURL = contentsURL
                .appendingPathComponent("Resources", isDirectory: true)
            let manifestURL = resourcesURL.appendingPathComponent("manifest.json")
            var manifest: [String: Any] = [
                "manifest_version": specification.manifestVersion,
                "name": specification.displayName,
                "version": specification.version,
            ]
            if specification.includeActionPopup {
                manifest["action"] = ["default_popup": "popup.html"]
            }
            if specification.hostPermissions.isEmpty == false {
                manifest["host_permissions"] = specification.hostPermissions
            }
            let data = try JSONSerialization.data(
                withJSONObject: manifest,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: manifestURL, options: [.atomic])

            if specification.includeActionPopup {
                let popupURL = resourcesURL.appendingPathComponent("popup.html")
                try Data(
                    "<!doctype html><title>popup</title>".utf8
                ).write(to: popupURL, options: [.atomic])
            }
        }

        return appexURL
    }

    private static func writeInfoPlist(
        at url: URL,
        bundleIdentifier: String,
        displayName: String,
        version: String = "1.0.0",
        extensionDictionary: [String: Any]? = nil,
        corruptPlist: Bool = false
    ) throws {
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL",
        ]
        if let extensionDictionary {
            plist["NSExtension"] = extensionDictionary
        }

        if corruptPlist {
            try Data("not a plist".utf8).write(to: url, options: [.atomic])
            return
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: [.atomic])
    }

    struct SyntheticSafariExtension {
        var name: String
        var bundleIdentifier: String
        var displayName: String
        var version: String = "1.0.0"
        var extensionPointIdentifier: String = SafariExtensionScannerTestSupport.safariExtensionPoint
        var includeManifest: Bool = true
        var includeExtensionAttributes: Bool = true
        var corruptPlist: Bool = false
        var manifestVersion: Int = 3
        var includeActionPopup: Bool = false
        var hostPermissions: [String] = []
    }
}
