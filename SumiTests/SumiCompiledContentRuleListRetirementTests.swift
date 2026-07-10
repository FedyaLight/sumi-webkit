import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiCompiledContentRuleListRetirementTests: XCTestCase {
    func testRetirementForgetsMaterializedIdentifiersAndRemovesStoreOrphans() async {
        let compiler = FakeContentRuleListCompiler()
        let catalog = FakeCompiledContentRuleListCatalog(
            cachedIdentifiers: ["cached-b", "cached-a", "cached-a"],
            orphanedIdentifiers: ["orphan-b", "orphan-a", "orphan-a"]
        )
        let retirement = SumiCompiledContentRuleListRetirement(
            compiler: compiler,
            catalog: catalog
        )
        var forgottenIdentifiers = [String]()

        let task = retirement.retireOrphanedRuleLists(
            replacing: [],
            with: [],
            forgetMaterializedRules: { identifiers in
                forgottenIdentifiers.append(contentsOf: identifiers)
            }
        )
        await task?.value

        XCTAssertEqual(catalog.cachedLookupCallCount, 1)
        XCTAssertEqual(catalog.orphanedLookupCallCount, 1)
        XCTAssertEqual(forgottenIdentifiers, ["cached-a", "cached-b"])
        XCTAssertEqual(compiler.removedIdentifiers, ["orphan-a", "orphan-b"])
    }

    func testRemovalFailureDoesNotStopFollowingIdentifiers() async {
        let compiler = FakeContentRuleListCompiler(
            failingRemovalIdentifiers: ["bad"]
        )
        let retirement = SumiCompiledContentRuleListRetirement(
            compiler: compiler,
            catalog: FakeCompiledContentRuleListCatalog()
        )

        let task = retirement.removeCompiledRuleLists(
            identifiers: ["good", "bad", "bad"],
            reason: "unit-test retirement"
        )
        await task?.value

        XCTAssertEqual(compiler.removedIdentifiers, ["bad", "good"])
        XCTAssertEqual(compiler.failedRemovalIdentifiers, ["bad"])
    }
}

@MainActor
private final class FakeCompiledContentRuleListCatalog:
    SumiCompiledContentRuleListCataloging
{
    private let cachedIdentifiersResult: [String]
    private let orphanedIdentifiersResult: [String]
    private(set) var cachedLookupCallCount = 0
    private(set) var orphanedLookupCallCount = 0

    init(
        cachedIdentifiers: [String] = [],
        orphanedIdentifiers: [String] = []
    ) {
        cachedIdentifiersResult = cachedIdentifiers
        orphanedIdentifiersResult = orphanedIdentifiers
    }

    func cachedIdentifiersToForget(
        replacing _: [SumiContentBlockerRules],
        with _: [SumiContentBlockerRules]
    ) -> [String] {
        cachedLookupCallCount += 1
        return cachedIdentifiersResult
    }

    func orphanedIdentifiers(
        replacing _: [SumiContentBlockerRules],
        with _: [SumiContentBlockerRules]
    ) -> [String] {
        orphanedLookupCallCount += 1
        return orphanedIdentifiersResult
    }

    func forgetIdentifiers(_: [String]) {}
}

@MainActor
private final class FakeContentRuleListCompiler:
    SumiContentRuleListCompiling,
    @unchecked Sendable
{
    private let failingRemovalIdentifiers: Set<String>
    private(set) var removedIdentifiers = [String]()
    private(set) var failedRemovalIdentifiers = [String]()

    init(failingRemovalIdentifiers: Set<String> = []) {
        self.failingRemovalIdentifiers = failingRemovalIdentifiers
    }

    func lookUpContentRuleList(forIdentifier _: String) async -> WKContentRuleList? {
        nil
    }

    func canLookUpContentRuleList(forIdentifier _: String) async -> Bool {
        false
    }

    func compileContentRuleList(
        forIdentifier _: String,
        encodedContentRuleList _: String
    ) async throws -> WKContentRuleList {
        throw FakeContentRuleListCompilerError.unimplemented
    }

    func availableContentRuleListIdentifiers() async -> [String] { [] }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        removedIdentifiers.append(identifier)
        if failingRemovalIdentifiers.contains(identifier) {
            failedRemovalIdentifiers.append(identifier)
            throw FakeContentRuleListCompilerError.removalFailed(identifier)
        }
    }
}

private enum FakeContentRuleListCompilerError: Error {
    case unimplemented
    case removalFailed(String)
}
