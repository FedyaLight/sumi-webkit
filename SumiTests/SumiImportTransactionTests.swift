import XCTest

@testable import Sumi

@MainActor
final class SumiImportTransactionTests: XCTestCase {
    func testMergePlanningIsDeterministicAndIdempotentAcrossRetry() {
        let request = makeMergeRequest()
        let builder = SumiImportPlanBuilder()

        let first = builder.makePlan(request: request, baseline: SumiPortableData())
        let retry = builder.makePlan(request: request, baseline: first.targetRuntimeData)
        let independent = SumiImportPlanBuilder().makePlan(
            request: request,
            baseline: SumiPortableData()
        )

        XCTAssertEqual(retry.targetRuntimeData, first.targetRuntimeData)
        XCTAssertEqual(independent.targetRuntimeData, first.targetRuntimeData)
        XCTAssertEqual(first.targetRuntimeData.profiles.count, 1)
        XCTAssertEqual(first.targetRuntimeData.spaces.count, 1)
        XCTAssertEqual(first.targetRuntimeData.folders.count, 1)
        XCTAssertEqual(first.targetRuntimeData.regularTabs.count, 1)
    }

    func testReplacingProfilesRehomesSurvivingReferencesInsteadOfDroppingData() throws {
        let originalProfileId = UUID().uuidString
        let originalSpaceId = UUID().uuidString
        let baseline = SumiPortableData(
            profiles: [portableProfile(id: originalProfileId, name: "Old")],
            spaces: [portableSpace(id: originalSpaceId, profileId: originalProfileId)],
            regularTabs: [portableTab(id: UUID().uuidString, spaceId: originalSpaceId)]
        )
        let replacement = portableProfile(id: "source-profile", name: "New")
        let request = SumiImportRequest(
            sourceKind: .arc,
            data: SumiPortableData(profiles: [replacement]),
            categories: [.profiles],
            mode: .replace
        )

        let plan = SumiImportPlanBuilder().makePlan(request: request, baseline: baseline)
        let newProfileId = try XCTUnwrap(plan.targetRuntimeData.profiles.first?.id)

        XCTAssertEqual(plan.targetRuntimeData.spaces.first?.profileId, newProfileId)
        XCTAssertEqual(plan.targetRuntimeData.regularTabs.first?.profileId, newProfileId)
        XCTAssertEqual(plan.targetRuntimeData.regularTabs.first?.spaceId, originalSpaceId)
    }

    func testMaterializationPreservesLiveObjectsInUntouchedRuntimeBuckets() throws {
        let browserManager = BrowserManager()
        let profile = Profile(name: "Existing", icon: "person")
        let space = Space(name: "Existing Space", icon: "circle", profileId: profile.id)
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://existing.example")!,
            name: "Existing Tab",
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profile.id
        let checkpoint = SumiImportRuntimeState(
            profiles: [profile],
            currentProfile: profile,
            spaces: [space],
            tabsBySpace: [space.id: [tab]],
            foldersBySpace: [space.id: []],
            pinnedByProfile: [profile.id: []],
            spacePinnedShortcuts: [space.id: []],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: tab
        )
        let baseline = SumiPortableData(
            profiles: [portableProfile(id: profile.id.uuidString, name: profile.name)],
            spaces: [SumiPortableSpace(
                id: space.id.uuidString,
                name: space.name,
                icon: space.icon,
                index: 0,
                profileId: profile.id.uuidString,
                themeDataBase64: space.workspaceTheme.encoded?.base64EncodedString(),
                color: nil
            )],
            regularTabs: [SumiPortableRegularTab(
                id: tab.id.uuidString,
                title: "Stale Snapshot Title",
                urlString: tab.url.absoluteString,
                index: tab.index,
                spaceId: space.id.uuidString,
                profileId: profile.id.uuidString,
                folderId: nil
            )]
        )
        let request = SumiImportRequest(
            sourceKind: .arc,
            data: SumiPortableData(profiles: [portableProfile(id: "new", name: "New")]),
            categories: [.profiles],
            mode: .merge
        )
        let plan = SumiImportPlanBuilder().makePlan(request: request, baseline: baseline)

        let materialized = try SumiImportRuntimeMaterializer(
            tabFactory: browserManager.tabManager.tabFactory,
            tabBrowserRuntime: .inactive
        ).materialize(plan, preserving: checkpoint)

        XCTAssertIdentical(materialized.profiles.first { $0.id == profile.id }, profile)
        XCTAssertIdentical(materialized.spaces.first { $0.id == space.id }, space)
        XCTAssertIdentical(materialized.tabsBySpace[space.id]?.first, tab)
        XCTAssertIdentical(materialized.currentTab, tab)
    }

