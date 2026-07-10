import Foundation

/// Canonical identity used when deciding whether two browser-owned main-frame
/// operations describe the same destination. Foundation's raw URL equality
/// does not normalize default ports, an empty HTTP path, or percent-escape
/// spelling, which is too weak for navigation de-duplication.
public struct WebRuntimeNavigationIdentity: Hashable, Sendable {
    private let value: String

    public init(_ url: URL) {
        value = Self.canonicalValue(for: url)
    }

    public static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        Self(lhs) == Self(rhs)
    }

    private static func canonicalValue(for url: URL) -> String {
        if url.isFileURL {
            return url.standardizedFileURL.absoluteString
        }

        let standardizedURL = url.absoluteURL.standardized
        guard var components = URLComponents(
            url: standardizedURL,
            resolvingAgainstBaseURL: true
        ) else {
            return standardizedURL.absoluteString
        }

        let scheme = components.scheme?.lowercased()
        components.scheme = scheme
        components.host = components.host?.lowercased()
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if (scheme == "http" || scheme == "https"), components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }

        components.percentEncodedUser = normalizePercentEscapes(components.percentEncodedUser)
        components.percentEncodedPassword = normalizePercentEscapes(components.percentEncodedPassword)
        components.percentEncodedPath = normalizePercentEscapes(components.percentEncodedPath)
        components.percentEncodedQuery = normalizePercentEscapes(components.percentEncodedQuery)
        components.percentEncodedFragment = normalizePercentEscapes(components.percentEncodedFragment)
        return components.string ?? standardizedURL.absoluteString
    }

    private static func normalizePercentEscapes(_ value: String?) -> String? {
        value.map(normalizePercentEscapes)
    }

    private static func normalizePercentEscapes(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var result = ""
        result.reserveCapacity(value.count)
        var index = 0

        while index < scalars.count {
            guard scalars[index] == "%",
                  index + 2 < scalars.count,
                  let high = hexadecimalValue(of: scalars[index + 1]),
                  let low = hexadecimalValue(of: scalars[index + 2]) else {
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }

            let byte = high * 16 + low
            if isUnreservedASCII(byte) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result.append(String(format: "%%%02X", byte))
            }
            index += 3
        }
        return result
    }

    private static func hexadecimalValue(of scalar: UnicodeScalar) -> UInt8? {
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...70:
            return UInt8(scalar.value - 55)
        case 97...102:
            return UInt8(scalar.value - 87)
        default:
            return nil
        }
    }

    private static func isUnreservedASCII(_ value: UInt8) -> Bool {
        (65...90).contains(value)
            || (97...122).contains(value)
            || (48...57).contains(value)
            || value == 45
            || value == 46
            || value == 95
            || value == 126
    }
}
