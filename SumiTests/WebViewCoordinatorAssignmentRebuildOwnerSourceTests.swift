import XCTest

final class WebViewCoordinatorAssignmentRebuildOwnerSourceTests: XCTestCase {
    func testNormalAssignmentAndRebuildPathIsOwnedOutsideCoordinator() throws {
        let coordinatorSource = try Self.source(
            named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
        )
        let ownerSource = try Self.source(
            named: "Sumi/Managers/WebViewCoordinator/WebViewAssignmentRebuildOwner.swift"
        )

        XCTAssertTrue(coordinatorSource.contains("private let webViewAssignmentRebuildOwner = WebViewAssignmentRebuildOwner()"))
        XCTAssertTrue(coordinatorSource.contains("runtime: assignmentRebuildRuntime()"))
        XCTAssertFalse(coordinatorSource.contains("private let webViewCreationPlanningOwner = WebViewCreationPlanningOwner()"))
        XCTAssertFalse(coordinatorSource.contains("private func createPrimaryWebView("))
        XCTAssertFalse(coordinatorSource.contains("private func createCloneWebView("))
        XCTAssertFalse(coordinatorSource.contains("private func loadInitialURLIfNeeded("))
        XCTAssertFalse(coordinatorSource.contains("private func adoptExistingPrimaryWebView("))

        XCTAssertTrue(ownerSource.contains("private let creationPlanningOwner = WebViewCreationPlanningOwner()"))
        XCTAssertTrue(ownerSource.contains("func getOrCreateWebView("))
        XCTAssertTrue(ownerSource.contains("func rebuildLiveWebViews("))
        XCTAssertTrue(ownerSource.contains("func refreshPrimaryTrackedWebView("))
        XCTAssertTrue(ownerSource.contains("private func createPrimaryWebView("))
        XCTAssertTrue(ownerSource.contains("private func createCloneWebView("))
        XCTAssertTrue(ownerSource.contains("private func loadInitialURLIfNeeded("))
        XCTAssertTrue(ownerSource.contains("private func adoptExistingPrimaryWebView("))
    }

    func testAssignmentRebuildOwnerDoesNotOwnProtectedCommandOrMediaSystems() throws {
        let ownerSource = try Self.source(
            named: "Sumi/Managers/WebViewCoordinator/WebViewAssignmentRebuildOwner.swift"
        )

        XCTAssertFalse(ownerSource.contains("enqueueDeferredProtectedCommand("))
        XCTAssertFalse(ownerSource.contains("WebViewMediaProtectionOwner"))
        XCTAssertFalse(ownerSource.contains("WebViewDeferredProtectedCommandExecutionOwner"))
        XCTAssertFalse(ownerSource.contains("WebViewDestructiveCleanupPreparationOwner"))
        XCTAssertFalse(ownerSource.contains("WebViewTrackedCleanupExecutionOwner"))
    }

    private static func source(named relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