    func testBookmarkOnlyReplaceIsIdempotentWithoutRuntimeChurn() async throws {
        let fixture = makeTransactionFixture()
        let baseline = SumiPortableData(bookmarks: [bookmarkNode("Before")])
        let replacement = bookmarkNode("Replacement")
        let request = SumiImportRequest(
            sourceKind: .sumiBackup,
            data: SumiPortableData(bookmarks: [replacement]),
            categories: [.bookmarks],
            mode: .replace
        )
        let firstPlan = SumiImportPlanBuilder().makePlan(request: request, baseline: baseline)
        let retryPlan = SumiImportPlanBuilder().makePlan(
            request: request,
            baseline: SumiPortableData(bookmarks: [replacement])
        )

        _ = try await fixture.transaction.commit(firstPlan)
        _ = try await fixture.transaction.commit(retryPlan)

        XCTAssertFalse(retryPlan.hasMutations)
        XCTAssertTrue(fixture.runtime.events.isEmpty)
        XCTAssertEqual(fixture.materializer.callCount, 0)
        XCTAssertEqual(fixture.backup.callCount, 1)
        XCTAssertEqual(fixture.bookmarks.events, ["checkpoint", "commit"])
        XCTAssertEqual(fixture.bookmarks.storedNames, ["Replacement"])
    }

    func testBookmarkPayloadNeverCountsAsRuntimeMutation() {
        let plan = SumiImportPlan(
            baseline: SumiPortableData(bookmarks: [bookmarkNode("Before")]),
            targetRuntimeData: SumiPortableData(bookmarks: [bookmarkNode("After")]),
            bookmarkMutation: .replace([bookmarkNode("After")]),
            categories: [.bookmarks],
            mode: .replace,
            warnings: []
        )

        XCTAssertFalse(plan.changesRuntime)
    }

    func testBookmarkOnlyFailureRestoresPartiallyMutatedBookmarksWithoutRuntimeChurn() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        let baseline = SumiPortableData(bookmarks: [bookmarkNode("Before")])
        let plan = SumiImportPlan(
            baseline: baseline,
            targetRuntimeData: baseline,
            bookmarkMutation: .merge([bookmarkNode("Partial")]),
            categories: [.bookmarks],
            mode: .merge,
            warnings: []
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(plan)
        }

