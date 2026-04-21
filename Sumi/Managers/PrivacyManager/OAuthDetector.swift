import Foundation

enum OAuthDetector {
    private static let knownHosts = [
        "accounts.google.com",
        "appleid.apple.com",
        "github.com",
        "login.microsoftonline.com",
        "auth.openai.com",
        "discord.com",
        "slack.com",
        "x.com",
        "twitter.com",
        "facebook.com",
    ]

    private static let pathFragments = [
        "/oauth",
        "/authorize",
        "/auth",
        "/signin",
        "/login",
        "/consent",
        "/sso",
    ]

    static func isLikelyOAuthPopupURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""

        if knownHosts.contains(where: { host.contains($0) }) {
            return true
        }

        if pathFragments.contains(where: { path.contains($0) }) {
            return true
        }

        let markers = [
            "client_id=",
            "redirect_uri=",
            "response_type=",
            "scope=",
            "code_challenge=",
            "oauth",
            "openid",
        ]

        return markers.contains(where: { query.contains($0) })
    }
}
