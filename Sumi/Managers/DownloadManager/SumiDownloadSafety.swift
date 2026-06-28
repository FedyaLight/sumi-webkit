import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

enum SumiDownloadSafety {
    static func requiresOpeningConfirmation(
        filename: String?,
        mimeType: String? = nil
    ) -> Bool {
        let fileType = filename.flatMap { type(forFilename: $0) }
            ?? mimeType.flatMap(type(forMIMEType:))
        return requiresOpeningConfirmation(type: fileType, filename: filename)
    }

    static func requiresOpeningConfirmation(forFileAt url: URL) -> Bool {
        requiresOpeningConfirmation(type: type(forFileAt: url), filename: url.lastPathComponent)
    }

    static func applyQuarantine(to url: URL, sourceURL: URL?) throws {
        var values = URLResourceValues()
        values.quarantineProperties = quarantineProperties(sourceURL: sourceURL)
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    @MainActor
    static func confirmOpeningIfNeeded(url: URL, sourceURL: URL?) -> Bool {
        guard requiresOpeningConfirmation(forFileAt: url) else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Open downloaded file?"
        alert.informativeText = warningText(filename: url.lastPathComponent, sourceURL: sourceURL)
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func requiresOpeningConfirmation(type: UTType?, filename: String?) -> Bool {
        if let ext = filename.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() }),
           dangerousExtensions.contains(ext) {
            return true
        }

        guard let type else { return false }
        if type.conforms(to: .executable)
            || type.conforms(to: .applicationBundle)
            || type.conforms(to: .script)
            || type.conforms(to: .shellScript)
            || type.conforms(to: .diskImage) {
            return true
        }
        return dangerousTypeIdentifiers.contains(type.identifier)
    }

    private static func type(forFileAt url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return type(forFilename: url.lastPathComponent)
    }

    private static func type(forFilename filename: String) -> UTType? {
        let ext = URL(fileURLWithPath: filename).pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }

    private static func type(forMIMEType mimeType: String) -> UTType? {
        let normalized = mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return UTType.types(tag: normalized, tagClass: .mimeType, conformingTo: nil).first
    }

    private static func quarantineProperties(sourceURL: URL?) -> [String: Any] {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Sumi",
            kLSQuarantineAgentBundleIdentifierKey as String: SumiAppIdentity.runtimeBundleIdentifier,
            kLSQuarantineTimeStampKey as String: Date(),
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        if let sourceURL {
            properties[kLSQuarantineDataURLKey as String] = sourceURL
        }
        return properties
    }

    private static func warningText(filename: String, sourceURL: URL?) -> String {
        let source = sourceURL?.host ?? sourceURL?.absoluteString
        if let source, !source.isEmpty {
            return "\(filename) may run code or open active content from \(source). Open it only if you trust this download."
        }
        return "\(filename) may run code or open active content. Open it only if you trust this download."
    }

    private static let dangerousExtensions: Set<String> = [
        "app", "applescript", "bash", "csh", "command", "dmg", "exe", "inetloc",
        "jar", "ksh", "mpkg", "pkg", "scpt", "scptd", "sh", "terminal", "tool",
        "url", "webloc", "workflow", "zsh",
    ]

    private static let dangerousTypeIdentifiers: Set<String> = [
        "com.apple.installer-package-archive",
        "com.apple.installer-package",
        "com.apple.web-internet-location",
    ]
}
