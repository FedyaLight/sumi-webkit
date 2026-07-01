import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ContentRuleListCleanupOwnerTests: XCTestCase {
    func testOrphanedCleanupForgetsCachedIdentifiersAndRemovesStoreOrphans() async {
        let compiler = FakeContentRuleListCompiler()
        let catalog = FakeCompiledContentRuleListCatalog(
            cachedIdentifiers: ["cached-b", "cached-a", "cached-a"],
            orphanedIdentifiers: ["orphan-b", "orphan-a", "orphan-a"]
        )
        let owner = SumiCompiledContentRuleListCleanupOwner(
            compiler: compiler,
            catalog: catalog
        )
        var forgottenIdentifiers = [String]()

        let cleanupTask = owner.cleanupOrphanedCompiledRuleLists(
            replacing: [],
            with: []
        ) { identifiers in
            forgottenIdentifiers.append(contentsOf: identifiers)
        }
        await cleanupTask?.value

        XCTAssertEqual(catalog.cachedLookupCallCount, 1)
        XCTAssertEqual(catalog.orphanedLookupCallCount, 1)
        XCTAssertEqual(forgottenIdentifiers, ["cached-a", "cached-b"])
        XCTAssertEqual(compiler.removedIdentifiers, ["orphan-a", "orphan-b"])
    }

    func testStoreRemovalFailureDoesNotStopFollowingRemovals() async {
        let compiler = FakeContentRuleListCompiler(failingRemovalIdentifiers: ["bad"])
        let owner = SumiCompiledContentRuleListCleanupOwner(
            compiler: compiler,
            catalog: FakeCompiledContentRuleListCatalog()
        )

        let cleanupTask = owner.removeCompiledRuleListsFromStore(
            withIdentifiers: ["good", "bad", "bad"],
            reason: "unit-test cleanup"
        )
        await cleanupTask?.value

        XCTAssertEqual(compiler.removedIdentifiers, ["bad", "good"])
        XCTAssertEqual(compiler.failedRemovalIdentifiers, ["bad"])
    }
}

@MainActor
private final class FakeCompiledContentRuleListCatalog: SumiCompiledContentRuleListCataloging {
    private let cachedIdentifiersResult: [String]
    private let orphanedIdentifiersResult: [String]
    private(set) var cachedLookupCallCount = 0
    private(set) var orphanedLookupCallCount = 0
    private(set) var forgottenIdentifiers = [String]()

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

    func forgetIdentifiers(_ identifiers: [String]) {
        forgottenIdentifiers.append(contentsOf: identifiers)
    }
}

@MainActor
private final class FakeContentRuleListCompiler: SumiContentRuleListCompiling, @unchecked Sendable {
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

    func availableContentRuleListIdentifiers() async -> [String] {
        []
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        removedIdentifiers.append(identifier)
        if failingRemovalIdentifiers.contains(identifier) {
            failedRemovalIdentifiers.append(identifier)
            throw FakeContentRuleListCompilerError.removalFailed(identifier)
        }
    }
}

private enum FakeContentRuleListCompilerError: Error, LocalizedError, Equatable {
    case unimplemented
    case removalFailed(String)

    var errorDescription: String? {
        switch self {
        case .unimplemented:
            return "Fake compiler does not compile rule lists."
        case .removalFailed(let identifier):
            return "Failed to remove \(identifier)."
        }
    }
}
