@testable import Sumi
import SumiDomain
import XCTest

@MainActor
extension SumiImportTransactionTests {
    func testFreshDatabaseJournalRecoveryRestoresCompleteDurableRuntimeCheckpoint() async throws {
        let database = try SumiDatabase.inMemory()
        let journal = SumiImportTransactionDatabaseJournal(database: database)

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
            journal: journal,
            executionGate: SumiImportTransactionExecutionGate(),
            shouldInterrupt: { $0 == .bookmarksMutated }
        )

        await XCTAssertImportThrowsErrorAsync {
            _ = try await firstTransaction.commit(plan)
        }

        let launchRuntime = StateTrackingImportRuntime(state: importedState)
        let launchTransaction = SumiImportTransaction(
            materializer: materializer,
            runtime: launchRuntime,
            bookmarks: bookmarks,
            backupWriter: RecordingImportBackup(),
            journal: SumiImportTransactionDatabaseJournal(database: database),
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
        let clearedJournal = try await journal.load()
        XCTAssertNil(clearedJournal)
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

        await XCTAssertImportThrowsErrorAsync {
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

        await XCTAssertImportThrowsErrorAsync {
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

        await XCTAssertImportThrowsErrorAsync {
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

    func testImportingBrowserSpacesAlsoImportsTheirOwningProfiles() throws {
        let localProfileID = UUID().uuidString
        let sourceProfileID = "chromium-profile-1"
        let request = SumiImportRequest(
            sourceKind: .chromium,
            data: SumiPortableData(
                profiles: [portableProfile(id: sourceProfileID, name: "Imported")],
                spaces: [portableSpace(id: "chromium-space-1", profileId: sourceProfileID)]
            ),
            categories: [.spaces],
            mode: .merge
        )

        let plan = SumiImportPlanBuilder().makePlan(
            request: request,
            baseline: SumiPortableData(profiles: [
                portableProfile(id: localProfileID, name: "Local"),
            ])
        )

        let importedProfileID = try XCTUnwrap(
            plan.profileTransition.sourceToTargetProfileID[sourceProfileID]
        )
        let importedSpace = try XCTUnwrap(
            plan.targetRuntimeData.spaces.first { $0.name == "Space" }
        )

        XCTAssertNotEqual(importedProfileID, localProfileID)
        XCTAssertEqual(importedSpace.profileId, importedProfileID)
        XCTAssertTrue(plan.categories.contains(.profiles))
        XCTAssertEqual(plan.targetRuntimeData.profiles.count, 2)

        let database = try SumiDatabase.inMemory()
        let localProfileUUID = try XCTUnwrap(UUID(uuidString: localProfileID))
        let importedProfileUUID = try XCTUnwrap(UUID(uuidString: importedProfileID))
        let importedSpaceUUID = try XCTUnwrap(UUID(uuidString: importedSpace.id))
        try database.transaction {
            try $0.profiles.save(
                ProfileRecord(id: localProfileUUID, name: "Local", index: 0)
            )
            try $0.profiles.save(
                ProfileRecord(id: importedProfileUUID, name: "Imported", index: 1)
            )
            try $0.workspace.save(
                SpaceRecord(
                    id: importedSpaceUUID,
                    profileID: importedProfileUUID,
                    name: importedSpace.name,
                    icon: importedSpace.icon,
                    index: importedSpace.index,
                    workspaceThemeData: nil
                )
            )
            try $0.profiles.delete(id: localProfileUUID)
        }
        let survivingSpaces = try database.read {
            try $0.workspace.spaces()
        }
        XCTAssertEqual(survivingSpaces.map(\.id), [importedSpaceUUID])
        XCTAssertEqual(survivingSpaces.first?.profileID, importedProfileUUID)
    }

    func testExternalBrowserReplaceRequestIsNormalizedToMerge() {
        let sourceKinds: [SumiImportSourceKind] = [
            .arc,
            .zen,
            .chromium,
            .firefox,
            .safari,
            .browser2zen,
        ]

        for sourceKind in sourceKinds {
            let localProfileID = UUID().uuidString
            let request = SumiImportRequest(
                sourceKind: sourceKind,
                data: SumiPortableData(
                    profiles: [
                        portableProfile(
                            id: "external-profile-1",
                            name: "Imported"
                        ),
                    ]
                ),
                categories: [.profiles],
                mode: .replace
            )

            let plan = SumiImportPlanBuilder().makePlan(
                request: request,
                baseline: SumiPortableData(profiles: [
                    portableProfile(id: localProfileID, name: "Local"),
                ])
            )

            XCTAssertEqual(plan.mode, .merge, "\(sourceKind)")
            XCTAssertTrue(
                plan.targetRuntimeData.profiles.contains {
                    $0.id == localProfileID
                },
                "\(sourceKind)"
            )
            XCTAssertTrue(
                plan.profileTransition.retiringProfileIDs.isEmpty,
                "\(sourceKind)"
            )
        }
    }
}
