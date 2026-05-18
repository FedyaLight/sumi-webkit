import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockNativeCSSWebKitSmokeTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testPreparedBundleMayContainNativeCSSOnlyAfterSafetyValidation() throws {
        let bundleURL = temporaryDirectory().appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL, includeNativeCSS: true)

        let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)
        let manifest = bundle.compiledGenerationManifest(previousManifest: nil, installedDate: Date())

        XCTAssertEqual(bundle.manifest.nativeCSSSafetyPolicyVersion, SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion)
        XCTAssertEqual(manifest.networkShards.count, 2)
        XCTAssertEqual(manifest.nativeCSSShards.count, 1)
    }

    func testUnsafePreparedBundlePolicyVersionIsRejectedBeforeUse() throws {
        let bundleURL = temporaryDirectory().appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(
            at: bundleURL,
            includeNativeCSS: true,
            nativeCSSSafetyPolicyVersion: "sumi-native-css-safety/0.3"
        )

        XCTAssertThrowsError(try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("native CSS safety policy"))
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockNativeCSSWebKitSmokeTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
