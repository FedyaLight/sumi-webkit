import Foundation

enum ExtensionDisplayNameResolver {
    static func displayName(
        for extensionID: String?,
        installedExtensions: [InstalledExtension]
    ) -> String? {
        guard let extensionID,
              let extensionRecord = installedExtensions.first(where: {
                  $0.id == extensionID
              })
        else { return nil }

        let name = extensionRecord.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return name.isEmpty ? nil : name
    }

    static func displayName(
        forOwnedURL url: URL?,
        installedExtensions: [InstalledExtension]
    ) -> String? {
        displayName(
            for: ExtensionURLIdentity.extensionID(from: url),
            installedExtensions: installedExtensions
        )
    }
}
