import Foundation

/// Decides whether omnibar input is a navigable URL or a search phrase, and
/// normalizes navigable input (scheme fix-ups, punycode hosts, IPv4 shorthand,
/// percent-encoding). Native replacement for the vendored DDG URLPredictor
/// Rust classifier; matches its macOS policy: multi-label intranet hosts are
/// navigable, single labels (except localhost) are searches.
public enum SumiAddressBarClassifier {
    public enum Decision: Equatable {
        case navigate(URL)
        case search(String)
    }

    /// Schemes accepted as navigable when typed explicitly.
    public static let allowedSchemes: Set<String> = [
        "http", "https", "file", "about", "blob", "data", "mailto",
        "webkit-extension", "safari-web-extension", "sumi", "x-safari-https",
    ]

    private static let hierarchicalSchemes: Set<String> = ["http", "https", "x-safari-https"]

    public static func classify(_ input: String) -> Decision {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .search(trimmed) }

        if let (scheme, rest) = splitScheme(trimmed) {
            if hierarchicalSchemes.contains(scheme) {
                return classifyHierarchical(scheme: scheme, rest: rest) ?? .search(trimmed)
            }
            if scheme == "file" {
                return classifyFile(rest: rest) ?? .search(trimmed)
            }
            if allowedSchemes.contains(scheme) {
                return classifyOpaque(original: trimmed) ?? .search(trimmed)
            }
            // Not a recognized scheme; the colon may still separate a port
            // ("localhost:8080") or credentials ("user:pass@host"), so fall
            // through to authority parsing.
        }

