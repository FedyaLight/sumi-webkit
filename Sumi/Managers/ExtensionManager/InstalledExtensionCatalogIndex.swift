import Foundation

@MainActor
final class InstalledExtensionCatalogIndex {
    private var recordsByID: [String: InstalledExtension] = [:]
    private(set) var enabledRecords: [InstalledExtension] = []
    private(set) var enabledContentScriptRecords: [InstalledExtension] = []

    func record(for id: String) -> InstalledExtension? {
        recordsByID[id]
    }

    func rebuild(from records: [InstalledExtension]) {
        recordsByID = Dictionary(
            records.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        enabledRecords = records.filter(\.isEnabled)
        enabledContentScriptRecords = enabledRecords.filter(
            \.hasContentScripts
        )
    }
}

enum InstalledExtensionCatalogIdentity {
    /// Prevents idempotent reloads from invalidating in-flight exact
    /// authority while still covering package and install/enable state.
    static func matches(
        _ lhs: InstalledExtension,
        _ rhs: InstalledExtension
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.version == rhs.version
            && lhs.manifestVersion == rhs.manifestVersion
            && lhs.isEnabled == rhs.isEnabled
            && lhs.installDate == rhs.installDate
            && lhs.packagePath == rhs.packagePath
            && lhs.sourceKind == rhs.sourceKind
            && lhs.incognitoMode == rhs.incognitoMode
            && lhs.sourcePathFingerprint == rhs.sourcePathFingerprint
            && lhs.manifestRootFingerprint == rhs.manifestRootFingerprint
            && lhs.sourceBundlePath == rhs.sourceBundlePath
            && lhs.safariRuntimeIdentity == rhs.safariRuntimeIdentity
    }
}
