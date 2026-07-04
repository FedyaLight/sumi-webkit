import XCTest

@testable import Sumi

@MainActor
final class TabRuntimeContextAttachmentOwnerTests: XCTestCase {
    func testAttachPreparesTabsDrainsPendingPinsRepairsSelectionAndRunsBootstrapHooks() {
        let profileId = UUID()
        let space = Space(name: "Current", profileId: profileId)
        let knownTab = Tab()
        let staleCurrentReference = Tab(id: knownTab.id)
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        )

        var attachedContext: TabManagerRuntimeContext?
        var preparedTabIds: [UUID] = []
        var drainedPendingPins = false
        var appendedPins: [ShortcutPin] = []
        var didSendObjectWillChange = false
        var didScheduleStructuralPersistence = false
        var replacedCurrentTab: Tab?
        var syncedSpaceIds: [UUID] = []
        var didReconcileSpaceProfiles = false

        let owner = TabRuntimeContextAttachmentOwner(
            dependencies: TabRuntimeContextAttachmentOwner.Dependencies(
                setRuntimeContext: { context in
                    attachedContext = context
                },
                allTabs: { [knownTab] },
                prepareTabForRuntime: { tab in
                    preparedTabIds.append(tab.id)
                },
                pendingPinnedWithoutProfileSnapshot: { [pendingPin] },
                drainPendingPinnedWithoutProfile: {
                    drainedPendingPins = true
                    return [pendingPin]
                },
                appendPinnedPins: { receivedProfileId, pins in
                    XCTAssertEqual(receivedProfileId, profileId)
                    appendedPins.append(contentsOf: pins)
                },
                sendObjectWillChange: {
                    didSendObjectWillChange = true
                },
                scheduleStructuralPersistence: {
                    didScheduleStructuralPersistence = true
                },
                currentTab: { staleCurrentReference },
                replaceCurrentTab: { tab in
                    replacedCurrentTab = tab
                },
                currentSpace: { space },
                reconcileSpaceProfilesIfNeeded: {
                    didReconcileSpaceProfiles = true
                }
            )
        )
        let context = TabManagerRuntimeContext(
            currentProfileId: { profileId },
            syncWorkspaceThemeAcrossWindows: { syncedSpace, animate in
                XCTAssertFalse(animate)
                syncedSpaceIds.append(syncedSpace.id)
            }
        )

        owner.attach(context)

        XCTAssertEqual(attachedContext?.currentProfileId, profileId)
        XCTAssertEqual(preparedTabIds, [knownTab.id])
        XCTAssertTrue(drainedPendingPins)
        XCTAssertEqual(appendedPins.map(\.id), [pendingPin.id])
        XCTAssertTrue(didSendObjectWillChange)
        XCTAssertTrue(didScheduleStructuralPersistence)
        XCTAssertIdentical(replacedCurrentTab, knownTab)
        XCTAssertEqual(syncedSpaceIds, [space.id])
        XCTAssertTrue(didReconcileSpaceProfiles)
    }
}
