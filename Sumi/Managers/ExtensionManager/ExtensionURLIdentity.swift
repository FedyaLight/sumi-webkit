import Foundation
import SumiDomain

enum ExtensionURLIdentity {
    static let ownedSchemes: Set<String> = SumiExtensionOwnedURL.schemes

    static func isOwned(_ url: URL?) -> Bool {
        SumiExtensionOwnedURL.isExtensionOwnedURL(url)
    }

    static func extensionID(from url: URL?) -> String? {
        guard isOwned(url),
              let host = url?.host?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ), host.isEmpty == false
        else { return nil }

        return extensionID(fromHost: host) ?? host
    }

    static func extensionID(fromHost host: String) -> String? {
        let normalizedHost = host.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedHost.hasPrefix("ext-") else { return nil }
        let hex = String(normalizedHost.dropFirst(4))
        guard hex.count.isMultiple(of: 2) else { return nil }

        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        guard let scopedIdentifier = String(bytes: bytes, encoding: .utf8),
              let separator = scopedIdentifier.firstIndex(of: ":")
        else { return nil }

        let extensionID = scopedIdentifier[
            scopedIdentifier.index(after: separator)...
        ].trimmingCharacters(in: .whitespacesAndNewlines)
        return extensionID.isEmpty ? nil : extensionID
    }
}
