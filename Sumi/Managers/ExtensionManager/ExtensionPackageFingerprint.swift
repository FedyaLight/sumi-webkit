import CryptoKit
import Foundation
import OSLog

enum ExtensionPackageFingerprint {
    private static let log = Logger.sumi(category: "Extensions")

    static func data(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func string(_ string: String) -> String {
        data(Data(string.utf8))
    }

    static func file(at url: URL) -> String {
        do {
            return try data(Data(contentsOf: url))
        } catch {
            log.error(
                "Failed to fingerprint extension file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return string(url.path)
        }
    }

    static func normalizedPath(_ url: URL) -> String {
        string(url.standardizedFileURL.path)
    }
}
