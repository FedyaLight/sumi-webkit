import Foundation

/// Serializes installation attempts by canonical source identity before an
/// extension ID exists. The runtime mutation registry takes over after ID
/// resolution.
@MainActor
final class ExtensionInstallationAdmission {
    struct Claim: Equatable {
        fileprivate let sourcePath: String
        fileprivate let token: UUID
    }

    private var tokensBySourcePath: [String: UUID] = [:]

    func begin(sourceBundleURL: URL) -> Claim? {
        let sourcePath = ExtensionInstallationIdentityResolver
            .canonicalSourcePath(sourceBundleURL)
        guard tokensBySourcePath[sourcePath] == nil else { return nil }
        let token = UUID()
        tokensBySourcePath[sourcePath] = token
        return Claim(sourcePath: sourcePath, token: token)
    }

    @discardableResult
    func finish(_ claim: Claim) -> Bool {
        guard tokensBySourcePath[claim.sourcePath] == claim.token else {
            return false
        }
        tokensBySourcePath.removeValue(forKey: claim.sourcePath)
        return true
    }
}
