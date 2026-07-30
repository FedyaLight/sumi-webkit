//
//  SafariContentBlockerRuleLocator.swift
//  Sumi
//

import CryptoKit
import Foundation

struct SafariContentBlockerLocatedRules: Equatable, Sendable {
    let definitions: [SumiContentRuleListDefinition]
    let resourceFingerprint: String
    let resourceStamp: String
    let ignoredEmptyRuleListCount: Int
}

enum SafariContentBlockerRuleLocatorError: LocalizedError, Equatable {
    case resourcesDirectoryMissing
    case invalidJSON(path: String, reason: String)
    case invalidRuleListShape(path: String)
    case staticRulesUnavailable

    var errorDescription: String? {
        switch self {
        case .resourcesDirectoryMissing:
            return "The content blocker has no readable Resources directory."
        case .invalidJSON(let path, let reason):
            return "Invalid content blocker JSON in \(path): \(reason)"
        case .invalidRuleListShape(let path):
            return "Content blocker rules in \(path) do not match WebKit's rule-list shape."
        case .staticRulesUnavailable:
            return "This content blocker does not expose non-empty static rule JSON that Sumi can compile."
        }
    }
}

enum SafariContentBlockerRuleLocator {
    static func locateRules(
        in candidate: DiscoveredSafariExtensionCandidate
    ) throws -> SafariContentBlockerLocatedRules {
        try locateRules(
            appexURL: candidate.appexURL,
            extensionBundleIdentifier: candidate.extensionBundleIdentifier,
            displayName: candidate.displayName
        )
    }

    static func locateRules(
        appexURL: URL,
        extensionBundleIdentifier: String,
        displayName: String
    ) throws -> SafariContentBlockerLocatedRules {
        let resourcesURL = appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let jsonURLs = try ruleJSONURLs(in: resourcesURL)
        var resourceHasher = SHA256()
        var resourceStampHasher = SHA256()

        var definitions: [SumiContentRuleListDefinition] = []
        var ignoredEmptyRuleListCount = 0

        for jsonURL in jsonURLs {
            let data = try Data(contentsOf: jsonURL)
            let relativePath = displayPath(jsonURL, relativeTo: resourcesURL)
            let digest = SHA256.hash(data: data)
            resourceHasher.update(data: Data(relativePath.utf8))
            resourceHasher.update(data: Data(digest))
            updateResourceStamp(
                &resourceStampHasher,
                relativePath: relativePath,
                fileSize: data.count,
                modificationDate: (try? jsonURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ))?.contentModificationDate
            )
            let parsed: Any
            do {
                parsed = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw SafariContentBlockerRuleLocatorError.invalidJSON(
                    path: relativePath,
                    reason: error.localizedDescription
                )
            }

            guard let rules = parsed as? [[String: Any]] else {
                continue
            }
            guard rules.isEmpty == false else {
                ignoredEmptyRuleListCount += 1
                continue
            }
            guard isValidRuleList(rules) else {
                throw SafariContentBlockerRuleLocatorError.invalidRuleListShape(
                    path: relativePath
                )
            }
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw SafariContentBlockerRuleLocatorError.invalidJSON(
                    path: relativePath,
                    reason: "The file is not valid UTF-8."
                )
            }

