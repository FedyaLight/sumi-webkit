import Foundation

public struct SumiPermissionOrigin: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case web
        case file
        case opaque
        case invalid
        case unsupported
    }

    public let kind: Kind
    public let scheme: String?
    public let host: String?
    public let port: Int?
    public let detail: String?

    public init(url: URL?) {
        guard let url else {
            self = .invalid(reason: "missing-url")
            return
        }

        guard let rawScheme = url.scheme?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawScheme.isEmpty
        else {
            self = .invalid(reason: "missing-scheme")
            return
        }

        let scheme = rawScheme.lowercased()

        if scheme == "file" || url.isFileURL {
            self.init(kind: .file, scheme: "file", host: nil, port: nil, detail: nil)
            return
        }

        if Self.opaqueSchemes.contains(scheme) {
            self.init(kind: .opaque, scheme: scheme, host: nil, port: nil, detail: nil)
            return
        }

        guard Self.webSchemes.contains(scheme) else {
            self.init(kind: .unsupported, scheme: scheme, host: nil, port: nil, detail: nil)
            return
        }

        guard let rawHost = url.host(percentEncoded: false) ?? url.host,
              !rawHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            self = .invalid(reason: "missing-host")
            return
        }

        let host = Self.normalizedHost(rawHost)
        let normalizedPort = Self.normalizedPort(url.port, scheme: scheme)
        self.init(kind: .web, scheme: scheme, host: host, port: normalizedPort, detail: nil)
    }

    public init(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self = .invalid(reason: "empty")
            return
        }

        guard let url = URL(string: trimmed) else {
            self = .invalid(reason: "malformed")
            return
        }

        self.init(url: url)
    }

    public init(identity: String) {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "file://" {
            self.init(kind: .file, scheme: "file", host: nil, port: nil, detail: nil)
            return
        }
        if trimmed == "invalid" {
            self = .invalid()
            return
        }
        if trimmed.hasPrefix("opaque:") {
            self = .opaque(scheme: String(trimmed.dropFirst("opaque:".count)))
            return
        }
        if trimmed.hasPrefix("unsupported:") {
            self.init(
                kind: .unsupported,
                scheme: String(trimmed.dropFirst("unsupported:".count)).lowercased(),
                host: nil,
                port: nil,
                detail: nil
            )
            return
        }
        self.init(string: trimmed)
    }

    private init(
        kind: Kind,
        scheme: String?,
        host: String?,
        port: Int?,
        detail: String?
    ) {
        self.kind = kind
        self.scheme = scheme
        self.host = host
        self.port = port
        self.detail = detail
    }

    public static func invalid(reason: String? = nil) -> SumiPermissionOrigin {
        SumiPermissionOrigin(kind: .invalid, scheme: nil, host: nil, port: nil, detail: reason)
    }

    public static func opaque(scheme: String? = nil) -> SumiPermissionOrigin {
        SumiPermissionOrigin(
            kind: .opaque,
            scheme: scheme?.lowercased(),
            host: nil,
            port: nil,
            detail: nil
        )
    }

    public var identity: String {
        switch kind {
        case .web:
            guard let scheme, let host else { return "invalid" }
            return "\(scheme)://\(Self.urlHostComponent(host))\(portComponent)"
        case .file:
            return "file://"
        case .opaque:
            return "opaque:\(scheme ?? "unknown")"
        case .invalid:
            return "invalid"
        case .unsupported:
            return "unsupported:\(scheme ?? "unknown")"
        }
    }

    public var displayDomain: String {
        switch kind {
        case .web:
            guard let host else { return "Invalid Origin" }
            return "\(Self.urlHostComponent(host))\(portComponent)"
        case .file:
            return "Local File"
        case .opaque:
            return "Opaque Origin"
        case .invalid:
            return "Invalid Origin"
        case .unsupported:
            return "Unsupported Origin"
        }
    }

    public var isWebOrigin: Bool {
        kind == .web
    }

    public var isFileOrigin: Bool {
        kind == .file
    }

    public var isOpaque: Bool {
        kind == .opaque
    }

    public var isInvalid: Bool {
        kind == .invalid
    }

    public var isUnsupported: Bool {
        kind == .unsupported
    }

    public var isLocalDevelopmentOrigin: Bool {
        guard kind == .web, let host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    public var isPotentiallyTrustworthy: Bool {
        guard kind == .web else { return false }
        return scheme == "https" || isLocalDevelopmentOrigin
    }

    public func supportsSensitiveWebPermission(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera,
             .microphone,
             .cameraAndMicrophone,
             .geolocation,
             .notifications,
             .screenCapture,
             .storageAccess:
            return isPotentiallyTrustworthy
        case .popups, .externalScheme, .autoplay, .filePicker:
            return isWebOrigin
        }
    }

    private var portComponent: String {
        guard let port else { return "" }
        return ":\(port)"
    }

    private static let webSchemes: Set<String> = ["http", "https"]
    private static let opaqueSchemes: Set<String> = [
        "about",
        "blob",
        "data",
        "javascript",
    ]

    private static func normalizedHost(_ host: String) -> String {
        var normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }
        return normalized
    }

    private static func normalizedPort(_ port: Int?, scheme: String) -> Int? {
        guard let port else { return nil }
        if scheme == "http", port == 80 { return nil }
        if scheme == "https", port == 443 { return nil }
        return port
    }

    private static func urlHostComponent(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }
}
