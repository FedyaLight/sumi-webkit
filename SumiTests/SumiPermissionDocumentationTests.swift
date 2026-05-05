import XCTest

final class SumiPermissionDocumentationTests: XCTestCase {
    func testStablePermissionDocsExistAndTemporaryImplementationFileIsAbsent() throws {
        for doc in stableDocNames {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: permissionsDocsURL.appendingPathComponent(doc).path),
                "\(doc) should exist"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: permissionsDocsURL.appendingPathComponent("IMPLEMENTATION_HANDOFF.md").path),
            "Temporary implementation file should not remain in stable permission docs"
        )
    }

    func testStableDocsDoNotContainPromptSequencePhrases() throws {
        let docs = try stableDocsJoined()
        let forbiddenPhrases = [
            "Current Prompt State",
            "Next prompt",
            "next prompt to run",
            "Prompt 1 Implementation Results",
            "Prompt 2 Implementation Results",
            "Prompt 3 Implementation Results",
            "Prompt 4 Implementation Results",
            "Prompt 5 Implementation Results",
            "Prompt 6 Implementation Results",
            "Prompt 7 Implementation Results",
            "Prompt 8 Implementation Results",
            "Prompt 9 Implementation Results",
            "Prompt 10 Implementation Results",
            "Prompt 11 Implementation Results",
            "Prompt 12 Implementation Results",
            "Prompt 13 Implementation Results",
            "Prompt 14 Implementation Results",
            "Prompt 15 Implementation Results",
            "Prompt 16 Implementation Results",
            "Prompt 17 Implementation Results",
            "Prompt 18 Implementation Results",
            "Prompt 19 Implementation Results",
            "Prompt 20 Implementation Results",
            "Prompt 21 Implementation Results",
            "Prompt 22",
            "Codex prompt",
        ]

        for phrase in forbiddenPhrases {
            XCTAssertFalse(docs.contains(phrase), "Stable permission docs contain prompt-sequence phrase: \(phrase)")
        }
    }

    func testReadmeLinksToStableDocs() throws {
        let readme = try docSource("README.md")

        XCTAssertTrue(readme.contains("ARCHITECTURE.md"))
        XCTAssertTrue(readme.contains("TEST_PLAN.md"))
        XCTAssertTrue(readme.contains("LICENSE_NOTES.md"))
        XCTAssertFalse(readme.contains("../../ManualTests/permissions/README.md"))
    }

    func testLicenseNotesPreserveReferenceAndAttributionMarkers() throws {
        let licenseNotes = try docSource("LICENSE_NOTES.md")

        XCTAssertTrue(licenseNotes.contains("DDG"))
        XCTAssertTrue(licenseNotes.contains("Apache 2.0"))
        XCTAssertTrue(licenseNotes.contains("GPL-3.0"))
        XCTAssertTrue(licenseNotes.contains("geolocation ABI header"))
        XCTAssertTrue(licenseNotes.contains("SumiWebKitGeolocationProviderABI.h"))
    }

    func testArchitectureDocumentsScopeAndDeferredWork() throws {
        let architecture = try docSource("ARCHITECTURE.md")

        XCTAssertTrue(architecture.contains("Implemented Normal-Tab Permission Scope"))
        XCTAssertTrue(architecture.contains("camera"))
        XCTAssertTrue(architecture.contains("microphone"))
        XCTAssertTrue(architecture.contains("storageAccess"))
        XCTAssertTrue(architecture.contains("MiniWindow/Glance permission integration"))
        XCTAssertTrue(architecture.contains("Extension permission bridging/UI"))
    }

    func testTestPlanDocumentsManualValidationAndSourceGuards() throws {
        let testPlan = try docSource("TEST_PLAN.md")

        XCTAssertTrue(testPlan.contains("Manual Validation Matrix"))
        XCTAssertTrue(testPlan.contains("Source-Level Regression Guards"))
    }

    private let stableDocNames = [
        "README.md",
        "ARCHITECTURE.md",
        "TEST_PLAN.md",
        "LICENSE_NOTES.md",
    ]

    private var permissionsDocsURL: URL {
        repoRoot.appendingPathComponent("docs/permissions", isDirectory: true)
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func docSource(_ name: String) throws -> String {
        try String(contentsOf: permissionsDocsURL.appendingPathComponent(name), encoding: .utf8)
    }

    private func stableDocsJoined() throws -> String {
        try stableDocNames
            .map(docSource)
            .joined(separator: "\n")
    }
}
