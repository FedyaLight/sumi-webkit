import Foundation

enum ChromeMV3RealPackageUsablePopupFixtureLocation {
    static let packageDirectoryName = "mv3-sumi-usable-popup"

    static func packageRoot(file: StaticString = #filePath) -> URL? {
        let repoFixture = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/\(packageDirectoryName)",
                isDirectory: true
            )
        let externalFixture = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/sumi-usable-popup",
            isDirectory: true
        )
        for candidate in [repoFixture, externalFixture] {
            guard FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("manifest.json").path
            ) else {
                continue
            }
            return candidate
        }
        return nil
    }
}
