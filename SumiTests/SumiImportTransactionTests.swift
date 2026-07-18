import SumiDomain
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
        let profile = Profile(name: "Existing")
        let space = Space(name: "Existing Space", icon: "circle", profileId: profile.id)
        let tab = browserManager.tabFactory.makeTab(
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
            profiles: [portableProfile(id: profile.id.uuidString, name: "Stale Profile Snapshot")],
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
            data: SumiPortableData(profiles: [
                portableProfile(id: profile.id.uuidString, name: profile.name),
            ]),
            categories: [.profiles],
            mode: .replace
        )
        let plan = SumiImportPlanBuilder().makePlan(request: request, baseline: baseline)

        let materialized = try SumiImportRuntimeMaterializer(
            tabFactory: browserManager.tabFactory,
            tabBrowserRuntime: .inactive
        ).materialize(plan, preserving: checkpoint)

        XCTAssertIdentical(materialized.profiles.first { $0.id == profile.id }, profile)
        XCTAssertIdentical(materialized.spaces.first { $0.id == space.id }, space)
        XCTAssertIdentical(materialized.tabsBySpace[space.id]?.first, tab)
        XCTAssertIdentical(materialized.currentTab, tab)
    }

    func testMaterializationBuildsProfileIdentityReplacementForDurableReconciliation() throws {
        let browserManager = BrowserManager()
        let profile = Profile(name: "Existing")
        let checkpoint = SumiImportRuntimeState(
            profiles: [profile],
            currentProfile: profile,
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
        let plan = SumiImportPlan(
            baseline: SumiPortableData(profiles: [
                portableProfile(id: profile.id.uuidString, name: profile.name),
            ]),
            targetRuntimeData: SumiPortableData(profiles: [
                portableProfile(id: UUID().uuidString, name: "Replacement"),
            ]),
            bookmarkMutation: .none,
            categories: [.profiles],
            mode: .replace,
            warnings: []
        )

        let materialized = try SumiImportRuntimeMaterializer(
            tabFactory: browserManager.tabFactory,
            tabBrowserRuntime: .inactive
        ).materialize(plan, preserving: checkpoint)

        XCTAssertEqual(materialized.profiles.map(\.name), ["Replacement"])
        XCTAssertNotEqual(materialized.profiles.first?.id, profile.id)
    }

    func testReplaceProfilePlanningReusesLocalIdentitiesAndRetiresOnlySurplus() throws {
        let firstID = "11111111-1111-1111-1111-111111111111"
        let secondID = "22222222-2222-2222-2222-222222222222"
        let baseline = SumiPortableData(profiles: [
            portableProfile(id: firstID, name: "First Local"),
            portableProfile(id: secondID, name: "Second Local"),
        ])
        let sourceID = UUID().uuidString
        let request = SumiImportRequest(
            sourceKind: .sumiBackup,
            data: SumiPortableData(profiles: [
                portableProfile(id: sourceID, name: "Restored"),
            ]),
            categories: [.profiles],
            mode: .replace
        )

        let plan = SumiImportPlanBuilder().makePlan(
            request: request,
            baseline: baseline
        )

        XCTAssertEqual(plan.targetRuntimeData.profiles.map(\.id), [firstID])
        XCTAssertEqual(
            plan.profileTransition.sourceToTargetProfileID[sourceID],
            firstID
        )
        XCTAssertTrue(plan.profileTransition.createdProfileIDs.isEmpty)
        XCTAssertEqual(
            plan.profileTransition.retiringProfileIDs,
            Set([try XCTUnwrap(UUID(uuidString: secondID))])
        )
    }

    func testMergeProfilePlanningAddsIdentityWithoutRetiringLocalProfiles() throws {
        let localID = UUID().uuidString
        let request = makeMergeRequest()
        let plan = SumiImportPlanBuilder().makePlan(
            request: request,
            baseline: SumiPortableData(profiles: [
                portableProfile(id: localID, name: "Local"),
            ])
        )

        XCTAssertEqual(plan.targetRuntimeData.profiles.count, 2)
        XCTAssertEqual(plan.targetRuntimeData.profiles.first?.id, localID)
        XCTAssertEqual(plan.profileTransition.createdProfileIDs.count, 1)
        XCTAssertTrue(plan.profileTransition.retiringProfileIDs.isEmpty)
    }

    func testMergeProfilePlanningDoesNotReuseBlockedProfileIdentity() throws {
        let request = makeMergeRequest()
        let first = SumiImportPlanBuilder().makePlan(
            request: request,
            baseline: SumiPortableData()
        )
        let blockedID = try XCTUnwrap(
            first.profileTransition.createdProfileIDs.first
        )

        let remapped = SumiImportPlanBuilder(
            isProfileIdentityAllowed: { $0 != blockedID }
        ).makePlan(
            request: request,
            baseline: SumiPortableData()
        )

        XCTAssertFalse(
            remapped.profileTransition.createdProfileIDs.contains(blockedID)
        )
        XCTAssertEqual(remapped.profileTransition.createdProfileIDs.count, 1)
    }

    func testMaterializationUsesCheckedWorkspaceThemeBytesBeforeStructuredFallback() throws {
        let browserManager = BrowserManager()
        let profileID = UUID()
        let spaceID = UUID()
        let themeBytes = try XCTUnwrap(
            Data(base64Encoded: Self.currentThemeFixtureBase64)
        )
        let portableData = SumiPortableData(
            profiles: [portableProfile(id: profileID.uuidString, name: "Theme Profile")],
            spaces: [
                SumiPortableSpace(
                    id: spaceID.uuidString,
                    name: "Theme Space",
                    icon: "circle",
                    index: 0,
                    profileId: profileID.uuidString,
                    themeDataBase64: Self.currentThemeFixtureBase64,
                    color: SumiPortableRGBColor(r: 1, g: 0, b: 0)
                ),
            ]
        )
        let plan = SumiImportPlan(
            baseline: SumiPortableData(),
            targetRuntimeData: portableData,
            bookmarkMutation: .none,
            categories: [.profiles, .spaces, .themes],
            mode: .replace,
            warnings: []
        )
        let checkpoint = SumiImportRuntimeState(
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

        let materialized = try SumiImportRuntimeMaterializer(
            tabFactory: browserManager.tabFactory,
            tabBrowserRuntime: .inactive
        ).materialize(plan, preserving: checkpoint)

        let expectedTheme = try XCTUnwrap(WorkspaceTheme.decode(themeBytes))
        let importedTheme = try XCTUnwrap(materialized.spaces.first?.workspaceTheme)
        XCTAssertEqual(importedTheme, expectedTheme)
        XCTAssertEqual(importedTheme.gradientTheme.colors.first?.hex, "#445566")
        XCTAssertNotEqual(importedTheme.gradientTheme.colors.first?.hex, "#FF0000")
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

    func testRuntimeMutationSessionSpansBookmarkCommitAndClosesAfterCommit() async throws {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.onCommit = {
            XCTAssertTrue(fixture.runtime.isMutationActive)
        }

        _ = try await fixture.transaction.commit(mutatingPlan())

        XCTAssertFalse(fixture.runtime.isMutationActive)
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
            guard case .commitFailed = error else {
                XCTFail("Expected commitFailed, got \(error)")
                return
            }
            XCTAssertEqual(error.rollbackErrors.count, 1)
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
            guard case .commitFailed = error else {
                XCTFail("Expected commitFailed, got \(error)")
                return
            }
            XCTAssertEqual(error.rollbackErrors.count, 1)
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

    func testFailureResultIncludesPreRestoreBackupURL() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1

        do {
            _ = try await fixture.transaction.commit(replaceMutatingPlan())
            XCTFail("Expected import failure")
        } catch let error as SumiImportTransactionError {
            guard case .commitFailed = error else {
                XCTFail("Expected commitFailed, got \(error)")
                return
            }
            XCTAssertEqual(
                error.preRestoreBackupURL,
                URL(fileURLWithPath: "/tmp/import-backup.sumibackup")
            )
            XCTAssertTrue(error.rollbackErrors.isEmpty)
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }
    }

    func testAllRollbackErrorsAreReportedAndJournalRemainsRecoverable() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        fixture.bookmarks.restoreError = TestImportFailure.bookmarkRollback
        fixture.runtime.restoreError = TestImportFailure.runtimeRollback

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected rollback failure")
        } catch let error as SumiImportTransactionError {
            guard case .commitFailed = error else {
                XCTFail("Expected commitFailed, got \(error)")
                return
            }
            XCTAssertEqual(error.rollbackErrors.count, 2)
            XCTAssertEqual(
                error.rollbackErrors.compactMap { $0 as? TestImportFailure },
                [.bookmarkRollback, .runtimeRollback]
            )
            XCTAssertEqual(fixture.journal.record?.phase, .compensating)
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }

        XCTAssertEqual(fixture.bookmarks.events.suffix(1), ["restore"])
        XCTAssertEqual(fixture.runtime.events.suffix(1), ["restore"])
    }

    func testJournalTransitionAndBothResourceRollbackErrorsAreAllReported() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        fixture.journal.saveErrors[.compensating] = TestImportFailure.journal
        fixture.bookmarks.restoreError = TestImportFailure.bookmarkRollback
        fixture.runtime.restoreError = TestImportFailure.runtimeRollback

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected rollback failure")
        } catch let error as SumiImportTransactionError {
            XCTAssertEqual(
                error.rollbackErrors.compactMap { $0 as? TestImportFailure },
                [.journal, .bookmarkRollback, .runtimeRollback]
            )
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }
    }

    func testPreparedJournalFailureIncludesCreatedBackupWithoutMutating() async {
        let fixture = makeTransactionFixture()
        fixture.journal.saveErrors[.prepared] = TestImportFailure.journal

        do {
            _ = try await fixture.transaction.commit(replaceMutatingPlan())
            XCTFail("Expected journal failure")
        } catch let error as SumiImportTransactionError {
            XCTAssertEqual(
                error.preRestoreBackupURL,
                URL(fileURLWithPath: "/tmp/import-backup.sumibackup")
            )
            XCTAssertTrue(error.rollbackErrors.isEmpty)
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint"])
        XCTAssertFalse(fixture.runtime.events.contains("install"))
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
    }

    func testInjectedCrashAtEveryForwardPhaseRecoversOnNextTransaction() async throws {
        let phases: [SumiImportTransactionPhase] = [
            .prepared,
            .runtimeCommitted,
            .bookmarksCommitted,
            .completed,
        ]

        for phase in phases {
            let fixture = makeTransactionFixture()
            let interrupted = fixture.makeTransaction(
                interrupting: .phasePersisted(phase)
            )

            await XCTAssertThrowsErrorAsync {
                _ = try await interrupted.commit(self.mutatingPlan())
            }

            XCTAssertEqual(fixture.journal.record?.phase, phase, "phase=\(phase)")
            let runtimeRestoreCount = fixture.runtime.events.filter { $0 == "restore" }.count
            let bookmarkRestoreCount = fixture.bookmarks.events.filter { $0 == "restore" }.count

            let report = try await fixture.makeTransaction().recoverIfNeeded()

            XCTAssertNotNil(report, "phase=\(phase)")
            XCTAssertNil(fixture.journal.record, "phase=\(phase)")
            if phase == .completed {
                XCTAssertEqual(
                    fixture.runtime.events.filter { $0 == "restore" }.count,
                    runtimeRestoreCount,
                    "phase=\(phase)"
                )
                XCTAssertEqual(
                    fixture.bookmarks.events.filter { $0 == "restore" }.count,
                    bookmarkRestoreCount,
                    "phase=\(phase)"
                )
            } else {
                XCTAssertEqual(
                    fixture.runtime.events.filter { $0 == "restore" }.count,
                    runtimeRestoreCount + 1,
                    "phase=\(phase)"
                )
                XCTAssertEqual(
                    fixture.bookmarks.events.filter { $0 == "restore" }.count,
                    bookmarkRestoreCount + 1,
                    "phase=\(phase)"
                )
                XCTAssertEqual(fixture.bookmarks.storedIDs, ["before-id"])
            }
        }
    }

    func testInjectedCrashBetweenDurableEffectsAndPhaseWritesRecovers() async throws {
        let cases: [(SumiImportTransactionFaultPoint, SumiImportTransactionPhase)] = [
            (.runtimeInstalled, .prepared),
            (.bookmarksMutated, .runtimeCommitted),
        ]

        for (faultPoint, expectedPhase) in cases {
            let fixture = makeTransactionFixture()

            await XCTAssertThrowsErrorAsync {
                _ = try await fixture.makeTransaction(interrupting: faultPoint)
                    .commit(self.mutatingPlan())
            }

            XCTAssertEqual(fixture.journal.record?.phase, expectedPhase)
            _ = try await fixture.makeTransaction().recoverIfNeeded()
            XCTAssertNil(fixture.journal.record)
            XCTAssertEqual(fixture.runtime.events.suffix(2), ["checkpoint", "restore"])
            XCTAssertEqual(fixture.bookmarks.storedIDs, ["before-id"])
        }
    }

    func testInjectedCrashAtCompensatingPhaseRecoversOnNextTransaction() async throws {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        let interrupted = fixture.makeTransaction(
            interrupting: .phasePersisted(.compensating)
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await interrupted.commit(self.mutatingPlan())
        }

        XCTAssertEqual(fixture.journal.record?.phase, .compensating)
        XCTAssertFalse(fixture.runtime.events.contains("restore"))
        XCTAssertFalse(fixture.bookmarks.events.contains("restore"))

        let report = try await fixture.makeTransaction().recoverIfNeeded()

        XCTAssertNotNil(report)
        XCTAssertNil(fixture.journal.record)
        XCTAssertEqual(fixture.runtime.events.suffix(2), ["checkpoint", "restore"])
        XCTAssertEqual(fixture.bookmarks.events.suffix(1), ["restore"])
        XCTAssertEqual(fixture.bookmarks.storedIDs, ["before-id"])
    }

    func testRecoveryCanResumeAfterEveryCompensationBoundary() async throws {
        let faultPoints: [SumiImportTransactionFaultPoint] = [
            .phasePersisted(.compensating),
            .bookmarksCompensated,
            .runtimeCompensated,
            .phasePersisted(.completed),
        ]

        for faultPoint in faultPoints {
            let fixture = makeTransactionFixture()
            await XCTAssertThrowsErrorAsync {
                _ = try await fixture.makeTransaction(interrupting: .runtimeInstalled)
                    .commit(self.mutatingPlan())
            }

            await XCTAssertThrowsErrorAsync {
                _ = try await fixture.makeTransaction(interrupting: faultPoint)
                    .recoverIfNeeded()
            }

            _ = try await fixture.makeTransaction().recoverIfNeeded()
            XCTAssertNil(fixture.journal.record, "faultPoint=\(faultPoint)")
            XCTAssertEqual(fixture.bookmarks.storedIDs, ["before-id"])
        }
    }

    func testCompensationCompletedTransitionIsCrashRecoverable() async throws {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeTransaction(
                interrupting: .phasePersisted(.completed)
            ).commit(self.mutatingPlan())
        }

        XCTAssertEqual(fixture.journal.record?.phase, .completed)
        let runtimeRestoreCount = fixture.runtime.events.filter { $0 == "restore" }.count
        let bookmarkRestoreCount = fixture.bookmarks.events.filter { $0 == "restore" }.count

        _ = try await fixture.makeTransaction().recoverIfNeeded()

        XCTAssertNil(fixture.journal.record)
        XCTAssertEqual(
            fixture.runtime.events.filter { $0 == "restore" }.count,
            runtimeRestoreCount
        )
        XCTAssertEqual(
            fixture.bookmarks.events.filter { $0 == "restore" }.count,
            bookmarkRestoreCount
        )
    }

    func testConcurrentTransactionsCannotOverwriteActiveJournal() async throws {
        let fixture = makeTransactionFixture()
        let installSuspended = expectation(description: "first install suspended")
        fixture.runtime.suspendNextInstall {
            installSuspended.fulfill()
        }

        let first = Task { @MainActor in
            try await fixture.transaction.commit(self.mutatingPlan())
        }
        await fulfillment(of: [installSuspended], timeout: 1)

        let secondStarted = expectation(description: "second transaction started")
        let second = Task { @MainActor in
            secondStarted.fulfill()
            try await fixture.makeTransaction().commit(self.mutatingPlan())
        }
        await fulfillment(of: [secondStarted], timeout: 1)
        await Task.yield()

        XCTAssertEqual(fixture.journal.savedPhases, [.prepared])
        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install"])

        fixture.runtime.resumeSuspendedInstall()
        _ = try await first.value
        _ = try await second.value

        XCTAssertNil(fixture.journal.record)
        XCTAssertEqual(fixture.runtime.events.filter { $0 == "install" }.count, 2)
    }

    func testRecoveryReportsEveryErrorAndPreRestoreBackupURL() async {
        let fixture = makeTransactionFixture()
        let interrupted = fixture.makeTransaction(
            interrupting: .phasePersisted(.bookmarksCommitted)
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await interrupted.commit(self.replaceMutatingPlan())
        }
        fixture.bookmarks.restoreError = TestImportFailure.bookmarkRollback
        fixture.runtime.restoreError = TestImportFailure.runtimeRollback

        do {
            _ = try await fixture.makeTransaction().recoverIfNeeded()
            XCTFail("Expected recovery failure")
        } catch let error as SumiImportTransactionError {
            guard case .recoveryFailed = error else {
                XCTFail("Expected recoveryFailed, got \(error)")
                return
            }
            XCTAssertEqual(error.rollbackErrors.count, 2)
            XCTAssertEqual(
                error.rollbackErrors.compactMap { $0 as? TestImportFailure },
                [.bookmarkRollback, .runtimeRollback]
            )
            XCTAssertEqual(
                error.preRestoreBackupURL,
                URL(fileURLWithPath: "/tmp/import-backup.sumibackup")
            )
            XCTAssertEqual(fixture.journal.record?.phase, .compensating)
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }
    }

    func testCompensationCompletedPublicationErrorIsIncludedInRollbackErrors() async {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        fixture.journal.saveErrors[.completed] = TestImportFailure.journal

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected import failure")
        } catch let error as SumiImportTransactionError {
            guard case .commitFailed = error else {
                XCTFail("Expected commitFailed, got \(error)")
                return
            }
            XCTAssertEqual(
                error.rollbackErrors.compactMap { $0 as? TestImportFailure },
                [.journal]
            )
            XCTAssertEqual(fixture.journal.record?.phase, .compensating)
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }
    }

    func testPreparedPhysicalPublicationRunsOffMainAndIsAwaitedBeforeEffects() async throws {
        let directory = temporaryDirectory(named: "SumiImportOffMainTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let publicationReached = expectation(description: "prepared publication reached parent barrier")
        let probe = ImportJournalFileOperationProbe(
            blocking: .synchronizePublishedPhase(.prepared),
            blockedExpectation: publicationReached
        )
        let journal = SumiImportTransactionFileJournal(
            fileURL: directory.appendingPathComponent("active.json"),
            operationHook: probe.handle
        )
        let fixture = makePhysicalTransactionFixture(journal: journal)
        let plan = mutatingPlan()

        let commitTask = Task { @MainActor in
            try await fixture.transaction.commit(plan)
        }
        await fulfillment(of: [publicationReached], timeout: 5)

        XCTAssertEqual(fixture.runtime.events, ["checkpoint"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
        XCTAssertFalse(probe.observations.isEmpty)
        XCTAssertTrue(probe.observations.allSatisfy { !$0.wasMainThread })
        XCTAssertTrue(probe.observations.allSatisfy(\.wasAtLeastUtilityPriority))

        probe.resumeBlockedOperation()
        _ = try await commitTask.value

        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 1)
        let operations = probe.operations
        XCTAssertLessThan(
            try XCTUnwrap(operations.firstIndex(of: .retireCompletedJournal)),
            try XCTUnwrap(operations.firstIndex(of: .synchronizeRetiredCompletedJournal))
        )
        XCTAssertLessThan(
            try XCTUnwrap(operations.firstIndex(of: .removeCompletedJournal)),
            try XCTUnwrap(operations.firstIndex(of: .synchronizeCompletedRemoval))
        )
        XCTAssertTrue(probe.observations.allSatisfy { !$0.wasMainThread })
        XCTAssertTrue(probe.observations.allSatisfy(\.wasAtLeastUtilityPriority))
    }

    func testDirectoryPublicationBarrierFailurePreventsPreparedJournalAndEffects() async {
        let directory = temporaryDirectory(named: "SumiImportDirectoryBarrierTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journalURL = directory
            .appendingPathComponent("new", isDirectory: true)
            .appendingPathComponent("active.json")
        let probe = ImportJournalFileOperationProbe(
            failing: .synchronizeJournalDirectoryParent
        )
        let fixture = makePhysicalTransactionFixture(
            journal: SumiImportTransactionFileJournal(
                fileURL: journalURL,
                operationHook: probe.handle
            )
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(self.mutatingPlan())
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
        XCTAssertFalse(probe.operations.contains(.synchronizeExistingDirectoryParent))
        XCTAssertFalse(probe.operations.contains(.writeTemporaryFile(.prepared)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testDirectoryBarrierRetryReestablishesParentBeforePublishing() async throws {
        let directory = temporaryDirectory(named: "SumiImportDirectoryRetryTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let journalURL = directory
            .appendingPathComponent("new", isDirectory: true)
            .appendingPathComponent("active.json")
        let probe = ImportJournalFileOperationProbe(
            failing: .synchronizeJournalDirectoryParent
        )
        let fixture = makePhysicalTransactionFixture(
            journal: SumiImportTransactionFileJournal(
                fileURL: journalURL,
                operationHook: probe.handle
            )
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(self.mutatingPlan())
        }
        _ = try await fixture.transaction.commit(mutatingPlan())

        let operations = probe.operations
        let preparedSaveIndices = operations.indices.filter {
            operations[$0] == .beginSave(.prepared)
        }
        XCTAssertEqual(preparedSaveIndices.count, 2)
        let retryOperations = Array(operations[preparedSaveIndices[1]...])
        let existingBarrier = try XCTUnwrap(
            retryOperations.firstIndex(of: .synchronizeExistingDirectoryParent)
        )
        let temporaryWrite = try XCTUnwrap(
            retryOperations.firstIndex(of: .writeTemporaryFile(.prepared))
        )
        XCTAssertFalse(retryOperations.contains(.createJournalDirectory))
        XCTAssertLessThan(existingBarrier, temporaryWrite)
    }

    func testUnavailableApplicationSupportFailsClosedBeforeAnyEffect() async {
        let fixture = makePhysicalTransactionFixture(
            journal: SumiImportTransactionFileJournal(
                applicationSupportDirectoryProvider: { nil }
            )
        )

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected unavailable Application Support failure")
        } catch let error as SumiImportTransactionJournalError {
            guard case .applicationSupportUnavailable = error else {
                XCTFail("Expected applicationSupportUnavailable, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected journal error, got \(error)")
        }

        XCTAssertTrue(fixture.runtime.events.isEmpty)
        XCTAssertTrue(fixture.bookmarks.events.isEmpty)
    }

    func testPreparedPublicationBarrierFailurePreventsAllEffects() async throws {
        let directory = temporaryDirectory(named: "SumiImportPreparedBarrierTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journalURL = directory.appendingPathComponent("active.json")
        let probe = ImportJournalFileOperationProbe(
            failing: .synchronizePublishedPhase(.prepared)
        )
        let fixture = makePhysicalTransactionFixture(
            journal: SumiImportTransactionFileJournal(
                fileURL: journalURL,
                operationHook: probe.handle
            )
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.transaction.commit(self.mutatingPlan())
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint"])
        XCTAssertEqual(fixture.bookmarks.commitCount, 0)
        let visibleRecord = try await SumiImportTransactionFileJournal(fileURL: journalURL).load()
        XCTAssertEqual(visibleRecord?.phase, .prepared)
    }

    func testLaterPhasePublicationBarrierFailureCannotAdvanceToNextEffect() async throws {
        struct Case {
            let phase: SumiImportTransactionPhase
            let expectedBookmarkCommitCount: Int
        }
        let cases = [
            Case(phase: .runtimeCommitted, expectedBookmarkCommitCount: 0),
            Case(phase: .bookmarksCommitted, expectedBookmarkCommitCount: 1),
        ]

        for testCase in cases {
            let directory = temporaryDirectory(named: "SumiImportPhaseBarrierTests")
            defer { removeTemporaryDirectoryOrRecordFailure(directory) }
            let journalURL = directory.appendingPathComponent("active.json")
            let probe = ImportJournalFileOperationProbe(
                failing: .synchronizePublishedPhase(testCase.phase)
            )
            let fixture = makePhysicalTransactionFixture(
                journal: SumiImportTransactionFileJournal(
                    fileURL: journalURL,
                    operationHook: probe.handle
                )
            )

            await XCTAssertThrowsErrorAsync {
                _ = try await fixture.transaction.commit(self.mutatingPlan())
            }

            XCTAssertEqual(
                fixture.bookmarks.commitCount,
                testCase.expectedBookmarkCommitCount,
                "phase=\(testCase.phase)"
            )
            XCTAssertEqual(
                fixture.runtime.events,
                ["checkpoint", "install", "restore"],
                "phase=\(testCase.phase)"
            )
            XCTAssertEqual(
                fixture.bookmarks.events.last,
                "restore",
                "phase=\(testCase.phase)"
            )
            let remainingRecord = try await SumiImportTransactionFileJournal(
                fileURL: journalURL
            ).load()
            XCTAssertNil(remainingRecord, "phase=\(testCase.phase)")
        }
    }

    func testCompletedPublicationFailureDefersDecisionToVisibleJournal() async throws {
        let cases: [(
            operation: SumiImportTransactionJournalFileOperation,
            visiblePhase: SumiImportTransactionPhase,
            recoveryRestores: Bool
        )] = [
            (.publishPhase(.completed), .bookmarksCommitted, true),
            (.synchronizePublishedPhase(.completed), .completed, false),
        ]

        for testCase in cases {
            let directory = temporaryDirectory(named: "SumiImportCompletedBarrierTests")
            defer { removeTemporaryDirectoryOrRecordFailure(directory) }
            let journalURL = directory.appendingPathComponent("active.json")
            let probe = ImportJournalFileOperationProbe(failing: testCase.operation)
            let fixture = makePhysicalTransactionFixture(
                journal: SumiImportTransactionFileJournal(
                    fileURL: journalURL,
                    operationHook: probe.handle
                )
            )

            do {
                _ = try await fixture.transaction.commit(mutatingPlan())
                XCTFail("Expected finalization failure")
            } catch let error as SumiImportTransactionError {
                guard case .commitFinalizationFailed = error else {
                    XCTFail("Expected commitFinalizationFailed, got \(error)")
                    continue
                }
            }

            XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install"])
            XCTAssertEqual(fixture.bookmarks.events.last, "commit")
            let freshJournal = SumiImportTransactionFileJournal(fileURL: journalURL)
            let visibleRecord = try await freshJournal.load()
            XCTAssertEqual(visibleRecord?.phase, testCase.visiblePhase)

            _ = try await SumiImportTransaction(
                materializer: fixture.materializer,
                runtime: fixture.runtime,
                bookmarks: fixture.bookmarks,
                backupWriter: fixture.backup,
                journal: freshJournal,
                executionGate: SumiImportTransactionExecutionGate()
            ).recoverIfNeeded()

            XCTAssertEqual(
                fixture.runtime.events.contains("restore"),
                testCase.recoveryRestores
            )
            XCTAssertEqual(
                fixture.bookmarks.events.contains("restore"),
                testCase.recoveryRestores
            )
        }
    }

    func testFailedPhasePublicationNeverSilentlyDiscardsOriginalJournal() async throws {
        let failureCases: [(
            operation: SumiImportTransactionJournalFileOperation,
            visiblePhase: SumiImportTransactionPhase
        )] = [
            (.synchronizeTemporaryFile(.runtimeCommitted), .prepared),
            (.publishPhase(.runtimeCommitted), .prepared),
            (.synchronizePublishedPhase(.runtimeCommitted), .runtimeCommitted),
        ]

        for testCase in failureCases {
            let directory = temporaryDirectory(named: "SumiImportOriginalJournalTests")
            defer { removeTemporaryDirectoryOrRecordFailure(directory) }
            let journalURL = directory.appendingPathComponent("active.json")
            try await SumiImportTransactionFileJournal(fileURL: journalURL).save(
                makeJournalRecord(phase: .prepared)
            )
            let probe = ImportJournalFileOperationProbe(failing: testCase.operation)
            let failingJournal = SumiImportTransactionFileJournal(
                fileURL: journalURL,
                operationHook: probe.handle
            )

            do {
                try await failingJournal.save(makeJournalRecord(phase: .runtimeCommitted))
                XCTFail("Expected journal publication failure")
            } catch {}

            let visibleRecord = try await SumiImportTransactionFileJournal(
                fileURL: journalURL
            ).load()
            XCTAssertEqual(visibleRecord?.phase, testCase.visiblePhase)
        }
    }

    func testStagingCleanupErrorsAreAggregatedWithoutDiscardingActiveJournal() async throws {
        let directory = temporaryDirectory(named: "SumiImportStagingCleanupTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journalURL = directory.appendingPathComponent("active.json")
        try await SumiImportTransactionFileJournal(fileURL: journalURL).save(
            makeJournalRecord(phase: .prepared)
        )
        let failingOperations: [SumiImportTransactionJournalFileOperation] = [
            .synchronizeTemporaryFile(.runtimeCommitted),
            .closeTemporaryFileAfterFailure(.runtimeCommitted),
            .discardTemporaryFile(.runtimeCommitted),
        ]
        let failingJournal = SumiImportTransactionFileJournal(
            fileURL: journalURL,
            operationHook: { operation in
                if failingOperations.contains(operation) {
                    throw TestImportFailure.journal
                }
            }
        )

        do {
            try await failingJournal.save(makeJournalRecord(phase: .runtimeCommitted))
            XCTFail("Expected journal and staging cleanup failure")
        } catch let error as SumiImportTransactionJournalFileFailure {
            XCTAssertEqual(error.operationError as? TestImportFailure, .journal)
            XCTAssertEqual(
                error.cleanupErrors.compactMap { $0 as? TestImportFailure },
                [.journal, .journal]
            )
        } catch {
            XCTFail("Expected aggregated journal failure, got \(error)")
        }

        let visibleRecord = try await SumiImportTransactionFileJournal(
            fileURL: journalURL
        ).load()
        XCTAssertEqual(visibleRecord?.phase, .prepared)
    }

    func testCleanupFailureLeavesCompletedEvidenceForFreshRecovery() async throws {
        let directory = temporaryDirectory(named: "SumiImportCleanupRecoveryTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journalURL = directory.appendingPathComponent("active.json")
        let probe = ImportJournalFileOperationProbe(
            failing: .synchronizeRetiredCompletedJournal
        )
        let fixture = makePhysicalTransactionFixture(
            journal: SumiImportTransactionFileJournal(
                fileURL: journalURL,
                operationHook: probe.handle
            )
        )

        do {
            _ = try await fixture.transaction.commit(replaceMutatingPlan())
            XCTFail("Expected cleanup failure")
        } catch let error as SumiImportTransactionError {
            guard case .commitFinalizationFailed = error else {
                XCTFail("Expected commitFinalizationFailed, got \(error)")
                return
            }
            XCTAssertEqual(
                error.preRestoreBackupURL,
                URL(fileURLWithPath: "/tmp/import-backup.sumibackup")
            )
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install"])
        XCTAssertEqual(fixture.bookmarks.events.last, "commit")
        let freshJournal = SumiImportTransactionFileJournal(fileURL: journalURL)
        let completedRecord = try await freshJournal.load()
        XCTAssertEqual(completedRecord?.phase, .completed)

        _ = try await SumiImportTransaction(
            materializer: fixture.materializer,
            runtime: fixture.runtime,
            bookmarks: fixture.bookmarks,
            backupWriter: fixture.backup,
            journal: freshJournal,
            executionGate: SumiImportTransactionExecutionGate()
        ).recoverIfNeeded()

        XCTAssertFalse(fixture.runtime.events.contains("restore"))
        XCTAssertFalse(fixture.bookmarks.events.contains("restore"))
        let clearedRecord = try await freshJournal.load()
        XCTAssertNil(clearedRecord)
    }

    func testPostRemovalBarrierFailureIsReportedWithoutRollback() async {
        let directory = temporaryDirectory(named: "SumiImportRemovalBarrierTests")
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journalURL = directory.appendingPathComponent("active.json")
        let probe = ImportJournalFileOperationProbe(
            failing: .synchronizeCompletedRemoval
        )
        let fixture = makePhysicalTransactionFixture(
            journal: SumiImportTransactionFileJournal(
                fileURL: journalURL,
                operationHook: probe.handle
            )
        )

        do {
            _ = try await fixture.transaction.commit(mutatingPlan())
            XCTFail("Expected cleanup barrier failure")
        } catch let error as SumiImportTransactionError {
            guard case .commitFinalizationFailed = error else {
                XCTFail("Expected commitFinalizationFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected SumiImportTransactionError, got \(error)")
        }

        XCTAssertEqual(fixture.runtime.events, ["checkpoint", "install"])
        XCTAssertEqual(fixture.bookmarks.events.last, "commit")
        XCTAssertTrue(probe.operations.contains(.removeCompletedJournal))
        XCTAssertTrue(probe.operations.contains(.synchronizeCompletedRemoval))
    }

    func testFileJournalDurablyRoundTripsEveryPhase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiImportJournalTests-\(UUID().uuidString)", isDirectory: true)
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journal = SumiImportTransactionFileJournal(
            fileURL: directory.appendingPathComponent("active.json")
        )
        let baseline = mutatingPlan().baseline
        let target = mutatingPlan().targetRuntimeData
        let bookmarkCheckpoint = SumiImportBookmarkCheckpoint(
            RecordingImportBookmarks().checkpoint()
        )
        let runtimeCheckpoint = SumiImportDurableRuntimeCheckpoint(emptyRuntimeState())

        for phase in SumiImportTransactionPhase.allCases {
            let record = SumiImportTransactionJournalRecord(
                phase: phase,
                baseline: baseline,
                targetRuntimeData: target,
                runtimeCheckpoint: runtimeCheckpoint,
                bookmarkCheckpoint: bookmarkCheckpoint,
                preRestoreBackupURL: URL(fileURLWithPath: "/tmp/pre-restore.sumibackup")
            )
            try await journal.save(record)
            let loadedRecord = try await journal.load()
            XCTAssertEqual(loadedRecord, record, "phase=\(phase)")
        }

        try await journal.clear()
        let clearedRecord = try await journal.load()
        XCTAssertNil(clearedRecord)
    }

    func testFreshFileJournalRecoveryRestoresCompleteDurableRuntimeCheckpoint() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiImportRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { removeTemporaryDirectoryOrRecordFailure(directory) }
        let journalURL = directory.appendingPathComponent("active.json")

        let browserManager = BrowserManager()
        let firstProfile = Profile(name: "First")
        let selectedProfile = Profile(name: "Selected")
        let space = Space(name: "Baseline Space", icon: "circle", profileId: selectedProfile.id)
        let firstTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://first.example")!,
            name: "First",
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        let selectedTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://selected.example")!,
            name: "Selected",
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            index: 0,
            launchURL: URL(string: "https://pending.example")!,
            title: "Pending"
        )
        let splitGroup = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(firstTab.id), .regularTab(selectedTab.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        let baselineState = SumiImportRuntimeState(
            profiles: [firstProfile, selectedProfile],
            currentProfile: selectedProfile,
            spaces: [space],
            tabsBySpace: [space.id: [firstTab, selectedTab]],
            foldersBySpace: [space.id: []],
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pendingPin],
            splitGroups: [splitGroup],
            currentSpace: space,
            currentTab: selectedTab
        )
        let materializedBaseline = SumiImportRuntimeState(
            profiles: baselineState.profiles,
            currentProfile: firstProfile,
            spaces: baselineState.spaces,
            tabsBySpace: baselineState.tabsBySpace,
            foldersBySpace: baselineState.foldersBySpace,
            pinnedByProfile: baselineState.pinnedByProfile,
            spacePinnedShortcuts: baselineState.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: firstTab
        )
        let importedProfile = Profile(id: firstProfile.id, name: "Imported")
        let importedState = SumiImportRuntimeState(
            profiles: [importedProfile, selectedProfile],
            currentProfile: importedProfile,
            spaces: baselineState.spaces,
            tabsBySpace: baselineState.tabsBySpace,
            foldersBySpace: baselineState.foldersBySpace,
            pinnedByProfile: baselineState.pinnedByProfile,
            spacePinnedShortcuts: baselineState.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: firstTab
        )
        let baselineData = SumiPortableData(
            profiles: [
                portableProfile(id: firstProfile.id.uuidString, name: firstProfile.name),
                portableProfile(id: selectedProfile.id.uuidString, name: selectedProfile.name),
            ],
            spaces: [portableSpace(
                id: space.id.uuidString,
                profileId: selectedProfile.id.uuidString
            )],
            regularTabs: [
                portableTab(id: firstTab.id.uuidString, spaceId: space.id.uuidString),
                portableTab(id: selectedTab.id.uuidString, spaceId: space.id.uuidString),
            ]
        )
        let targetData = SumiPortableData(
            profiles: [
                portableProfile(id: firstProfile.id.uuidString, name: importedProfile.name),
                portableProfile(id: selectedProfile.id.uuidString, name: selectedProfile.name),
            ],
            spaces: baselineData.spaces,
            regularTabs: baselineData.regularTabs
        )
        let plan = SumiImportPlan(
            baseline: baselineData,
            targetRuntimeData: targetData,
            bookmarkMutation: .merge([bookmarkNode("Imported")]),
            categories: [.profiles, .bookmarks],
            mode: .merge,
            warnings: []
        )
        let bookmarks = RecordingImportBookmarks()
        let firstRuntime = StateTrackingImportRuntime(state: baselineState)
        let materializer = PlanStateImportMaterializer(
            rollbackData: baselineData,
            importedState: importedState,
            rollbackState: materializedBaseline
        )
        let firstTransaction = SumiImportTransaction(
            materializer: materializer,
            runtime: firstRuntime,
            bookmarks: bookmarks,
            backupWriter: RecordingImportBackup(),
            journal: SumiImportTransactionFileJournal(fileURL: journalURL),
            executionGate: SumiImportTransactionExecutionGate(),
            shouldInterrupt: { $0 == .bookmarksMutated }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await firstTransaction.commit(plan)
        }

        let launchRuntime = StateTrackingImportRuntime(state: importedState)
        let launchTransaction = SumiImportTransaction(
            materializer: materializer,
            runtime: launchRuntime,
            bookmarks: bookmarks,
            backupWriter: RecordingImportBackup(),
            journal: SumiImportTransactionFileJournal(fileURL: journalURL),
            executionGate: SumiImportTransactionExecutionGate()
        )

        _ = try await launchTransaction.recoverIfNeeded()

        XCTAssertEqual(launchRuntime.state.profiles.map(\.name), ["First", "Selected"])
        XCTAssertIdentical(launchRuntime.state.currentProfile, selectedProfile)
        XCTAssertIdentical(launchRuntime.state.currentSpace, space)
        XCTAssertIdentical(launchRuntime.state.currentTab, selectedTab)
        XCTAssertEqual(launchRuntime.state.pendingPinnedWithoutProfile.count, 1)
        XCTAssertEqual(launchRuntime.state.pendingPinnedWithoutProfile.first?.id, pendingPin.id)
        XCTAssertEqual(launchRuntime.state.splitGroups, [splitGroup])
        XCTAssertEqual(bookmarks.storedIDs, ["before-id"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
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

    func testCommittedReplaceRetiresProfilesAfterRuntimeLeaseEnds() async throws {
        let fixture = makeTransactionFixture()
        let retirement = RecordingImportProfileRetirement()
        retirement.onRetire = {
            XCTAssertFalse(fixture.runtime.isMutationActive)
        }
        let basePlan = mutatingPlan()
        let retiringID = try XCTUnwrap(
            UUID(uuidString: basePlan.baseline.profiles[0].id)
        )
        let fallbackID = try XCTUnwrap(
            UUID(uuidString: basePlan.targetRuntimeData.profiles[0].id)
        )
        let plan = SumiImportPlan(
            baseline: basePlan.baseline,
            targetRuntimeData: basePlan.targetRuntimeData,
            bookmarkMutation: basePlan.bookmarkMutation,
            categories: basePlan.categories,
            mode: .replace,
            warnings: [],
            profileTransition: SumiImportProfileTransition(
                sourceToTargetProfileID: [:],
                createdProfileIDs: [fallbackID],
                retiringProfileIDs: [retiringID],
                fallbackProfileID: fallbackID
            )
        )
        let transaction = SumiImportTransaction(
            materializer: fixture.materializer,
            runtime: fixture.runtime,
            bookmarks: fixture.bookmarks,
            backupWriter: fixture.backup,
            journal: fixture.journal,
            profileRetirement: retirement,
            executionGate: fixture.executionGate
        )

        _ = try await transaction.commit(plan)

        XCTAssertEqual(retirement.calls.count, 1)
        XCTAssertEqual(retirement.calls[0].profileIDs, [retiringID])
        XCTAssertEqual(retirement.calls[0].fallbackProfileID, fallbackID)
        XCTAssertTrue(fixture.journal.savedPhases.contains(.retiringProfiles))
        XCTAssertNil(fixture.journal.record)
    }

    func testRetiringProfilesPhaseResumesForwardWithoutRollback() async throws {
        let fixture = makeTransactionFixture()
        let retirement = RecordingImportProfileRetirement()
        retirement.error = TestImportFailure.rollback
        let basePlan = mutatingPlan()
        let retiringID = try XCTUnwrap(
            UUID(uuidString: basePlan.baseline.profiles[0].id)
        )
        let fallbackID = try XCTUnwrap(
            UUID(uuidString: basePlan.targetRuntimeData.profiles[0].id)
        )
        let plan = SumiImportPlan(
            baseline: basePlan.baseline,
            targetRuntimeData: basePlan.targetRuntimeData,
            bookmarkMutation: basePlan.bookmarkMutation,
            categories: basePlan.categories,
            mode: .replace,
            warnings: [],
            profileTransition: SumiImportProfileTransition(
                sourceToTargetProfileID: [:],
                createdProfileIDs: [fallbackID],
                retiringProfileIDs: [retiringID],
                fallbackProfileID: fallbackID
            )
        )
        let transaction = SumiImportTransaction(
            materializer: fixture.materializer,
            runtime: fixture.runtime,
            bookmarks: fixture.bookmarks,
            backupWriter: fixture.backup,
            journal: fixture.journal,
            profileRetirement: retirement,
            executionGate: fixture.executionGate
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await transaction.commit(plan)
        }
        XCTAssertEqual(fixture.journal.record?.phase, .retiringProfiles)
        XCTAssertFalse(fixture.runtime.events.contains("restore"))

        retirement.error = nil
        _ = try await transaction.recoverIfNeeded()

        XCTAssertEqual(retirement.calls.count, 2)
        XCTAssertNil(fixture.journal.record)
        XCTAssertFalse(fixture.runtime.events.contains("restore"))
    }

    func testRollbackRetiresProfilesCreatedByFailedImport() async throws {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        let retirement = RecordingImportProfileRetirement()
        let basePlan = mutatingPlan()
        let createdID = try XCTUnwrap(
            UUID(uuidString: basePlan.targetRuntimeData.profiles[0].id)
        )
        let fallbackID = try XCTUnwrap(
            UUID(uuidString: basePlan.baseline.profiles[0].id)
        )
        let plan = SumiImportPlan(
            baseline: basePlan.baseline,
            targetRuntimeData: basePlan.targetRuntimeData,
            bookmarkMutation: basePlan.bookmarkMutation,
            categories: basePlan.categories,
            mode: .merge,
            warnings: [],
            profileTransition: SumiImportProfileTransition(
                sourceToTargetProfileID: [:],
                createdProfileIDs: [createdID],
                retiringProfileIDs: [],
                fallbackProfileID: createdID
            )
        )
        let transaction = SumiImportTransaction(
            materializer: fixture.materializer,
            runtime: fixture.runtime,
            bookmarks: fixture.bookmarks,
            backupWriter: fixture.backup,
            journal: fixture.journal,
            profileRetirement: retirement,
            executionGate: fixture.executionGate
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await transaction.commit(plan)
        }

        XCTAssertTrue(fixture.runtime.events.contains("restore"))
        XCTAssertEqual(retirement.calls.count, 1)
        XCTAssertEqual(retirement.calls[0].profileIDs, [createdID])
        XCTAssertEqual(retirement.calls[0].fallbackProfileID, fallbackID)
        XCTAssertTrue(
            fixture.journal.savedPhases.contains(.compensatingProfiles)
        )
        XCTAssertNil(fixture.journal.record)
    }

    func testCompensatingProfileRetirementResumesAfterJournalInterruption() async throws {
        let fixture = makeTransactionFixture()
        fixture.bookmarks.failuresRemaining = 1
        let retirement = RecordingImportProfileRetirement()
        let basePlan = mutatingPlan()
        let createdID = try XCTUnwrap(
            UUID(uuidString: basePlan.targetRuntimeData.profiles[0].id)
        )
        let plan = SumiImportPlan(
            baseline: basePlan.baseline,
            targetRuntimeData: basePlan.targetRuntimeData,
            bookmarkMutation: basePlan.bookmarkMutation,
            categories: basePlan.categories,
            mode: .merge,
            warnings: [],
            profileTransition: SumiImportProfileTransition(
                sourceToTargetProfileID: [:],
                createdProfileIDs: [createdID],
                retiringProfileIDs: [],
                fallbackProfileID: createdID
            )
        )
        let interrupted = SumiImportTransaction(
            materializer: fixture.materializer,
            runtime: fixture.runtime,
            bookmarks: fixture.bookmarks,
            backupWriter: fixture.backup,
            journal: fixture.journal,
            profileRetirement: retirement,
            executionGate: fixture.executionGate,
            shouldInterrupt: {
                $0 == .phasePersisted(.compensatingProfiles)
            }
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await interrupted.commit(plan)
        }

        XCTAssertEqual(fixture.journal.record?.phase, .compensatingProfiles)
        XCTAssertTrue(retirement.calls.isEmpty)

        _ = try await SumiImportTransaction(
            materializer: fixture.materializer,
            runtime: fixture.runtime,
            bookmarks: fixture.bookmarks,
            backupWriter: fixture.backup,
            journal: fixture.journal,
            profileRetirement: retirement,
            executionGate: fixture.executionGate
        ).recoverIfNeeded()

        XCTAssertEqual(retirement.calls.first?.profileIDs, [createdID])
        XCTAssertNil(fixture.journal.record)
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

    private func replaceMutatingPlan() -> SumiImportPlan {
        let plan = mutatingPlan()
        return SumiImportPlan(
            baseline: plan.baseline,
            targetRuntimeData: plan.targetRuntimeData,
            bookmarkMutation: plan.bookmarkMutation,
            categories: plan.categories,
            mode: .replace,
            warnings: plan.warnings
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
        SumiPortableProfile(id: id, name: name, index: 0)
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

    private func temporaryDirectory(named prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeTemporaryDirectoryOrRecordFailure(
        _ directory: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            XCTFail(
                "Failed to remove test temporary directory \(directory.path): \(error)",
                file: file,
                line: line
            )
        }
    }

    private func makeJournalRecord(
        phase: SumiImportTransactionPhase
    ) -> SumiImportTransactionJournalRecord {
        SumiImportTransactionJournalRecord(
            phase: phase,
            baseline: mutatingPlan().baseline,
            targetRuntimeData: mutatingPlan().targetRuntimeData,
            runtimeCheckpoint: SumiImportDurableRuntimeCheckpoint(emptyRuntimeState()),
            bookmarkCheckpoint: SumiImportBookmarkCheckpoint(
                RecordingImportBookmarks().checkpoint()
            ),
            preRestoreBackupURL: URL(fileURLWithPath: "/tmp/pre-restore.sumibackup")
        )
    }

    private func makePhysicalTransactionFixture(
        journal: SumiImportTransactionFileJournal
    ) -> PhysicalTransactionFixture {
        let materializer = RecordingImportMaterializer(state: emptyRuntimeState())
        let runtime = RecordingImportRuntime(checkpoint: emptyRuntimeState())
        let bookmarks = RecordingImportBookmarks()
        let backup = RecordingImportBackup()
        return PhysicalTransactionFixture(
            transaction: SumiImportTransaction(
                materializer: materializer,
                runtime: runtime,
                bookmarks: bookmarks,
                backupWriter: backup,
                journal: journal,
                executionGate: SumiImportTransactionExecutionGate()
            ),
            materializer: materializer,
            runtime: runtime,
            bookmarks: bookmarks,
            backup: backup
        )
    }

    private func makeTransactionFixture() -> TransactionFixture {
        let checkpoint = emptyRuntimeState()
        let target = emptyRuntimeState()
        let materializer = RecordingImportMaterializer(state: target)
        let runtime = RecordingImportRuntime(checkpoint: checkpoint)
        let bookmarks = RecordingImportBookmarks()
        let backup = RecordingImportBackup()
        let journal = RecordingImportJournal()
        let executionGate = SumiImportTransactionExecutionGate()
        return TransactionFixture(
            transaction: SumiImportTransaction(
                materializer: materializer,
                runtime: runtime,
                bookmarks: bookmarks,
                backupWriter: backup,
                journal: journal,
                executionGate: executionGate
            ),
            materializer: materializer,
            runtime: runtime,
            bookmarks: bookmarks,
            backup: backup,
            journal: journal,
            executionGate: executionGate
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

    private static let currentThemeFixtureBase64 =
        "eyJncmFkaWVudFRoZW1lIjp7ImNvbG9ycyI6W3siYWxnb3JpdGhtIjoiZmxvYXRpbmciLCJoZXgiOiIjNDQ1NTY2IiwiaWQiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJpc0N1c3RvbSI6ZmFsc2UsImlzUHJpbWFyeSI6dHJ1ZSwibGlnaHRuZXNzIjowLjM1LCJwb3NpdGlvbiI6eyJ4IjowLjY2LCJ5IjowLjV9LCJ0eXBlIjoiZXhwbGljaXQtbGlnaHRuZXNzIn1dLCJvcGFjaXR5IjowLjc0LCJ0ZXh0dXJlIjowLjE4NzUsInR5cGUiOiJncmFkaWVudCJ9LCJ1c2VzRXhwbGljaXRDb2xvclNjaGVtZSI6dHJ1ZX0="
}

@MainActor
private struct PhysicalTransactionFixture {
    let transaction: SumiImportTransaction
    let materializer: RecordingImportMaterializer
    let runtime: RecordingImportRuntime
    let bookmarks: RecordingImportBookmarks
    let backup: RecordingImportBackup
}

@MainActor
private struct TransactionFixture {
    let transaction: SumiImportTransaction
    let materializer: RecordingImportMaterializer
    let runtime: RecordingImportRuntime
    let bookmarks: RecordingImportBookmarks
    let backup: RecordingImportBackup
    let journal: RecordingImportJournal
    let executionGate: SumiImportTransactionExecutionGate

    func makeTransaction(
        interrupting faultPoint: SumiImportTransactionFaultPoint? = nil
    ) -> SumiImportTransaction {
        SumiImportTransaction(
            materializer: materializer,
            runtime: runtime,
            bookmarks: bookmarks,
            backupWriter: backup,
            journal: journal,
            executionGate: executionGate,
            shouldInterrupt: { $0 == faultPoint }
        )
    }
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
private final class PlanStateImportMaterializer: SumiImportRuntimeMaterializing {
    let rollbackData: SumiPortableData
    let importedState: SumiImportRuntimeState
    let rollbackState: SumiImportRuntimeState

    init(
        rollbackData: SumiPortableData,
        importedState: SumiImportRuntimeState,
        rollbackState: SumiImportRuntimeState
    ) {
        self.rollbackData = rollbackData
        self.importedState = importedState
        self.rollbackState = rollbackState
    }

    func materialize(
        _ plan: SumiImportPlan,
        preserving checkpoint: SumiImportRuntimeState
    ) throws -> SumiImportRuntimeState {
        _ = checkpoint
        return plan.targetRuntimeData == rollbackData ? rollbackState : importedState
    }
}

@MainActor
private final class StateTrackingImportRuntime: SumiImportRuntimeMutating {
    private(set) var state: SumiImportRuntimeState
    private var activeSession: SumiImportRuntimeMutationSession?

    init(state: SumiImportRuntimeState) {
        self.state = state
    }

    func checkpoint() -> SumiImportRuntimeState {
        state
    }

    func beginMutation(
        covering candidates: [SumiImportRuntimeState]
    ) throws -> SumiImportRuntimeMutationSession {
        _ = candidates
        precondition(activeSession == nil)
        let session = SumiImportRuntimeMutationSession()
        activeSession = session
        return session
    }

    func install(
        _ state: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws {
        precondition(activeSession == session)
        self.state = state
    }

    func restore(
        _ checkpoint: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws {
        precondition(activeSession == session)
        state = checkpoint
    }

    func endMutation(_ session: SumiImportRuntimeMutationSession) -> Bool {
        guard activeSession == session else { return false }
        activeSession = nil
        return true
    }
}

@MainActor
private final class RecordingImportRuntime: SumiImportRuntimeMutating {
    let savedCheckpoint: SumiImportRuntimeState
    var events: [String] = []
    var installFailuresRemaining = 0
    var restoreError: Error?
    private var suspendedInstall: CheckedContinuation<Void, Never>?
    private var onInstallSuspended: (() -> Void)?
    private var activeSession: SumiImportRuntimeMutationSession?

    var isMutationActive: Bool {
        activeSession != nil
    }

    init(checkpoint: SumiImportRuntimeState) {
        savedCheckpoint = checkpoint
    }

    func checkpoint() -> SumiImportRuntimeState {
        events.append("checkpoint")
        return savedCheckpoint
    }

    func beginMutation(
        covering candidates: [SumiImportRuntimeState]
    ) throws -> SumiImportRuntimeMutationSession {
        _ = candidates
        precondition(activeSession == nil)
        let session = SumiImportRuntimeMutationSession()
        activeSession = session
        return session
    }

    func install(
        _ state: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws {
        precondition(activeSession == session)
        events.append("install")
        if let onInstallSuspended {
            self.onInstallSuspended = nil
            await withCheckedContinuation { continuation in
                suspendedInstall = continuation
                onInstallSuspended()
            }
        }
        if installFailuresRemaining > 0 {
            installFailuresRemaining -= 1
            throw TestImportFailure.install
        }
    }

    func restore(
        _ checkpoint: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws {
        precondition(activeSession == session)
        events.append("restore")
        if let restoreError { throw restoreError }
    }

    func endMutation(_ session: SumiImportRuntimeMutationSession) -> Bool {
        guard activeSession == session else { return false }
        activeSession = nil
        return true
    }

    func suspendNextInstall(_ onSuspended: @escaping () -> Void) {
        onInstallSuspended = onSuspended
    }

    func resumeSuspendedInstall() {
        suspendedInstall?.resume()
        suspendedInstall = nil
    }
}

@MainActor
private final class RecordingImportBookmarks: SumiImportBookmarkMutating {
    var failuresRemaining = 0
    var restoreError: Error?
    var onCommit: (() -> Void)?
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
        onCommit?()
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

@MainActor
private final class RecordingImportProfileRetirement: SumiImportProfileRetiring {
    struct Call: Equatable {
        let profileIDs: Set<UUID>
        let fallbackProfileID: UUID
    }

    var error: Error?
    var onRetire: (() -> Void)?
    private(set) var calls: [Call] = []

    func retireProfiles(
        _ profileIDs: Set<UUID>,
        fallbackProfileID: UUID
    ) async throws {
        calls.append(
            Call(
                profileIDs: profileIDs,
                fallbackProfileID: fallbackProfileID
            )
        )
        onRetire?()
        if let error { throw error }
    }
}

@MainActor
private final class RecordingImportJournal: SumiImportTransactionJournal {
    var record: SumiImportTransactionJournalRecord?
    var saveErrors: [SumiImportTransactionPhase: Error] = [:]
    var clearError: Error?
    private(set) var savedPhases: [SumiImportTransactionPhase] = []
    private(set) var clearCount = 0

    func load() async throws -> SumiImportTransactionJournalRecord? {
        record
    }

    func save(_ record: SumiImportTransactionJournalRecord) async throws {
        if let error = saveErrors[record.phase] {
            throw error
        }
        self.record = record
        savedPhases.append(record.phase)
    }

    func clear() async throws {
        if let clearError { throw clearError }
        record = nil
        clearCount += 1
    }
}

private enum TestImportFailure: LocalizedError, Equatable {
    case install
    case bookmarks
    case backup
    case rollback
    case bookmarkRollback
    case runtimeRollback
    case journal
}

private final class ImportJournalFileOperationProbe: @unchecked Sendable {
    struct Observation {
        let operation: SumiImportTransactionJournalFileOperation
        let wasMainThread: Bool
        let wasAtLeastUtilityPriority: Bool
    }

    private let lock = NSLock()
    private let failingOperation: SumiImportTransactionJournalFileOperation?
    private let blockingOperation: SumiImportTransactionJournalFileOperation?
    private let blockedExpectation: XCTestExpectation?
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var failureRemaining: Bool
    private var blockRemaining: Bool
    private var recordedObservations: [Observation] = []

    init(
        failing: SumiImportTransactionJournalFileOperation? = nil,
        blocking: SumiImportTransactionJournalFileOperation? = nil,
        blockedExpectation: XCTestExpectation? = nil
    ) {
        failingOperation = failing
        blockingOperation = blocking
        self.blockedExpectation = blockedExpectation
        failureRemaining = failing != nil
        blockRemaining = blocking != nil
    }

    func handle(_ operation: SumiImportTransactionJournalFileOperation) throws {
        let observation = Observation(
            operation: operation,
            wasMainThread: Thread.isMainThread,
            wasAtLeastUtilityPriority: Task.currentPriority >= .utility
        )
        lock.lock()
        recordedObservations.append(observation)
        let shouldFail = failureRemaining && operation == failingOperation
        if shouldFail { failureRemaining = false }
        let shouldBlock = blockRemaining && operation == blockingOperation
        if shouldBlock { blockRemaining = false }
        lock.unlock()

        if shouldBlock {
            blockedExpectation?.fulfill()
            releaseSemaphore.wait()
        }
        if shouldFail {
            throw TestImportFailure.journal
        }
    }

    func resumeBlockedOperation() {
        releaseSemaphore.signal()
    }

    var observations: [Observation] {
        lock.withLock { recordedObservations }
    }

    var operations: [SumiImportTransactionJournalFileOperation] {
        observations.map(\.operation)
    }
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