            let name = "\(displayName) \(relativePath)"
            let storeIdentifier = storeIdentifier(
                extensionBundleIdentifier: extensionBundleIdentifier,
                relativePath: relativePath,
                digest: digest
            )
            definitions.append(
                SumiContentRuleListDefinition(
                    name: name,
                    encodedContentRuleList: encoded,
                    storeIdentifierOverride: storeIdentifier,
                    contentHashOverride: shortHex(digest, byteCount: 12)
                )
            )
        }

        guard definitions.isEmpty == false else {
            throw SafariContentBlockerRuleLocatorError.staticRulesUnavailable
        }

        let fingerprint = shortHex(
            resourceHasher.finalize(),
            byteCount: 12
        )
        let stamp = shortHex(
            resourceStampHasher.finalize(),
            byteCount: 12
        )
        return SafariContentBlockerLocatedRules(
            definitions: definitions.sorted { $0.webKitStoreIdentifier < $1.webKitStoreIdentifier },
            resourceFingerprint: fingerprint,
            resourceStamp: stamp,
            ignoredEmptyRuleListCount: ignoredEmptyRuleListCount
        )
    }

    static func resourceStamp(appexURL: URL) -> String {
        let resourcesURL = appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let urls: [URL]
        do {
            urls = try ruleJSONURLs(in: resourcesURL)
        } catch {
            return "resources-unavailable"
        }

        var hasher = SHA256()
        for url in urls {
            let relativePath = displayPath(url, relativeTo: resourcesURL)
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            updateResourceStamp(
                &hasher,
                relativePath: relativePath,
                fileSize: values?.fileSize ?? -1,
                modificationDate: values?.contentModificationDate
            )
        }
        return shortHex(hasher.finalize(), byteCount: 12)
    }

    static func resourceFingerprint(appexURL: URL) -> String {
        let resourcesURL = appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let urls: [URL]
        do {
            urls = try ruleJSONURLs(in: resourcesURL)
        } catch {
            RuntimeDiagnostics.debug(category: "SafariContentBlocker") {
                "Content blocker resource fingerprint unavailable: \(error.localizedDescription)"
            }
            return "resources-unavailable"
        }
        return resourceFingerprint(for: urls, relativeTo: resourcesURL)
    }

    private static func ruleJSONURLs(in resourcesURL: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resourcesURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw SafariContentBlockerRuleLocatorError.resourcesDirectoryMissing
        }

        guard let enumerator = FileManager.default.enumerator(
            at: resourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SafariContentBlockerRuleLocatorError.resourcesDirectoryMissing
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "json" else { continue }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isRegularFileKey])
            } catch {
                RuntimeDiagnostics.debug(category: "SafariContentBlocker") {
                    "Skipping content blocker JSON candidate with unreadable resource values: path=\(displayPath(url, relativeTo: resourcesURL)) error=\(error.localizedDescription)"
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    private static func shouldSkipDirectory(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "bundle" || ext == "framework"
    }

    private static func isValidRuleList(_ rules: [[String: Any]]) -> Bool {
        rules.allSatisfy { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let action = rule["action"] as? [String: Any],
                  trigger["url-filter"] is String,
                  action["type"] is String
            else {
                return false
            }
            return true
        }
    }

    private static func resourceFingerprint(for urls: [URL], relativeTo root: URL) -> String {
        var hasher = SHA256()
        for url in urls {
            let relativePath = displayPath(url, relativeTo: root)
            hasher.update(data: Data(relativePath.utf8))
            do {
                let data = try Data(contentsOf: url)
                hasher.update(data: Data(SHA256.hash(data: data)))
            } catch {
                RuntimeDiagnostics.debug(category: "SafariContentBlocker") {
                    "Content blocker resource fingerprint marked unreadable file: path=\(relativePath) error=\(error.localizedDescription)"
                }
                hasher.update(data: Data("unreadable:\(relativePath)".utf8))
            }
        }
        let digest = hasher.finalize()
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func updateResourceStamp(
        _ hasher: inout SHA256,
        relativePath: String,
        fileSize: Int,
        modificationDate: Date?
    ) {
        let modificationBits = (
            modificationDate?.timeIntervalSince1970
                ?? -1
        ).bitPattern
        hasher.update(
            data: Data(
                "\(relativePath)\u{0}\(fileSize)\u{0}\(modificationBits)\u{0}"
                    .utf8
            )
        )
    }

    private static func storeIdentifier(
        extensionBundleIdentifier: String,
        relativePath: String,
        digest: SHA256.Digest
    ) -> String {
        [
            "sumi",
            "safariContentBlocker",
            sanitizedIdentifierComponent(extensionBundleIdentifier),
            sanitizedIdentifierComponent(relativePath),
            shortHex(digest, byteCount: 8),
        ].joined(separator: ".")
    }

    private static func shortHex<D: Sequence>(
        _ digest: D,
        byteCount: Int
    ) -> String where D.Element == UInt8 {
        digest.prefix(byteCount)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sanitizedIdentifierComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "rules" : collapsed
    }

    private static func displayPath(_ url: URL, relativeTo root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relative = path.dropFirst(rootPath.count)
        return relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
