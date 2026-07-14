import Foundation
import OSLog
import WebKit

@available(macOS 15.5, *)
@MainActor
enum ExtensionOptionsPageResolver {
    private static let log = Logger.sumi(category: "Extensions")

    struct Resolution {
        let presentationURL: URL
        let packageURL: URL
        let extensionRoot: URL
    }

    /// Resolves one URL through both authorities that matter: WebKit must map
    /// the SDK URL to the exact callback context, and its path must name a real
    /// file inside the exact installed package root. There is deliberately no
    /// raw base-URL, manifest, or persisted-path fallback after SDK rejection.
    @available(macOS 15.5, *)
    static func resolve(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        installedExtension: InstalledExtension
    ) -> Resolution? {
        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        do {
            guard let sdkURL = context.optionsPageURL,
                  ExtensionURLIdentity.isOwned(sdkURL),
                  controller.extensionContext(for: sdkURL) === context,
                  let relativePath = relativePath(from: sdkURL),
                  let candidate = ExtensionPathSafety.manifestRelativeURL(
                      extensionRoot,
                      path: relativePath
                  )
            else {
                return nil
            }
            let packageURL = try ExtensionPathSafety.validatedPageURL(
                candidate,
                within: extensionRoot
            )
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                return nil
            }
            return Resolution(
                presentationURL: sdkURL,
                packageURL: packageURL,
                extensionRoot: extensionRoot
            )
        } catch {
            log.error(
                "Rejected options URL for extension \(installedExtension.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func relativePath(from url: URL) -> String? {
        let encodedPath = url.path(percentEncoded: true)
        let trimmed = encodedPath.drop(while: { $0 == "/" })
        guard trimmed.isEmpty == false,
              let decoded = String(trimmed).removingPercentEncoding,
              decoded.isEmpty == false
        else {
            return nil
        }
        return decoded
    }
}
