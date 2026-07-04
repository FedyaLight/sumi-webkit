import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiContentRuleListMaterializerTests: XCTestCase {
    private static let encodedRuleList = """
    [
      {
        "trigger": { "url-filter": ".*sumi-materializer-blocked\\\\.example/.*" },
        "action": { "type": "block" }
      }
    ]
    """

    func testExistingUpdateEventLooksUpAllCompiledListsAndPreservesOrder() async throws {
        let compiler = SumiWKContentRuleListCompiler()
        let suffix = UUID().uuidString
        let identifiers = ["mat-a-\(suffix)", "mat-b-\(suffix)", "mat-c-\(suffix)"]
        for identifier in identifiers {
            _ = try await compiler.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: Self.encodedRuleList
            )
        }

        let materializer = SumiContentRuleListMaterializer(compiler: compiler)
        let definitions = identifiers.map { Self.definition(storeIdentifier: $0) }

        let update = try await materializer.existingUpdateEvent(for: definitions)

        XCTAssertEqual(update.rules.map(\.storeIdentifier), identifiers)
        XCTAssertEqual(update.lookupSucceededIdentifiers, identifiers.sorted())
        XCTAssertTrue(update.lookupFailedIdentifiers.isEmpty)

        for identifier in identifiers {
            try await compiler.removeContentRuleList(forIdentifier: identifier)
        }
    }

    func testExistingUpdateEventThrowsForMissingCompiledList() async throws {
        let compiler = SumiWKContentRuleListCompiler()
        let suffix = UUID().uuidString
        let presentIdentifier = "mat-present-\(suffix)"
        _ = try await compiler.compileContentRuleList(
            forIdentifier: presentIdentifier,
            encodedContentRuleList: Self.encodedRuleList
        )

        let materializer = SumiContentRuleListMaterializer(compiler: compiler)
        let missingIdentifier = "mat-missing-\(suffix)"
        let definitions = [
            Self.definition(storeIdentifier: presentIdentifier),
            Self.definition(storeIdentifier: missingIdentifier),
        ]

        do {
            _ = try await materializer.existingUpdateEvent(for: definitions)
            XCTFail("Expected a missing compiled rule list to throw")
        } catch let error as SumiContentBlockingCompilationError {
            XCTAssertEqual(error.identifier, missingIdentifier)
        }

        try await compiler.removeContentRuleList(forIdentifier: presentIdentifier)
    }

    private static func definition(storeIdentifier: String) -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: storeIdentifier,
            encodedContentRuleList: "",
            storeIdentifierOverride: storeIdentifier,
            contentHashOverride: "hash-\(storeIdentifier)"
        )
    }
}
