import Foundation

struct SumiSecurityOrigin: Hashable, Sendable {
    let `protocol`: String
    let host: String
    let port: Int

    init(`protocol`: String, host: String, port: Int) {
        self.`protocol` = `protocol`
        self.host = host
        self.port = port
    }

    init(url: URL?) {
        self.init(
            protocol: url?.scheme ?? "",
            host: url?.host ?? "",
            port: url?.port ?? 0
        )
    }

    static let empty = SumiSecurityOrigin(protocol: "", host: "", port: 0)

    func permissionOrigin(missingReason: String) -> SumiPermissionOrigin {
        let scheme = self.`protocol`.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = self.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, !host.isEmpty else {
            return .invalid(reason: missingReason)
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if port > 0 {
            components.port = port
        }
        return SumiPermissionOrigin(url: components.url)
    }
}
