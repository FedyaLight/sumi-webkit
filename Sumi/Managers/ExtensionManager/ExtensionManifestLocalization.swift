import Foundation
import OSLog

enum ExtensionManifestLocalization {
    private static let log = Logger.sumi(category: "Extensions")

    static func resolve(_ rawValue: String?, in extensionRoot: URL) -> String? {
        guard let rawValue, rawValue.hasPrefix("__MSG_"),
              rawValue.hasSuffix("__")
        else { return rawValue }

        let key = String(rawValue.dropFirst(6).dropLast(2))
        let localesRoot = extensionRoot.appendingPathComponent(
            "_locales",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: localesRoot.path) else {
            return nil
        }

        let directories: [URL]
        do {
            directories = try FileManager.default.contentsOfDirectory(
                at: localesRoot,
                includingPropertiesForKeys: nil
            )
        } catch {
            log.error(
                "Failed to read extension locales directory \(localesRoot.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        let localeDirectory = preferredLocaleDirectoryNames().lazy.compactMap {
            candidate in
            directories.first {
                $0.lastPathComponent.caseInsensitiveCompare(candidate)
                    == .orderedSame
            }
        }.first
        guard let localeDirectory else { return nil }

        let messagesURL = localeDirectory.appendingPathComponent("messages.json")
        let messages: [String: Any]
        do {
            messages = try ExtensionManifestValidation.loadJSONObject(
                at: messagesURL
            )
        } catch {
            log.error(
                "Failed to read extension locale messages \(messagesURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        return (messages[key] as? [String: Any])?["message"] as? String
    }

    static func preferredLocaleDirectoryNames() -> [String] {
        var values: [String] = []
        let locale = Locale.current
        if let language = locale.language.languageCode?.identifier {
            if let region = locale.language.region?.identifier {
                values.append("\(language)_\(region)")
                values.append("\(language)-\(region)")
            }
            values.append(language)
        }
        values.append("en")
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }
}