        XCTAssertTrue(fixture.runtime.events.isEmpty)
        XCTAssertEqual(fixture.materializer.callCount, 0)
        XCTAssertEqual(fixture.bookmarks.events, ["checkpoint", "commit", "restore"])
        XCTAssertEqual(fixture.bookmarks.storedNames, ["Before"])
        XCTAssertEqual(fixture.bookmarks.storedIDs, ["before-id"])
    }

    func testBookmarkFailureRestoresRuntimeAndSameTransactionCanRetry() async throws {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(self.mutatingPlan())
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install", "restore"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 1)
        XCTAssertEqual(fixture.bookmarks.events, ["checkpoint", "commit", "restore"])
        XCTAssertEqual(fixture.bookmarks.storedNames, ["Before"])
        XCTAssertEqual(fixture.bookmarks.storedIDs, ["before-id"])

        let report = try await fixture.transaction.commit(mutatingPlan())

        XCTAssertEqual(
            fixture.runtime.events,
            ["checkpoint", "install", "restore", "checkpoint", "install"]
        )
        XCTAssertEqual(fixture.bookmarks.commitCount, 2)
        XCTAssertEqual(
            fixture.bookmarks.events,
            ["checkpoint", "commit", "restore", "checkpoint", "commit"]
        )
        XCTAssertEqual(fixture.bookmarks.storedNames, ["Before", "Example"])
        XCTAssertEqual(report.bookmarkSummary?.successful, 1)
    }

    func testRuntimePersistenceFailureRollsBackBeforeBookmarkMutation() async {
        let fixture = makeTransactionFixture()
        fixture.runtime.installFailuresRemaining = 1

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(self.mutatingPlan())
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install", "restore"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
    }

    func testRollbackFailureIsReportedSeparatelyFromImportFailure() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        fixture.runtime.restoreError = TestImportFailure.rollback

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected rollback failure")
        } catch let error as SumiImportTransactionError {
            guard case .rollbackFailed = error else {
                XCTFail("Expected rollbackFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }
        XCTAssertEqual(fixture.bookmarks.events, ["checkpoint", "commit", "restore"])
        XCTAssertEqual(fixture.bookmarks.storedNames, ["Before"])
    }

    func testBookmarkRollbackFailureStillAttemptsRuntimeRollback() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        fixture.bookmarks.restoreError = TestImportFailure.rollback

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected rollback failure")
        } catch let error as SumiImportTransactionError {
            guard case .rollbackFailed = error else {
                XCTFail("Expected rollbackFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }

        XCTAssertEqual(fixture.bookmarks.events, ["checkpoint", "commit", "restore"])
        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install", "restore"])
    }

    func testReplaceBackupFailurePreventsEveryDurableMutation() async {
        let fixture = makeTransactionFixture()
        fixture.backup.error = TestImportFailure.backup
        let plan = SumiImportPlan(
            baseline: mutatingPlan().baseline,
            targetRuntimeData: mutatingPlan().targetRuntimeData,
            bookmarkMutation: .replace([]),
            categories: [.profiles, .bookmarks],
            mode: .replace,
            warnings: []
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(plan)
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
    }

    func testNoOpPlanDoesNotMaterializeCheckpointBackupOrMutate() async throws {
        let fixture = makeTransactionFixture()
        let baseline = SumiPortableData()
        let plan = SumiImportPlan(
            baseline: baseline,
            targetRuntimeData: baseline,
            bookmarkMutation: .none,
            categories: [],
            mode: .merge,
            warnings: []
        )

        let report = try await fixture.transaction.commit(plan)

        XCTAssertTrue(fixture.runtime.events.isEmpty)
        XCTAssertEqual(fixture.materializer.callCount, 0)
        XCTAssertEqual(fixture.backup.callCount, 0)
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
        XCTAssertTrue(report.appliedCategories.isEmpty)
    }

    private func makeMergeRequest() -> SumiImportRequest {
        let profileId = "source-profile"
        let spaceId = "source-space"
        let folderId = "source-folder"
        return SumiImportRequest(
            sourceKind: .arc,
            data: SumiPortableData(
                profiles: [portableProfile(id: profileId, name: "Work")],
                spaces: [portableSpace(id: spaceId, profileId: profileId)],
                folders: [SumiPortableFolder(
                    id: folderId,
                    name: "Docs",
                    icon: "folder",
                    colorHex: "#112233",
                    spaceId: spaceId,
                    parentFolderId: nil,
                    isOpen: true,
                    index: 0,
                    sourcePath: ["Docs"]
                )],
                pinnedLaunchers: [SumiPortableLauncher(
                    id: "source-pin",
                    title: "Pinned",
                    urlString: "https://pinned.example",
                    index: 0,
                    profileId: profileId,
                    executionProfileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    iconAsset: nil,
                    sourceSpaceId: spaceId
                )],
                regularTabs: [portableTab(id: "source-tab", spaceId: spaceId)]
            ),
            categories: [.profiles, .spaces, .folders, .pinnedLaunchers, .regularTabs],
            mode: .merge
        )
    }

    private func mutatingPlan() -> SumiImportPlan {
        let baselineBookmarks = [bookmarkNode("Before")]
        let baseline = SumiPortableData(
            profiles: [portableProfile(id: UUID().uuidString, name: "Before")],
            bookmarks: baselineBookmarks
        )
        let target = SumiPortableData(
            profiles: [portableProfile(id: UUID().uuidString, name: "After")],
            bookmarks: baselineBookmarks
        )
        return SumiImportPlan(
            baseline: baseline,
            targetRuntimeData: target,
            bookmarkMutation: .merge([SumiPortableBookmarkNode(
                name: "Example",
                kind: .bookmark,
                urlString: "https://example.com",
                children: []
            )]),
            categories: [.profiles, .bookmarks],
            mode: .merge,
            warnings: []
        )
    }

    private func bookmarkNode(_ name: String) -> SumiPortableBookmarkNode {
        SumiPortableBookmarkNode(
            name: name,
            kind: .bookmark,
            urlString: "https://\(name.lowercased()).example",
            children: []
        )
    }

    private func portableProfile(id: String, name: String) -> SumiPortableProfile {
        SumiPortableProfile(id: id, name: name, icon: "person", index: 0)
    }

    private func portableSpace(id: String, profileId: String) -> SumiPortableSpace {
        SumiPortableSpace(
            id: id,
            name: "Space",
            icon: "circle",
            index: 0,
            profileId: profileId,
            themeDataBase64: nil,
            color: nil
        )
    }

    private func portableTab(id: String, spaceId: String) -> SumiPortableRegularTab {
        SumiPortableRegularTab(
            id: id,
            title: "Tab",
            urlString: "https://tab.example",
            index: 0,
            spaceId: spaceId,
            profileId: nil,
            folderId: nil
        )
    }

    private func makeTransactionFixture() -> TransactionFixture {
        let checkpoint = emptyRuntimeState()
        let target = emptyRuntimeState()
        let materializer = RecordingImportMaterializer(state: target)
        let runtime = RecordingImportRuntime(checkpoint: checkpoint)
        let bookmarks = RecordingImportBookmarks()
        let backup = RecordingImportBackup()
        return TransactionFixture(
            transaction: SumiImportTransaction(
                materializer: materializer,
                runtime: runtime,
                bookmarks: bookmarks,
                backupWriter: backup
            ),
            materializer: materializer,
            runtime: runtime,
            bookmarks: bookmarks,
            backup: backup
        )
    }

    private func emptyRuntimeState() -> SumiImportRuntimeState {
        SumiImportRuntimeState(
            profiles: [],
            currentProfile: nil,
            spaces: [],
            tabsBySpace: [:],
            foldersBySpace: [:],
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: nil,
            currentTab: nil
        )
    }
}

@MainActor
private struct TransactionFixture {
    let transaction: SumiImportTransaction
    let materializer: RecordingImportMaterializer
    let runtime: RecordingImportRuntime
    let bookmarks: RecordingImportBookmarks
    let backup: RecordingImportBackup
}

@MainActor
private final class RecordingImportMaterializer: SumiImportRuntimeMaterializing {
    let state: SumiImportRuntimeState
    private(set) var callCount = 0

    init(state: SumiImportRuntimeState) {
        self.state = state
    }

    func materialize(
        _ plan: SumiImportPlan,
        preserving checkpoint: SumiImportRuntimeState
    ) throws -> SumiImportRuntimeState {
        callCount += 1
        return state
    }
}

@MainActor
private final class RecordingImportRuntime: SumiImportRuntimeMutating {
    let savedCheckpoint: SumiImportRuntimeState
    var events: [String] = []
    var installFailuresRemaining = 0
    var restoreError: Error?

    init(checkpoint: SumiImportRuntimeState) {
        savedCheckpoint = checkpoint
    }

    func checkpoint() -> SumiImportRuntimeState {
        events.append("checkpoint")
        return savedCheckpoint
    }

    func install(_ state: SumiImportRuntimeState) async throws {
        events.append("install")
        if installFailuresRemaining > 0 {
            installFailuresRemaining -= 1
            throw TestImportFailure.install
        }
    }

    func restore(_ checkpoint: SumiImportRuntimeState) async throws {
        events.append("restore")
        if let restoreError { throw restoreError }
    }
}

@MainActor
private final class RecordingImportBookmarks: SumiImportBookmarkMutating {
    var failuresRemaining = 0
    var restoreError: Error?
    private(set) var commitCount = 0
    private(set) var events: [String] = []
    private(set) var storedNames = ["Before"]
    private(set) var storedIDs = ["before-id"]

    func checkpoint() -> SumiBookmarksSnapshot {
        events.append("checkpoint")
        let children = zip(storedIDs, storedNames).map { id, name in
            SumiBookmarkEntity(
                id: id,
                kind: .bookmark,
                title: name,
                url: URL(string: "https://\(name.lowercased()).example"),
                parentID: SumiBookmarkConstants.rootFolderID,
                parentTitle: "Bookmarks",
                children: [],
                childBookmarkCount: 0
            )
        }
        let root = SumiBookmarkEntity(
            id: SumiBookmarkConstants.rootFolderID,
            kind: .folder,
            title: "Bookmarks",
            url: nil,
            parentID: nil,
            parentTitle: nil,
            children: children,
            childBookmarkCount: children.count
        )
        return SumiBookmarksSnapshot(
            root: root,
            flattenedFolders: [],
            entitiesByID: Dictionary(
                uniqueKeysWithValues: ([root] + children).map { ($0.id, $0) }
            )
        )
    }

    func commit(_ mutation: SumiImportBookmarkMutation) throws -> SumiBookmarksImportSummary? {
        events.append("commit")
        commitCount += 1
        switch mutation {
        case .none:
            return nil
        case .merge(let nodes):
            storedNames.append(contentsOf: nodes.map(\.name))
            storedIDs.append(contentsOf: nodes.map { "import-\($0.name)" })
        case .replace(let nodes):
            storedNames = nodes.map(\.name)
            storedIDs = nodes.map { "import-\($0.name)" }
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw TestImportFailure.bookmarks
        }
        return SumiBookmarksImportSummary(successful: 1, duplicates: 0, failed: 0)
    }

    func restore(_ checkpoint: SumiBookmarksSnapshot) throws {
        events.append("restore")
        if let restoreError { throw restoreError }
        storedNames = checkpoint.root.children.map(\.title)
        storedIDs = checkpoint.root.children.map(\.id)
    }
}

@MainActor
private final class RecordingImportBackup: SumiImportBackupWriting {
    var error: Error?
    private(set) var callCount = 0

    func writeAutomaticPreRestoreBackup(data: SumiPortableData) throws -> URL {
        callCount += 1
        if let error { throw error }
        return URL(fileURLWithPath: "/tmp/import-backup.sumibackup")
    }
}

private enum TestImportFailure: LocalizedError {
    case install
    case bookmarks
    case backup
    case rollback
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @MainActor () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