        return classifySchemeless(trimmed) ?? .search(trimmed)
    }

    // MARK: - Scheme splitting

    private static func splitScheme(_ input: String) -> (scheme: String, rest: String)? {
        guard let colon = input.firstIndex(of: ":"), colon != input.startIndex else { return nil }
        let candidate = input[..<colon]
        guard candidate.first!.isLetter,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }

        let rest = String(input[input.index(after: colon)...])
        guard !rest.isEmpty else { return nil }
        return (candidate.lowercased(), rest)
    }

    // MARK: - Hierarchical URLs (http, https)

    private static func classifyHierarchical(scheme: String, rest: String) -> Decision? {
        // Tolerate a missing slash after the scheme ("http:/example.com").
        let afterSlashes = rest.drop(while: { $0 == "/" })
        guard let first = afterSlashes.first, !first.isWhitespace else { return nil }

        let (authority, tail) = splitAuthority(String(afterSlashes))
        guard let encodedAuthority = normalizeAuthority(authority, expandIPv4: true) else { return nil }
        guard let encodedTail = encodeTail(tail) else { return nil }

        return URL(string: "\(scheme)://\(encodedAuthority)\(encodedTail)").map { .navigate($0) }
    }

    private static func classifyFile(rest: String) -> Decision? {
        let slashCount = rest.prefix(while: { $0 == "/" }).count
        let remainder = String(rest.dropFirst(slashCount))
        guard !remainder.isEmpty else { return nil }

        let urlString: String
        if slashCount == 2 {
            // file://host/path form.
            let (authority, tail) = splitAuthority(remainder)
            guard let encodedTail = encodeTail(tail) else { return nil }
            urlString = "file://\(authority)\(encodedTail)"
        } else {
            guard let encodedPath = remainder.addingPercentEncoding(withAllowedCharacters: pathAllowed) else {
                return nil
            }
            urlString = "file:///\(encodedPath)"
        }

        return URL(string: urlString).map { .navigate($0) }
    }

    private static func classifyOpaque(original: String) -> Decision? {
        if let url = URL(string: original) {
            return .navigate(url)
        }
        guard let colon = original.firstIndex(of: ":") else { return nil }
        let head = original[...colon]
        guard let encoded = String(original[original.index(after: colon)...])
            .addingPercentEncoding(withAllowedCharacters: queryAllowed)
        else { return nil }
        return URL(string: head + encoded).map { .navigate($0) }
    }

    // MARK: - Schemeless input

    private static func classifySchemeless(_ input: String) -> Decision? {
        guard !input.contains(where: { $0.isWhitespace }) else { return nil }

        let (authority, tail) = splitAuthority(input)
        guard !authority.isEmpty else { return nil }

        if let at = authority.lastIndex(of: "@") {
            // Bare "user@host" is an email-like phrase; only host-typed
            // credentials ("user:pass@host") read as a URL.
            let userinfo = authority[..<at]
            guard let colon = userinfo.firstIndex(of: ":"),
                  userinfo.index(after: colon) != userinfo.endIndex
            else { return nil }
        }

        guard let encodedAuthority = normalizeAuthority(authority, expandIPv4: false) else { return nil }
        let host = hostPart(of: authority)
        guard isNavigableBareHost(host) else { return nil }
        guard let encodedTail = encodeTail(tail) else { return nil }

        let scheme = defaultScheme(forBareHost: host)
        return URL(string: "\(scheme)://\(encodedAuthority)\(encodedTail)").map { .navigate($0) }
    }

    /// Public hosts start securely and avoid an unnecessary HTTP redirect and
    /// WebContent process swap. Local development endpoints retain HTTP so a
    /// bare localhost or IPv4 address remains usable without a certificate.
    private static func defaultScheme(forBareHost host: String) -> String {
        if host.lowercased() == "localhost" {
            return "http"
        }
        let labels = host.components(separatedBy: ".")
        if parseIPv4(labels: labels, allowShorthand: false) != nil {
            return "http"
        }
        return "https"
    }

    /// macOS policy: localhost and full IPv4 addresses navigate; other
    /// single labels search; multi-label hosts navigate unless the TLD is
    /// numeric without being a valid IPv4 address.
    private static func isNavigableBareHost(_ host: String) -> Bool {
        if host.lowercased() == "localhost" { return true }

        let labels = host.components(separatedBy: ".")
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }

        if let last = labels.last, last.allSatisfy({ $0.isNumber }) {
            return parseIPv4(labels: labels, allowShorthand: false) != nil
        }

        return true
    }

    // MARK: - Authority handling

    private static func splitAuthority(_ input: String) -> (authority: String, tail: String) {
        if let cut = input.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            return (String(input[..<cut]), String(input[cut...]))
        }
        return (input, "")
    }

    private static func hostPart(of authority: String) -> String {
        var host = authority
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if let colon = host.lastIndex(of: ":"), host[host.index(after: colon)...].allSatisfy({ $0.isNumber }) {
            host = String(host[..<colon])
        }
        return host
    }

    private static func normalizeAuthority(_ authority: String, expandIPv4: Bool) -> String? {
        guard !authority.isEmpty else { return nil }

        var hostport = authority
        var userinfoPrefix = ""

        if let at = authority.lastIndex(of: "@") {
            guard let userinfo = encodeUserinfo(String(authority[..<at])) else { return nil }
            userinfoPrefix = userinfo + "@"
            hostport = String(authority[authority.index(after: at)...])
        }

        var host = hostport
        var portSuffix = ""
        if let colon = hostport.lastIndex(of: ":") {
            let portCandidate = hostport[hostport.index(after: colon)...]
            guard !portCandidate.isEmpty, portCandidate.allSatisfy({ $0.isNumber }),
                  let port = Int(portCandidate), port <= 65535
            else { return nil }
            host = String(hostport[..<colon])
            portSuffix = ":" + portCandidate
        }

        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }) else { return nil }

        let labels = host.components(separatedBy: ".")
        if expandIPv4, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
           let ipv4 = parseIPv4(labels: labels, allowShorthand: true) {
            return userinfoPrefix + ipv4 + portSuffix
        }

        guard labels.allSatisfy({ !$0.isEmpty && isValidHostLabel($0) }) else { return nil }
        guard let asciiHost = SumiPunycode.hostToASCII(host) else { return nil }

        return userinfoPrefix + asciiHost + portSuffix
    }

    private static func isValidHostLabel(_ label: String) -> Bool {
        label.unicodeScalars.allSatisfy { scalar in
            if !scalar.isASCII { return true }
            return CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-" || scalar == "_" || scalar == "~"
        }
    }

    /// Parses dotted-decimal IPv4, optionally expanding the URL-standard
    /// shorthand where the last part spans the remaining octets
    /// ("1.2.7" → "1.2.0.7"). Returns the canonical 4-octet form.
    private static func parseIPv4(labels: [String], allowShorthand: Bool) -> String? {
        guard (1...4).contains(labels.count) else { return nil }
        if !allowShorthand && labels.count != 4 { return nil }

        var numbers: [UInt32] = []
        for label in labels {
            guard label.count <= 10, let value = UInt32(label) else { return nil }
            numbers.append(value)
        }

        let last = numbers.removeLast()
        for value in numbers where value > 255 { return nil }

        let remainingBytes = 4 - numbers.count
        guard remainingBytes >= 1, last < (remainingBytes == 4 ? .max : 1 << (8 * remainingBytes)) else {
            return nil
        }

        var address: UInt32 = 0
        for value in numbers {
            address = address << 8 | value
        }
        address = address << (8 * UInt32(remainingBytes)) | last

        return (0..<4).reversed()
            .map { String((address >> ($0 * 8)) & 0xFF) }
            .joined(separator: ".")
    }

    private static func encodeUserinfo(_ userinfo: String) -> String? {
        let user: Substring
        let password: Substring?
        if let colon = userinfo.firstIndex(of: ":") {
            user = userinfo[..<colon]
            password = userinfo[userinfo.index(after: colon)...]
        } else {
            user = userinfo[...]
            password = nil
        }

        guard let encodedUser = String(user).addingPercentEncoding(withAllowedCharacters: userinfoAllowed) else {
            return nil
        }
        guard let password, !password.isEmpty else {
            // Drop an empty ":" separator ("user:@host" → "user@host").
            return encodedUser
        }
        guard let encodedPassword = String(password).addingPercentEncoding(withAllowedCharacters: userinfoAllowed) else {
            return nil
        }
        return encodedUser + ":" + encodedPassword
    }

    // MARK: - Path/query/fragment encoding

    private static func encodeTail(_ tail: String) -> String? {
        guard !tail.isEmpty else { return "/" }

        var path = tail
        var query = ""
        var fragment = ""
        var hasQuery = false
        var hasFragment = false

        if let hash = path.firstIndex(of: "#") {
            hasFragment = true
            fragment = String(path[path.index(after: hash)...])
            path = String(path[..<hash])
        }
        if let question = path.firstIndex(of: "?") {
            hasQuery = true
            query = String(path[path.index(after: question)...])
            path = String(path[..<question])
        }

        guard var encoded = path.addingPercentEncoding(withAllowedCharacters: pathAllowed) else { return nil }
        if encoded.isEmpty { encoded = "/" }

        if hasQuery {
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: queryAllowed) else {
                return nil
            }
            encoded += "?" + encodedQuery
        }
        if hasFragment {
            guard let encodedFragment = fragment.addingPercentEncoding(withAllowedCharacters: fragmentAllowed) else {
                return nil
            }
            encoded += "#" + encodedFragment
        }

        return encoded
    }

    // Existing percent-escapes are preserved: "%" stays in every allowed set,
    // matching the URL standard's lenient reparse of typed input.
    private static let pathAllowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))
    private static let queryAllowed = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%"))
    private static let fragmentAllowed = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "%"))
    private static let userinfoAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~!$&'()*+,;=%")
        return set
    }()
}
